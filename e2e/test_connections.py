import os
import random
import shutil
import signal
import socket
import subprocess
import threading
import time
from collections.abc import Callable, Generator
from pathlib import Path

import pytest

from logwatch import APP, EXTENSION, LogWatcher, Matcher, msg
from proxy import Proxy
from sshadow import (
    PROFILE_NAME,
    REPO,
    SERVER_PORT,
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
from tree import Dir, File, Tree, make_tree, wait_for, wait_for_tree

MiB = 1 << 20


def reconnecting(profile: str) -> Matcher:
    return msg(rf"^Session reconnecting: .*{named(profile)}")


def gave_up(profile: str) -> Matcher:
    return msg(rf"^Reconnect cancelled: .*{named(profile)}")


def invalidated(profile: str) -> Matcher:
    return msg(rf"^XPC invalidated: .*{named(profile, 'displayName')}", subsystem=APP)


RETRYING = msg(r"^Connect failed; retrying in ")
CONNECT_ATTEMPT = msg(r"^(Failed to connect SSH config|SSH config connected)")


# Multiple domains


def enable_domains(
    app: App, logs: LogWatcher, profiles: Profiles, paths: dict[str, Path]
) -> dict[str, Path]:
    """Create and enable a profile per name in `paths`, and return their local roots."""
    for name, path in paths.items():
        profiles.create(name, path=path)
    return {name: enable(app, logs, name) for name in paths}


def test_domains_are_isolated(
    app: App, logs: LogWatcher, profiles: Profiles, remote: Path
) -> None:
    remotes = {"Test-E2E-A": remote / "a", "Test-E2E-B": remote / "b"}
    roots = enable_domains(app, logs, profiles, remotes)
    (a, b) = remotes

    trees: dict[str, Tree] = {
        a: {"hello.txt": File(b"hello from A\n"), "only-a": Dir()},
        b: {"hello.txt": File(b"hello from B\n"), "only-b": Dir()},
    }
    make_tree(roots[a], trees[a])
    make_tree(remotes[b], trees[b])
    app.send("poll", name=a)
    app.send("poll", name=b)
    for name, path in remotes.items():
        wait_for_tree(path, trees[name], on_poll=logs.check)
        wait_for_tree(roots[name], trees[name], on_poll=logs.check)

    edits: dict[str, Tree] = {
        a: {"hello.txt": File(b"edited on A's server\n")},
        b: {"hello.txt": File(b"edited in B's folder\n")},
    }
    make_tree(remotes[a], edits[a])
    make_tree(roots[b], edits[b])
    app.send("poll", name=a)
    app.send("poll", name=b)
    for name, path in remotes.items():
        trees[name] |= edits[name]
        wait_for_tree(path, trees[name], on_poll=logs.check)
        wait_for_tree(roots[name], trees[name], on_poll=logs.check)


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
            logs.expect(msg(r"^Core XPC disconnected$", subsystem=EXTENSION))
            relaunch_app()
        else:
            app.kill_extension()
            logs.expect_all([invalidated(name) for name in remotes])
        logs.expect_all([brokered(name) for name in remotes], timeout=60)
        for name, path in remotes.items():
            trees[name] = round_trip(app, logs, name, roots[name], path, trees[name])


def test_nested_domains(
    app: App, logs: LogWatcher, profiles: Profiles, remote: Path
) -> None:
    outer, inner = "Test-E2E-Outer", "Test-E2E-Inner"
    roots = enable_domains(
        app, logs, profiles, {outer: remote, inner: remote / "inner"}
    )

    from_inner: Tree = {"from-inner.txt": File(b"from the inner domain\n")}
    make_tree(roots[inner], from_inner)
    wait_for_tree(remote / "inner", from_inner, on_poll=logs.check)
    app.send("poll", name=outer)
    wait_for_tree(
        roots[outer],
        {"inner": Dir(), "inner/from-inner.txt": from_inner["from-inner.txt"]},
        on_poll=logs.check,
    )

    from_outer: Tree = {"from-outer.txt": File(b"from the outer domain\n")}
    make_tree(roots[outer] / "inner", from_outer)
    both = from_inner | from_outer
    wait_for_tree(remote / "inner", both, on_poll=logs.check)
    app.send("poll", name=inner)
    wait_for_tree(roots[inner], both, on_poll=logs.check)

    (roots[inner] / "from-outer.txt").unlink()
    wait_for_tree(remote / "inner", from_inner, on_poll=logs.check)
    app.send("poll", name=outer)
    wait_for_tree(
        roots[outer],
        {"inner": Dir(), "inner/from-inner.txt": from_inner["from-inner.txt"]},
        on_poll=logs.check,
    )


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


@pytest.mark.skip(reason="not implemented yet")
def test_reconnect_after_blackhole(
    app: App, logs: LogWatcher, proxy: Proxy, proxied_profile: str, remote: Path
) -> None:
    name = proxied_profile
    local = enable(app, logs, name)
    tree = round_trip(app, logs, name, local, remote, {})

    proxy.blackhole()
    app.send("poll", name=name)
    logs.expect(reconnecting(name), timeout=120)

    proxy.restore()
    logs.expect(connected(name), timeout=120)
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


def test_enable_while_server_down(
    app: App, logs: LogWatcher, proxy: Proxy, proxied_profile: str, remote: Path
) -> None:
    name = proxied_profile
    proxy.refuse()
    app.send("enable", name=name)
    logs.expect(msg(rf"^Failed to enable .*{named(name)}"), timeout=60)

    proxy.restore()
    local = enable(app, logs, name)
    round_trip(app, logs, name, local, remote, {})


@pytest.mark.skip(reason="not implemented yet")
def test_relaunch_while_server_down(
    app: App,
    logs: LogWatcher,
    proxy: Proxy,
    proxied_profile: str,
    remote: Path,
    relaunch_app: Callable[[], None],
) -> None:
    name = proxied_profile
    local = enable(app, logs, name)
    tree = round_trip(app, logs, name, local, remote, {})

    app.quit()
    proxy.refuse()
    relaunch_app()
    logs.expect(msg(rf"^Failed to enable .*{named(name, 'displayName')}"), timeout=60)

    proxy.restore()
    logs.expect(connected(name), timeout=90)
    round_trip(app, logs, name, local, remote, tree)


def test_missing_remote_path_stops_retrying(
    app: App, logs: LogWatcher, proxy: Proxy, profiles: Profiles, remote: Path
) -> None:
    root = remote / "root"
    name = profiles.create(PROFILE_NAME, path=root, host="127.0.0.1", port=proxy.port)
    local = enable(app, logs, name)
    round_trip(app, logs, name, local, root, {})

    proxy.drop()
    shutil.rmtree(root)
    app.send("poll", name=name)
    logs.expect(reconnecting(name), timeout=30)
    logs.expect(gave_up(name), timeout=30)
    logs.expect_none(CONNECT_ATTEMPT, timeout=10)

    root.mkdir()
    disable(app, logs, name)
    local = enable(app, logs, name)
    round_trip(app, logs, name, local, root, {})


@pytest.fixture
def locked_server(tmp_path: Path) -> Generator[int]:
    """Another test server, which accepts no keys, and return its port."""
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        port = s.getsockname()[1]
    pid_file = tmp_path / "sshd.pid"
    host_key = tmp_path / "host_key_ed25519"
    subprocess.run(
        ["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", host_key], check=True
    )
    subprocess.run(
        [
            "/usr/sbin/sshd",
            "-f",
            REPO / "ci_scripts/test_server/sshd_config",
            "-p",
            str(port),
            "-E",
            tmp_path / "sshd.log",
            "-h",
            host_key,
            "-o",
            f"PidFile {pid_file}",
            "-o",
            "AuthorizedKeysFile none",
        ],
        check=True,
    )
    wait_for(lambda: "" if pid_file.exists() else "sshd didn't start", timeout=5)
    yield port
    os.kill(int(pid_file.read_text()), signal.SIGTERM)


def test_rejected_key_stops_retrying(
    app: App,
    logs: LogWatcher,
    proxy: Proxy,
    proxied_profile: str,
    remote: Path,
    locked_server: int,
) -> None:
    name = proxied_profile
    local = enable(app, logs, name)
    tree = round_trip(app, logs, name, local, remote, {})

    proxy.upstream = ("127.0.0.1", locked_server)
    proxy.drop()
    app.send("poll", name=name)
    logs.expect(reconnecting(name), timeout=30)
    logs.expect(gave_up(name), timeout=30)
    logs.expect_none(CONNECT_ATTEMPT, timeout=10)

    proxy.upstream = ("127.0.0.1", SERVER_PORT)
    disable(app, logs, name)
    local = enable(app, logs, name)
    wait_for_tree(local, tree, on_poll=logs.check)
    round_trip(app, logs, name, local, remote, tree)
