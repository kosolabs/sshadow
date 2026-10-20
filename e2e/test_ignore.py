import re
from pathlib import Path

from logwatch import LogWatcher, Matcher, msg
from sshadow import App, dataless, enable, evict, trash
from tree import Dir, File, Tree, make_tree, wait_for, wait_for_tree

IGNORE: Tree = {".sshadowignore": File(b"build/\n*.log\n")}

CONTENT: Tree = {
    "notes.txt": File(b"notes\n"),
    "src": Dir(),
    "src/main.c": File(b"int main() {}\n"),
    "src/debug.log": File(b"debug\n"),
    "build": Dir(),
    "build/out.o": File(b"out\n"),
}

TREE: Tree = IGNORE | CONTENT

SYNCED: Tree = {
    k: v for k, v in TREE.items() if k != "src/debug.log" and not k.startswith("build")
}


def excluded(path: str) -> Matcher:
    return msg(rf"^Excluded from sync: {re.escape(path)} ")


def test_ignored_items_stay_local(
    app: App, logs: LogWatcher, profile: str, remote: Path
) -> None:
    local = enable(app, logs, profile)
    make_tree(local, TREE)
    logs.expect_all([excluded("build"), excluded("src/debug.log")], timeout=30)
    wait_for_tree(remote, SYNCED, on_poll=logs.check)
    wait_for_tree(local, TREE, on_poll=logs.check)


def test_remote_ignore_file_applies_locally(
    app: App, logs: LogWatcher, profile: str, remote: Path
) -> None:
    make_tree(remote, IGNORE)
    local = enable(app, logs, profile)
    ignore = local / ".sshadowignore"
    wait_for(lambda: "" if ignore.exists() else "missing", on_poll=logs.check)
    if not dataless(ignore):
        evict(ignore)
    wait_for(lambda: "" if dataless(ignore) else "downloaded", on_poll=logs.check)

    make_tree(local, CONTENT)
    logs.expect_all([excluded("build"), excluded("src/debug.log")], timeout=30)
    wait_for_tree(remote, SYNCED, on_poll=logs.check)


def test_ignored_items_stay_remote(
    app: App, logs: LogWatcher, profile: str, remote: Path
) -> None:
    make_tree(remote, TREE)
    local = enable(app, logs, profile)
    wait_for_tree(local, SYNCED, on_poll=logs.check)

    added: Tree = {"notes.log": File(b"notes\n"), "keep.txt": File(b"keep\n")}
    make_tree(remote, added)
    app.send("poll", name=profile)
    wait_for_tree(local, SYNCED | {"keep.txt": added["keep.txt"]}, on_poll=logs.check)
    wait_for_tree(remote, TREE | added)


def test_unignored_local_items_upload(
    app: App, logs: LogWatcher, profile: str, remote: Path
) -> None:
    local = enable(app, logs, profile)
    make_tree(local, {".sshadowignore": File(b"build/\n")})
    wait_for_tree(remote, {".sshadowignore": File(b"build/\n")}, on_poll=logs.check)
    make_tree(local, {"build/x.o": File(b"x\n")})
    logs.expect(excluded("build"), timeout=30)

    (local / ".sshadowignore").write_bytes(b"")
    expected: Tree = {
        ".sshadowignore": File(b""),
        "build": Dir(),
        "build/x.o": File(b"x\n"),
    }
    wait_for_tree(remote, expected, on_poll=logs.check)


def test_unignored_remote_items_download(
    app: App, logs: LogWatcher, profile: str, remote: Path
) -> None:
    make_tree(remote, TREE)
    local = enable(app, logs, profile)
    wait_for_tree(local, SYNCED, on_poll=logs.check)

    (remote / ".sshadowignore").write_bytes(b"")
    app.send("poll", name=profile)
    wait_for_tree(
        local, TREE | {".sshadowignore": File(b"")}, on_poll=logs.check
    )


def poll_until(app: App, logs: LogWatcher, profile: str, remote: Path, local: Path, marker: str) -> None:
    """Poll until a new remote file appears locally, so the poll has finished."""
    make_tree(remote, {marker: File(b"marker\n")})
    app.send("poll", name=profile)
    wait_for(
        lambda: "" if (local / marker).exists() else f"no {marker}", on_poll=logs.check
    )


def test_newly_ignored_items_stop_syncing(
    app: App, logs: LogWatcher, profile: str, remote: Path
) -> None:
    local = enable(app, logs, profile)
    synced: Tree = {"data": Dir(), "data/a.txt": File(b"a\n"), "b.txt": File(b"b\n")}
    make_tree(local, synced)
    wait_for_tree(remote, synced, on_poll=logs.check)

    make_tree(local, {".sshadowignore": File(b"data/\nb.txt\n")})
    wait_for(lambda: "" if (remote / ".sshadowignore").exists() else "missing")
    (local / "data/a.txt").write_bytes(b"local a\n")
    (local / "b.txt").write_bytes(b"local b\n")
    logs.expect_all([excluded("data/a.txt"), excluded("b.txt")], timeout=30)
    poll_until(app, logs, profile, remote, local, "marker-1.md")

    assert (remote / "data/a.txt").read_bytes() == b"a\n"
    assert (remote / "b.txt").read_bytes() == b"b\n"
    assert (local / "data/a.txt").read_bytes() == b"local a\n"
    assert (local / "b.txt").read_bytes() == b"local b\n"

    make_tree(remote, {"data/a.txt": File(b"remote a\n"), "b.txt": File(b"remote b\n")})
    poll_until(app, logs, profile, remote, local, "marker-2.md")

    assert (local / "data/a.txt").read_bytes() == b"local a\n"
    assert (local / "b.txt").read_bytes() == b"local b\n"


def test_deleting_ignored_item_keeps_remote_copy(
    app: App, logs: LogWatcher, profile: str, remote: Path
) -> None:
    local = enable(app, logs, profile)
    make_tree(local, {"b.txt": File(b"b\n")})
    wait_for_tree(remote, {"b.txt": File(b"b\n")}, on_poll=logs.check)

    make_tree(local, {".sshadowignore": File(b"b.txt\n")})
    wait_for(lambda: "" if (remote / ".sshadowignore").exists() else "missing")
    (local / "b.txt").unlink()
    logs.expect(msg(r"^Delete item "), timeout=30)
    poll_until(app, logs, profile, remote, local, "marker.md")

    assert (remote / "b.txt").read_bytes() == b"b\n"
    assert not (local / "b.txt").exists()


def test_unignored_directory_on_both_sides_merges(
    app: App, logs: LogWatcher, profile: str, remote: Path
) -> None:
    local = enable(app, logs, profile)
    make_tree(local, {".sshadowignore": File(b"build/\n")})
    wait_for_tree(remote, {".sshadowignore": File(b"build/\n")}, on_poll=logs.check)
    make_tree(local, {"build/x.o": File(b"x\n")})
    logs.expect(excluded("build"), timeout=30)
    make_tree(remote, {"build/y.o": File(b"y\n")})
    poll_until(app, logs, profile, remote, local, "marker.md")

    (local / ".sshadowignore").write_bytes(b"")
    expected: Tree = {
        ".sshadowignore": File(b""),
        "marker.md": File(b"marker\n"),
        "build": Dir(),
        "build/x.o": File(b"x\n"),
        "build/y.o": File(b"y\n"),
    }
    wait_for_tree(remote, expected, on_poll=logs.check)
    app.send("poll", name=profile)
    wait_for_tree(local, expected, on_poll=logs.check)


def test_trashing_ignored_item_keeps_remote_copy(
    app: App, logs: LogWatcher, profile: str, remote: Path
) -> None:
    local = enable(app, logs, profile)
    make_tree(local, {"b.txt": File(b"b\n")})
    wait_for_tree(remote, {"b.txt": File(b"b\n")}, on_poll=logs.check)

    make_tree(local, {".sshadowignore": File(b"b.txt\n")})
    wait_for(lambda: "" if (remote / ".sshadowignore").exists() else "missing")
    trashed = trash(local / "b.txt")
    logs.expect(excluded("b.txt"), timeout=30)
    poll_until(app, logs, profile, remote, local, "marker.md")

    assert (remote / "b.txt").read_bytes() == b"b\n"
    assert not (remote / ".sshadow/trash/b.txt").exists()
    assert trashed.read_bytes() == b"b\n"
