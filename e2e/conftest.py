import getpass
import json
import shutil
from collections.abc import Generator
from pathlib import Path

import pytest

from logwatch import LogWatcher, msg
from sshadow import REPO, App, find_app

LOG_DIR = REPO / "logs"
TEST_KEY = REPO / "CommonTests" / "id_ed25519"
PROFILE_NAME = "Test-E2E"
REMOTE_ROOT = Path("/tmp/sshadow")


@pytest.fixture
def logs() -> Generator[LogWatcher]:
    watcher = LogWatcher('subsystem BEGINSWITH "com.kosolabs.SSHadow"')
    yield watcher
    watcher.close()


@pytest.fixture(scope="session")
def app() -> Generator[App]:
    """The app under test, quit afterwards if the tests launched it."""
    app = App(find_app())
    started = app.started()
    if started is not None and started < app.built():
        pytest.fail(
            f"SSHadow is running an older build than {app.path}. Quit it and rerun.",
            pytrace=False,
        )
    yield app
    if started is None:
        app.quit()


@pytest.fixture
def remote() -> Path:
    """The profile's directory on the test server, emptied."""
    shutil.rmtree(REMOTE_ROOT, ignore_errors=True)
    REMOTE_ROOT.mkdir()
    return REMOTE_ROOT


@pytest.fixture
def profile(app: App, logs: LogWatcher, remote: Path, tmp_path: Path) -> Generator[str]:
    """Create a profile for the test server, and delete it afterwards."""
    key = tmp_path / "id_ed25519"
    shutil.copy(TEST_KEY, key)

    app.open(
        "create",
        files=[key],
        name=PROFILE_NAME,
        host="localhost",
        port=2248,
        user=getpass.getuser(),
        path=remote,
        key=key,
    )
    logs.expect(msg(rf"Profile created: .*\bname: {PROFILE_NAME}\b"))
    yield PROFILE_NAME

    app.open("delete", name=PROFILE_NAME)
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
