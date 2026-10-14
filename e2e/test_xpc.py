from collections.abc import Callable
from pathlib import Path

import pytest

from logwatch import APP, EXTENSION, LogWatcher, Matcher, msg
from sshadow import App, enable
from tree import File, Tree, make_tree, wait_for_tree

Bounce = Callable[[App, LogWatcher, str], None]


def brokered(profile: str) -> Matcher:
    return msg(rf"^XPC brokered: .*\bdisplayName: {profile}\b", subsystem=APP)


def bounce_extension(app: App, logs: LogWatcher, profile: str) -> None:
    """Kill the extension, which the app should notice and broker again."""
    app.kill_extension()
    logs.expect(msg(rf"^XPC invalidated: .*\bdisplayName: {profile}\b", subsystem=APP))
    # Brokering launches the extension again.
    logs.expect(brokered(profile), timeout=60)


def bounce_app(app: App, logs: LogWatcher, profile: str) -> None:
    """Kill the app, which should broker again once it's relaunched."""
    app.kill()
    try:
        logs.expect(msg(r"^Core XPC disconnected$", subsystem=EXTENSION))
    finally:
        # Later tests share the app, so relaunch it even if this test fails.
        app.launch()
    logs.expect(msg(r"^URL commands enabled$"))
    logs.expect(brokered(profile), timeout=60)


def round_trip(
    app: App, logs: LogWatcher, profile: str, local: Path, remote: Path, tree: Tree
) -> Tree:
    """Sync a new file each way, which only works if the extension can reach the app."""
    n = len(tree)
    upload: Tree = {f"upload-{n}.txt": File(f"upload {n}\n".encode())}
    make_tree(local, upload)
    tree = tree | upload
    wait_for_tree(remote, tree, on_poll=logs.check)

    download: Tree = {f"download-{n}.txt": File(f"download {n}\n".encode())}
    make_tree(remote, download)
    tree = tree | download
    app.send("poll", name=profile)
    wait_for_tree(local, tree, on_poll=logs.check)
    return tree


@pytest.mark.parametrize(
    "bounce", [bounce_extension, bounce_app], ids=["extension", "app"]
)
def test_rebroker(
    app: App, logs: LogWatcher, profile: str, remote: Path, bounce: Bounce
) -> None:
    local = enable(app, logs, profile)
    tree = round_trip(app, logs, profile, local, remote, {})

    # Twice, since the connection brokered after a bounce must survive one too.
    for _ in range(2):
        bounce(app, logs, profile)
        tree = round_trip(app, logs, profile, local, remote, tree)
