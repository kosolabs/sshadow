from collections.abc import Callable
from pathlib import Path

from logwatch import APP, EXTENSION, LogWatcher, Matcher, msg
from sshadow import App, enable
from tree import File, Tree, make_tree, wait_for_tree


def brokered(profile: str) -> Matcher:
    return msg(rf"^XPC brokered: .*\bdisplayName: {profile}\b", subsystem=APP)


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


def test_rebroker_app(
    app: App,
    logs: LogWatcher,
    profile: str,
    remote: Path,
    relaunch_app: Callable[[], None],
) -> None:
    local = enable(app, logs, profile)
    tree = round_trip(app, logs, profile, local, remote, {})

    for _ in range(2):
        app.kill()
        logs.expect(msg(r"^Core XPC disconnected$", subsystem=EXTENSION))
        relaunch_app()
        logs.expect(brokered(profile), timeout=60)
        tree = round_trip(app, logs, profile, local, remote, tree)


def test_rebroker_extension(
    app: App, logs: LogWatcher, profile: str, remote: Path
) -> None:
    local = enable(app, logs, profile)
    tree = round_trip(app, logs, profile, local, remote, {})

    for _ in range(2):
        app.kill_extension()
        logs.expect(
            msg(rf"^XPC invalidated: .*\bdisplayName: {profile}\b", subsystem=APP)
        )
        logs.expect(brokered(profile), timeout=60)
        tree = round_trip(app, logs, profile, local, remote, tree)
