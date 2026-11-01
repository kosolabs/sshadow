import random
import threading
import time
from collections.abc import Callable
from pathlib import Path

import pytest

from logwatch import APP, EXTENSION, LogWatcher, Matcher, msg
from proxy import Proxy
from sshadow import (
    App,
    Profiles,
    brokered,
    connected,
    disable,
    enable,
    named,
    round_trip,
    uploading,
)
from tree import File, Tree, make_tree, wait_for, wait_for_tree

MiB = 1 << 20


def reconnecting(profile: str) -> Matcher:
    return msg(rf"^Session reconnecting: .*{named(profile)}")


def invalidated(profile: str) -> Matcher:
    return msg(rf"^XPC invalidated: .*{named(profile, 'displayName')}", subsystem=APP)


def suspended_by_extension(profile: str) -> Matcher:
    return msg(
        rf"^Sync suspended: .*{named(profile, 'displayName')}", subsystem=EXTENSION
    )


RETRYING = msg(r"^Connect failed; retrying in ")


# Multiple domains


def enable_domains(
    app: App, logs: LogWatcher, profiles: Profiles, paths: dict[str, Path]
) -> dict[str, Path]:
    """Create and enable a profile per name in `paths`, and return their local roots."""
    for name, path in paths.items():
        profiles.create(name, path=path)
    return {name: enable(app, logs, name) for name in paths}


@pytest.mark.parametrize("kill", ["app", "extension"])
def test_rebroker_domains(
    app: App,
    logs: LogWatcher,
    profiles: Profiles,
    remote: Path,
    relaunch_app: Callable[[], None],
    kill: str,
) -> None:
    remotes = {"Test-E2E-A": remote / "a", "Test-E2E-B": remote / "b"}
    roots = enable_domains(app, logs, profiles, remotes)
    trees = {
        name: round_trip(app, logs, name, roots[name], path, {})
        for name, path in remotes.items()
    }

    for _ in range(2):
        if kill == "app":
            app.kill()
            logs.expect_all([suspended_by_extension(name) for name in remotes])
            # File Provider restarts each domain after its extension suspends
            # it, and can lose a reconnect that arrives mid-restart.
            time.sleep(2)
            relaunch_app()
        else:
            app.kill_extension()
            logs.expect_all([invalidated(name) for name in remotes])
        logs.expect_all([brokered(name) for name in remotes], timeout=60)
        for name, path in remotes.items():
            trees[name] = round_trip(app, logs, name, roots[name], path, trees[name])


def test_disable_one_domain(
    app: App, logs: LogWatcher, profiles: Profiles, remote: Path
) -> None:
    remotes = {"Test-E2E-A": remote / "a", "Test-E2E-B": remote / "b"}
    roots = enable_domains(app, logs, profiles, remotes)
    (a, b) = remotes
    trees = {
        name: round_trip(app, logs, name, roots[name], path, {})
        for name, path in remotes.items()
    }

    disable(app, logs, b)
    trees[a] = round_trip(app, logs, a, roots[a], remotes[a], trees[a])
    wait_for_tree(remotes[b], trees[b], on_poll=logs.check)

    roots[b] = enable(app, logs, b)
    wait_for_tree(roots[b], trees[b], on_poll=logs.check)
    for name, path in remotes.items():
        trees[name] = round_trip(app, logs, name, roots[name], path, trees[name])


# Server inaccessible


def test_reconnect_after_drop(
    app: App, logs: LogWatcher, proxy: Proxy, proxied_profile: str, remote: Path
) -> None:
    name = proxied_profile
    local = enable(app, logs, name)
    tree = round_trip(app, logs, name, local, remote, {})

    proxy.drop()
    app.send("poll", name=name)
    logs.expect(reconnecting(name), timeout=30)
    logs.expect(connected(name), timeout=30)
    round_trip(app, logs, name, local, remote, tree)


def test_reconnect_after_outage(
    app: App, logs: LogWatcher, proxy: Proxy, proxied_profile: str, remote: Path
) -> None:
    name = proxied_profile
    local = enable(app, logs, name)
    tree = round_trip(app, logs, name, local, remote, {})

    proxy.refuse()
    app.send("poll", name=name)
    logs.expect(reconnecting(name), timeout=30)
    logs.expect(RETRYING, timeout=30)
    logs.expect(RETRYING, timeout=30)

    offline: Tree = {"offline.txt": File(b"written while the server was down\n")}
    make_tree(local, offline)
    tree = tree | offline

    proxy.restore()
    logs.expect(connected(name), timeout=60)
    wait_for_tree(remote, tree, timeout=60, on_poll=logs.check)
    round_trip(app, logs, name, local, remote, tree)


def test_drop_during_upload(
    app: App, logs: LogWatcher, proxy: Proxy, proxied_profile: str, remote: Path
) -> None:
    name = proxied_profile
    proxy.rate = MiB
    local = enable(app, logs, name)
    tree: Tree = {"big.bin": File(random.Random(0).randbytes(8 * MiB))}
    make_tree(local, tree)
    logs.expect(uploading("big.bin"), timeout=30)
    time.sleep(1)

    proxy.drop()
    logs.expect(reconnecting(name), timeout=30)
    logs.expect(connected(name), timeout=30)
    proxy.rate = None
    wait_for_tree(remote, tree, timeout=60, on_poll=logs.check)
    wait_for_tree(local, tree, on_poll=logs.check)
    round_trip(app, logs, name, local, remote, tree)


def test_drop_during_download(
    app: App, logs: LogWatcher, proxy: Proxy, proxied_profile: str, remote: Path
) -> None:
    name = proxied_profile
    proxy.rate = MiB
    data = random.Random(0).randbytes(8 * MiB)
    tree: Tree = {"big.bin": File(data)}
    make_tree(remote, tree)
    local = enable(app, logs, name)
    path = local / "big.bin"
    wait_for(lambda: "" if path.exists() else f"{path} doesn't exist")

    result: list[bytes | OSError] = []

    def read() -> None:
        try:
            result.append(path.read_bytes())
        except OSError as e:
            result.append(e)

    reader = threading.Thread(target=read, daemon=True)
    reader.start()
    logs.expect(msg(r"^Fetch partial contents of "), timeout=30)
    time.sleep(1)

    proxy.drop()
    logs.expect(reconnecting(name), timeout=30)
    logs.expect(connected(name), timeout=30)
    proxy.rate = None
    reader.join(timeout=60)
    assert not reader.is_alive(), "read didn't finish within 60s of reconnecting"
    if isinstance(result[0], bytes):
        assert result[0] == data, "read returned corrupt contents"
    wait_for_tree(local, tree, on_poll=logs.check)
    round_trip(app, logs, name, local, remote, tree)
