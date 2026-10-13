import ctypes
import getpass
import json
import plistlib
import re
import shutil
import subprocess
import time
from collections.abc import Generator
from pathlib import Path
from typing import Any

import pytest

from logwatch import LogWatcher, msg
from sshadow import REPO, App, find_app

PREDICATE = 'subsystem BEGINSWITH "com.kosolabs.SSHadow"'
LOG_DIR = REPO / "logs"
TEST_KEY = REPO / "CommonTests" / "id_ed25519"
PROFILE_NAME = "Test-E2E"
APPROVAL_PROFILE_NAME = "Test-E2E-Approval"
REMOTE_ROOT = Path("/tmp/sshadow")
DOMAINS_PLIST = (
    Path.home()
    / "Library/Application Support/FileProvider/com.kosolabs.SSHadow.Extension/Domains.plist"
)
DEFAULT_DOMAIN = "NSFileProviderDomainDefaultIdentifier"


# From <sys/resource.h>.
IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES = 3
IOPOL_SCOPE_PROCESS = 0
IOPOL_MATERIALIZE_DATALESS_FILES_ON = 2


def pytest_configure(config: pytest.Config) -> None:
    # Reading File Provider files that aren't downloaded yet fails with EDEADLK
    # unless the process may materialize them, which background processes such
    # as CI runners may not by default.
    libc = ctypes.CDLL(None, use_errno=True)
    before = libc.getiopolicy_np(
        IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_PROCESS
    )
    if libc.setiopolicy_np(
        IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES,
        IOPOL_SCOPE_PROCESS,
        IOPOL_MATERIALIZE_DATALESS_FILES_ON,
    ):
        raise OSError(ctypes.get_errno(), "setiopolicy_np failed")
    print(
        f"Dataless file materialization policy: {before} -> {IOPOL_MATERIALIZE_DATALESS_FILES_ON}"
    )


@pytest.fixture
def logs() -> Generator[LogWatcher]:
    watcher = LogWatcher(PREDICATE)
    yield watcher
    watcher.close()


@pytest.fixture(scope="session")
def key(tmp_path_factory: pytest.TempPathFactory) -> Path:
    key = tmp_path_factory.mktemp("key") / "id_ed25519"
    shutil.copy(TEST_KEY, key)
    return key.resolve()


@pytest.fixture(scope="session")
def app(key: Path) -> Generator[App]:
    app = App(find_app())
    watcher = LogWatcher(PREDICATE)
    try:
        app.launch(files=[key])
        watcher.expect(msg("^URL commands enabled$"))
        watcher.expect(msg(rf"^Opened file: {re.escape(str(key))}$"))
        approve_file_provider(app, watcher, key)
    except (RuntimeError, TimeoutError) as e:
        pytest.fail(str(e), pytrace=False)
    finally:
        watcher.close()
    yield app
    app.quit()


def read_domains() -> dict[str, Any]:
    try:
        with DOMAINS_PLIST.open("rb") as f:
            return plistlib.load(f)
    except FileNotFoundError:
        return {}
    except PermissionError as e:
        raise RuntimeError(
            f"Can't read {DOMAINS_PLIST}. Give the terminal running the tests Full Disk Access."
        ) from e


def domain_named(name: str, timeout: float = 30) -> str:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        for identifier, domain in read_domains().items():
            if identifier != DEFAULT_DOMAIN and domain.get("DisplayName") == name:
                return identifier
        time.sleep(0.5)
    raise TimeoutError(f"no File Provider domain named {name} within {timeout}s")


def approve_file_provider(app: App, logs: LogWatcher, key: Path) -> None:
    """Approve SSHadow's File Provider, as clicking Enable in Finder does.

    A new File Provider's domains stay disabled until the user clicks Enable
    in Finder, which is only needed once. There's no API for it, so enable a
    throwaway domain in fileproviderd's settings and restart it.
    """
    if read_domains().get(DEFAULT_DOMAIN, {}).get("Enabled"):
        return

    create_profile(app, logs, APPROVAL_PROFILE_NAME, key)
    app.send("enable", name=APPROVAL_PROFILE_NAME)
    domain = domain_named(APPROVAL_PROFILE_NAME)
    for key_path in (f"{domain}.Enabled", f"{DEFAULT_DOMAIN}.Enabled"):
        subprocess.run(
            ["plutil", "-replace", key_path, "-bool", "YES", DOMAINS_PLIST], check=True
        )
    # SIGKILL so fileproviderd can't save its old settings over the change.
    # launchd starts it again on demand.
    subprocess.run(["killall", "-KILL", "fileproviderd"], check=True)
    logs.expect(
        msg(rf"Profile enabled: .*\bname: {APPROVAL_PROFILE_NAME}\b"), timeout=60
    )

    app.send("delete", name=APPROVAL_PROFILE_NAME)
    logs.expect(msg(rf"Profile deleted: .*\bname: {APPROVAL_PROFILE_NAME}\b"))


def create_profile(app: App, logs: LogWatcher, name: str, key: Path) -> None:
    REMOTE_ROOT.mkdir(exist_ok=True)
    app.send(
        "create",
        name=name,
        host="localhost",
        port=2248,
        user=getpass.getuser(),
        path=REMOTE_ROOT,
        key=key,
    )
    logs.expect(msg(rf"Profile created: .*\bname: {name}\b"))


@pytest.fixture
def remote() -> Path:
    """The profile's directory on the test server, emptied."""
    shutil.rmtree(REMOTE_ROOT, ignore_errors=True)
    REMOTE_ROOT.mkdir()
    return REMOTE_ROOT


@pytest.fixture
def profile(app: App, logs: LogWatcher, remote: Path, key: Path) -> Generator[str]:
    """Create a profile for the test server, and delete it afterwards."""
    create_profile(app, logs, PROFILE_NAME, key)
    yield PROFILE_NAME

    app.send("delete", name=PROFILE_NAME)
    logs.expect(msg(rf"Profile deleted: .*\bname: {PROFILE_NAME}\b"))


@pytest.hookimpl(wrapper=True)
def pytest_runtest_makereport(
    item: pytest.Item, call: pytest.CallInfo[None]
) -> Generator[None, pytest.TestReport, pytest.TestReport]:
    """Save every event a failed test's watcher received under logs/."""
    report = yield
    funcargs: dict[str, object] = getattr(item, "funcargs", {})
    watcher = funcargs.get("logs")
    if report.when == "call" and report.failed and isinstance(watcher, LogWatcher):
        watcher.drain()
        LOG_DIR.mkdir(exist_ok=True)
        path = LOG_DIR / f"e2e-{item.name}.log"
        path.write_text("".join(json.dumps(e) + "\n" for e in watcher.seen))
        report.sections.append(("log events", str(path)))
    return report
