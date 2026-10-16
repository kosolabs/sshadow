import random
import subprocess
import time
from collections.abc import Callable
from pathlib import Path

from logwatch import LogWatcher
from proxy import Proxy
from sshadow import (
    App,
    brokered,
    connected,
    disable,
    enable,
    pause,
    round_trip,
    uploading,
)
from tree import Dir, File, Tree, make_tree, wait_for_tree

MiB = 1 << 20

TREE: Tree = {
    "hello.txt": File(b"hello, world\n"),
    "docs": Dir(),
    "docs/readme.md": File(b"# Readme\n"),
}


def test_quit_and_relaunch(
    app: App,
    logs: LogWatcher,
    profile: str,
    remote: Path,
    relaunch_app: Callable[[], None],
) -> None:
    local = enable(app, logs, profile)
    make_tree(local, TREE)
    tree = round_trip(app, logs, profile, local, remote, TREE)

    app.quit()
    remote_change: Tree = {"remote-while-quit.txt": File(b"changed on the server\n")}
    make_tree(remote, remote_change)
    local_change: Tree = {"local-while-quit.txt": File(b"changed locally\n")}
    make_tree(local, local_change)
    tree = tree | remote_change | local_change

    relaunch_app()
    logs.expect_all([brokered(profile), connected(profile)], timeout=60)
    app.send("poll", name=profile)
    wait_for_tree(remote, tree, timeout=60, on_poll=logs.check)
    wait_for_tree(local, tree, on_poll=logs.check)
    round_trip(app, logs, profile, local, remote, tree)


def test_disable_and_enable(
    app: App, logs: LogWatcher, profile: str, remote: Path
) -> None:
    local = enable(app, logs, profile)
    make_tree(local, TREE)
    wait_for_tree(remote, TREE, on_poll=logs.check)

    disable(app, logs, profile)
    wait_for_tree(remote, TREE, on_poll=logs.check)

    local = enable(app, logs, profile)
    wait_for_tree(local, TREE, on_poll=logs.check)
    round_trip(app, logs, profile, local, remote, TREE)


def test_pause_during_upload(
    app: App, logs: LogWatcher, proxy: Proxy, proxied_profile: str, remote: Path
) -> None:
    proxy.rate = MiB
    local = enable(app, logs, proxied_profile)
    data = random.Random(0).randbytes(32 * MiB)
    tree: Tree = {"big.bin": File(data)}
    make_tree(local, tree)
    logs.expect(uploading("big.bin"), timeout=30)
    time.sleep(1)

    pause(app, logs, proxied_profile, timeout=10)
    proxy.rate = None
    # Resume, as the menu's Resume button does.
    enable(app, logs, proxied_profile)
    wait_for_tree(remote, tree, timeout=60, on_poll=logs.check)
    wait_for_tree(local, tree, on_poll=logs.check)
    round_trip(app, logs, proxied_profile, local, remote, tree)


def test_kill_fileproviderd_during_upload(
    app: App, logs: LogWatcher, proxy: Proxy, proxied_profile: str, remote: Path
) -> None:
    proxy.rate = 4 * MiB
    local = enable(app, logs, proxied_profile)
    data = random.Random(0).randbytes(32 * MiB)
    tree: Tree = {"big.bin": File(data)}
    make_tree(local, tree)
    logs.expect(uploading("big.bin"), timeout=30)

    subprocess.run(["killall", "-KILL", "fileproviderd"], check=True)
    proxy.rate = None
    wait_for_tree(remote, tree, timeout=120, on_poll=logs.check)
    wait_for_tree(local, tree, on_poll=logs.check)
    round_trip(app, logs, proxied_profile, local, remote, tree)
