import ctypes
import getpass
import json
import re
import shutil
from collections.abc import Generator
from pathlib import Path

import pytest

from logwatch import LogWatcher, msg
from sshadow import REPO, App, find_app

PREDICATE = 'subsystem BEGINSWITH "com.kosolabs.SSHadow"'
LOG_DIR = REPO / "logs"
TEST_KEY = REPO / "CommonTests" / "id_ed25519"
PROFILE_NAME = "Test-E2E"
REMOTE_ROOT = Path("/tmp/sshadow")


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
    except (RuntimeError, TimeoutError) as e:
        pytest.fail(str(e), pytrace=False)
    finally:
        watcher.close()
    yield app
    app.quit()


@pytest.fixture
def remote() -> Path:
    """The profile's directory on the test server, emptied."""
    shutil.rmtree(REMOTE_ROOT, ignore_errors=True)
    REMOTE_ROOT.mkdir()
    return REMOTE_ROOT


@pytest.fixture
def profile(app: App, logs: LogWatcher, remote: Path, key: Path) -> Generator[str]:
    """Create a profile for the test server, and delete it afterwards."""
    app.send(
        "create",
        name=PROFILE_NAME,
        host="localhost",
        port=2248,
        user=getpass.getuser(),
        path=remote,
        key=key,
    )
    logs.expect(msg(rf"Profile created: .*\bname: {PROFILE_NAME}\b"))
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
