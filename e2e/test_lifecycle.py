import random
import subprocess
import time
from collections.abc import Callable
from pathlib import Path

import pytest

from logwatch import LogWatcher
from proxy import Proxy
from sshadow import (
    PROFILE_NAME,
    App,
    Profiles,
    brokered,
    connected,
    disable,
    enable,
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


def assert_not_truncated(path: Path, contents: bytes) -> None:
    """Check that an interrupted upload left either nothing or all of `contents`."""
    # Give an upload that's still running time to show up.
    time.sleep(2)
    if path.exists():
        size = path.stat().st_size
        assert size == len(contents), (
            f"{path} is truncated: {size} of {len(contents)} bytes"
        )
        assert path.read_bytes() == contents, f"{path} is corrupt"


def remote_tree(path: Path, contents: bytes) -> Tree:
    return {path.name: File(contents)} if path.exists() else {}


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


@pytest.mark.skip(reason="not implemented yet")
def test_disable_during_upload(
    app: App, logs: LogWatcher, proxy: Proxy, proxied_profile: str, remote: Path
) -> None:
    proxy.rate = MiB
    local = enable(app, logs, proxied_profile)
    data = random.Random(0).randbytes(32 * MiB)
    make_tree(local, {"big.bin": File(data)})
    logs.expect(uploading("big.bin"), timeout=30)

    disable(app, logs, proxied_profile, timeout=10)
    assert_not_truncated(remote / "big.bin", data)

    proxy.rate = None
    local = enable(app, logs, proxied_profile)
    tree = remote_tree(remote / "big.bin", data)
    wait_for_tree(local, tree, on_poll=logs.check)
    round_trip(app, logs, proxied_profile, local, remote, tree)


@pytest.mark.skip(reason="not implemented yet")
def test_delete_during_upload(
    app: App,
    logs: LogWatcher,
    proxy: Proxy,
    profiles: Profiles,
    proxied_profile: str,
    remote: Path,
) -> None:
    proxy.rate = MiB
    local = enable(app, logs, proxied_profile)
    data = random.Random(0).randbytes(32 * MiB)
    make_tree(local, {"big.bin": File(data)})
    logs.expect(uploading("big.bin"), timeout=30)

    profiles.delete(proxied_profile, timeout=10)
    assert_not_truncated(remote / "big.bin", data)

    proxy.rate = None
    profiles.create(PROFILE_NAME, host="127.0.0.1", port=proxy.port)
    local = enable(app, logs, PROFILE_NAME)
    tree = remote_tree(remote / "big.bin", data)
    wait_for_tree(local, tree, on_poll=logs.check)
    round_trip(app, logs, PROFILE_NAME, local, remote, tree)


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
