import re
import subprocess
from collections.abc import Generator
from pathlib import Path

import pytest

from conftest import launch
from logwatch import APP, LogWatcher, fault, msg
from sshadow import App, disable, enable, unregister


@pytest.fixture
def other_copy(app: App, tmp_path: Path) -> Generator[App]:
    """A copy of the app under test at another path, removed afterwards."""
    path = tmp_path / "SSHadow.app"
    subprocess.run(["ditto", app.path, path], check=True)
    other = App(path)
    yield other
    if other.started() is not None:
        other.kill()
    unregister(other.path)
    app.make_only_copy()


@pytest.mark.usefixtures("relaunch_app")
def test_refuses_extension_from_another_copy(
    app: App,
    logs: LogWatcher,
    key: Path,
    profile: str,
    other_copy: App,
) -> None:
    # Start this copy's extension, so File Provider keeps running it for the
    # other copy too.
    enable(app, logs, profile)
    disable(app, logs, profile)
    app.quit()

    launch(other_copy, logs, key)
    other_copy.send("enable", name=profile)

    refused = msg(
        rf"^Refused extension .*from {re.escape(str(app.path))}/", subsystem=APP
    )
    brokered = msg(r"^XPC brokered", subsystem=APP)
    event = logs.expect(lambda e: refused(e) or brokered(e), fail=(fault,), timeout=60)
    assert refused(event), (
        "File Provider ran the other copy's own extension, so the test didn't "
        "reproduce another copy's extension connecting."
    )
    logs.expect(
        msg(r"^Sync suspended: .*Another copy of SSHadow is interfering", subsystem=APP),
        fail=(fault,),
    )
