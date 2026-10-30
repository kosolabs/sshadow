import ctypes
import plistlib
import re
import shutil
import subprocess
import time
from collections.abc import Callable, Generator
from pathlib import Path
from typing import Any

import pytest

from logwatch import LogWatcher, msg
from proxy import Proxy
from sshadow import (
    PROFILE_NAME,
    REMOTE_ROOT,
    REPO,
    SERVER_PORT,
    App,
    Profiles,
    create_profile,
    find_app,
)

PREDICATE = 'subsystem BEGINSWITH "com.kosolabs.SSHadow"'
LOG_DIR = REPO / "logs"
TEST_KEY = REPO / "TestKit" / "id_ed25519"
APPROVAL_PROFILE_NAME = "Test-E2E-Approval"
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


log_stream: subprocess.Popen[bytes] | None = None


def pytest_sessionstart(session: pytest.Session) -> None:
    """Record the session's log events to logs/e2e.log."""
    global log_stream
    LOG_DIR.mkdir(exist_ok=True)
    path = LOG_DIR / "e2e.log"
    with path.open("wb") as f:
        log_stream = subprocess.Popen(
            [
                "log",
                "stream",
                "--style",
                "ndjson",
                "--level",
                "debug",
                "--predicate",
                f'{PREDICATE} OR process == "logger"',
            ],
            stdout=f,
            stderr=subprocess.STDOUT,
        )
    deadline = time.monotonic() + 10
    while path.stat().st_size == 0 and time.monotonic() < deadline:
        time.sleep(0.1)


def pytest_sessionfinish(session: pytest.Session) -> None:
    if log_stream is not None:
        log_stream.terminate()
        log_stream.wait(timeout=5)


def pytest_runtest_logstart(nodeid: str, location: tuple[str, int | None, str]) -> None:
    subprocess.run(["logger", f"e2e start: {nodeid}"], check=True)


test_outcomes: dict[str, str] = {}


def pytest_runtest_logreport(report: pytest.TestReport) -> None:
    if not report.passed and report.nodeid not in test_outcomes:
        test_outcomes[report.nodeid] = f"{report.outcome} in {report.when}"


def pytest_runtest_logfinish(
    nodeid: str, location: tuple[str, int | None, str]
) -> None:
    outcome = test_outcomes.pop(nodeid, "passed")
    subprocess.run(["logger", f"e2e finish ({outcome}): {nodeid}"], check=True)


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
    app.make_only_copy()
    watcher = LogWatcher(PREDICATE)
    try:
        launch(app, watcher, key)
        approve_file_provider(app, watcher, key)
    except (RuntimeError, TimeoutError) as e:
        pytest.fail(str(e), pytrace=False)
    finally:
        watcher.close()
    yield app
    app.quit()


def launch(app: App, logs: LogWatcher, key: Path) -> None:
    app.launch(files=[key])
    logs.expect_all(
        [
            msg("^Test commands enabled$"),
            msg(rf"^Started from {re.escape(str(app.path))}/? "),
        ]
    )
    logs.expect(msg(rf"^Opened file: {re.escape(str(key))}$"))


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


@pytest.fixture
def remote() -> Path:
    """The profile's directory on the test server, emptied."""
    shutil.rmtree(REMOTE_ROOT, ignore_errors=True)
    REMOTE_ROOT.mkdir()
    return REMOTE_ROOT


@pytest.fixture
def profiles(
    app: App, logs: LogWatcher, remote: Path, key: Path
) -> Generator[Profiles]:
    profiles = Profiles(app, logs, key)
    yield profiles
    profiles.delete_all()


@pytest.fixture
def relaunch_app(
    app: App, logs: LogWatcher, key: Path, profiles: Profiles
) -> Generator[Callable[[], None]]:
    yield lambda: launch(app, logs, key)
    if app.started() is None:
        launch(app, logs, key)


@pytest.fixture
def profile(profiles: Profiles) -> str:
    """Create a profile for the test server, and delete it afterwards."""
    return profiles.create(PROFILE_NAME)


@pytest.fixture
def proxy() -> Generator[Proxy]:
    """A proxy in front of the test server, for simulating network failures."""
    proxy = Proxy(("127.0.0.1", SERVER_PORT))
    yield proxy
    proxy.close()


@pytest.fixture
def proxied_profile(proxy: Proxy, profiles: Profiles) -> Generator[str]:
    """Create a profile that reaches the test server through `proxy`."""
    yield profiles.create(PROFILE_NAME, host="127.0.0.1", port=proxy.port)
    proxy.rate = None
    proxy.restore()
