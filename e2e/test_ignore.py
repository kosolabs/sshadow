import re
import shutil
from collections.abc import Callable
from pathlib import Path

from logwatch import LogWatcher, Matcher, msg
from sshadow import (
    App,
    brokered,
    connected,
    dataless,
    enable,
    evict,
)
from tree import (
    Dir,
    File,
    Tree,
    diff_trees,
    make_tree,
    read_tree,
    wait_for,
    wait_for_tree,
)

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


def ignored(path: str) -> Matcher:
    return msg(rf'^Ignore (?!rules ).*\bpath: "{re.escape(path)}"[,)]')


def hidden(path: str) -> Matcher:
    return msg(rf'^Hide ignored Ref\(path: "{re.escape(path)}"[,)]')


def evicted(path: str) -> Matcher:
    return msg(rf'^Evicted Ref\(path: "{re.escape(path)}"[,)]')


def make_dataless(path: Path, logs: LogWatcher) -> None:
    wait_for(lambda: "" if path.exists() else "missing", on_poll=logs.check)
    # Eviction fails while File Provider is still syncing the item.
    wait_for(
        lambda: "" if dataless(path) else (evict(path) or "downloaded"),
        on_poll=logs.check,
    )


def wait_until_gone(path: Path, logs: LogWatcher) -> None:
    wait_for(
        lambda: f"{path.name} still listed" if path.exists() else "",
        on_poll=logs.check,
    )


def wait_for_entries(
    root: Path,
    expected: Tree,
    *,
    timeout: float = 30,
    on_poll: Callable[[], None] = lambda: None,
) -> None:
    """Like `wait_for_tree`, but ignores entries `expected` doesn't name."""

    def check() -> str:
        actual = {k: v for k, v in read_tree(root).items() if k in expected}
        return diff_trees(actual, expected)

    wait_for(check, timeout=timeout, on_poll=on_poll)


def test_ignored_items_stay_local(
    app: App, logs: LogWatcher, profile: str, remote: Path
) -> None:
    local = enable(app, logs, profile)
    make_tree(local, TREE)
    logs.expect_all([ignored("build"), ignored("src/debug.log")], timeout=30)
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
    logs.expect_all([ignored("build"), ignored("src/debug.log")], timeout=30)
    wait_for_tree(remote, SYNCED, on_poll=logs.check)


def test_unignored_local_items_upload(
    app: App, logs: LogWatcher, profile: str, remote: Path
) -> None:
    local = enable(app, logs, profile)
    make_tree(local, {".sshadowignore": File(b"build/\n")})
    wait_for_tree(remote, {".sshadowignore": File(b"build/\n")}, on_poll=logs.check)
    make_tree(local, {"build/x.o": File(b"x\n")})
    logs.expect(ignored("build"), timeout=30)

    (local / ".sshadowignore").write_bytes(b"")
    expected: Tree = {
        ".sshadowignore": File(b""),
        "build": Dir(),
        "build/x.o": File(b"x\n"),
    }
    wait_for_tree(remote, expected, on_poll=logs.check)


def poll_until(
    app: App, logs: LogWatcher, profile: str, remote: Path, local: Path, marker: str
) -> None:
    """Poll until a new remote file appears locally, so the poll has finished."""
    make_tree(remote, {marker: File(b"marker\n")})
    app.send("poll", name=profile)
    wait_for(
        lambda: "" if (local / marker).exists() else f"no {marker}", on_poll=logs.check
    )


def test_moving_synced_items_into_ignored_folder_deletes_remote_copies(
    app: App, logs: LogWatcher, profile: str, remote: Path
) -> None:
    local = enable(app, logs, profile)
    synced: Tree = {
        ".sshadowignore": File(b"build/\n"),
        "a.txt": File(b"a\n"),
        "docs": Dir(),
        "docs/d.txt": File(b"d\n"),
    }
    make_tree(local, synced)
    wait_for_tree(remote, synced, on_poll=logs.check)
    make_tree(local, {"build/x.o": File(b"x\n")})
    logs.expect(ignored("build"), timeout=30)

    (local / "a.txt").rename(local / "build/a.txt")
    (local / "docs").rename(local / "build/docs")
    wait_for_tree(remote, {".sshadowignore": File(b"build/\n")}, on_poll=logs.check)
    assert (local / "build/a.txt").read_bytes() == b"a\n"
    assert (local / "build/docs/d.txt").read_bytes() == b"d\n"


def test_renaming_ignored_items_to_synced_names_uploads_them(
    app: App, logs: LogWatcher, profile: str, remote: Path
) -> None:
    local = enable(app, logs, profile)
    make_tree(local, {".sshadowignore": File(b"build/\n*.log\n")})
    wait_for_tree(
        remote, {".sshadowignore": File(b"build/\n*.log\n")}, on_poll=logs.check
    )
    make_tree(local, {"x.log": File(b"x\n"), "build/y.o": File(b"y\n")})
    logs.expect_all([ignored("x.log"), ignored("build")], timeout=30)

    (local / "x.log").rename(local / "x.txt")
    (local / "build").rename(local / "out")
    expected: Tree = {
        ".sshadowignore": File(b"build/\n*.log\n"),
        "x.txt": File(b"x\n"),
        "out": Dir(),
        "out/y.o": File(b"y\n"),
    }
    wait_for_tree(remote, expected, on_poll=logs.check)


def detach_on_both_sides(
    app: App,
    logs: LogWatcher,
    profile: str,
    remote: Path,
    rules: bytes,
    both: Tree,
    local_only: Tree,
    remote_only: Tree,
    rules_from_remote: bool,
) -> Path:
    """Create `both` on each side with different contents while `rules` ignore it."""
    if rules_from_remote:
        make_tree(remote, {".sshadowignore": File(rules)})
        local = enable(app, logs, profile)
        wait_for(
            lambda: "" if (local / ".sshadowignore").exists() else "missing",
            on_poll=logs.check,
        )
    else:
        local = enable(app, logs, profile)
        make_tree(local, {".sshadowignore": File(rules)})
        wait_for_tree(remote, {".sshadowignore": File(rules)}, on_poll=logs.check)
    make_tree(
        local,
        {
            k: File(b"local " + v.contents) if isinstance(v, File) else v
            for k, v in both.items()
        }
        | local_only,
    )
    top = min(both)
    logs.expect(ignored(top), timeout=30)
    make_tree(
        remote,
        {
            k: File(b"remote " + v.contents) if isinstance(v, File) else v
            for k, v in both.items()
        }
        | remote_only,
    )
    poll_until(app, logs, profile, remote, local, "marker.md")
    return local


def side(tree: Tree, prefix: bytes) -> Tree:
    return {
        k: File(prefix + v.contents) if isinstance(v, File) else v
        for k, v in tree.items()
    }


FILE: Tree = {"x.log": File(b"x\n")}
MARKER: Tree = {"marker.md": File(b"marker\n")}


FOLDER: Tree = {"build": Dir(), "build/data.txt": File(b"data\n")}
LOCAL_ONLY: Tree = {"build/local.txt": File(b"l\n")}
REMOTE_ONLY: Tree = {"build/remote.txt": File(b"r\n")}
LOCAL_FOLDER: Tree = side(FOLDER, b"local ") | LOCAL_ONLY
REMOTE_FOLDER: Tree = side(FOLDER, b"remote ") | REMOTE_ONLY


def renamed(tree: Tree, name: str) -> Tree:
    """`tree` with its top item renamed, as File Provider does on a collision."""
    top = min(tree)
    return {name + k.removeprefix(top): v for k, v in tree.items()}


LOCAL_FILE: Tree = side(FILE, b"local ")
REMOTE_FILE: Tree = side(FILE, b"remote ")


def test_removing_rule_locally_keeps_both_files_until_one_is_deleted(
    app: App, logs: LogWatcher, profile: str, remote: Path
) -> None:
    local = detach_on_both_sides(
        app, logs, profile, remote, b"*.log\n", FILE, {}, {}, False
    )

    (local / ".sshadowignore").write_bytes(b"")
    base = {".sshadowignore": File(b"")} | MARKER
    expected = REMOTE_FILE | renamed(LOCAL_FILE, "x 2.log")
    wait_for_entries(local, expected, timeout=60, on_poll=logs.check)
    wait_for_tree(remote, base | REMOTE_FILE, on_poll=logs.check)

    (local / "x.log").unlink()
    wait_for_tree(remote, base | LOCAL_FILE, timeout=60, on_poll=logs.check)
    wait_for_tree(local, base | LOCAL_FILE, on_poll=logs.check)


def test_removing_rule_remotely_keeps_both_files_until_one_is_deleted(
    app: App, logs: LogWatcher, profile: str, remote: Path
) -> None:
    local = detach_on_both_sides(
        app, logs, profile, remote, b"*.log\n", FILE, {}, {}, True
    )

    (remote / ".sshadowignore").write_bytes(b"")
    app.send("poll", name=profile)
    base = {".sshadowignore": File(b"")} | MARKER
    expected = REMOTE_FILE | renamed(LOCAL_FILE, "x 2.log")
    wait_for_entries(local, expected, timeout=60, on_poll=logs.check)
    wait_for_tree(remote, base | REMOTE_FILE, on_poll=logs.check)

    (local / "x 2.log").unlink()
    app.send("poll", name=profile)
    wait_for_tree(local, base | REMOTE_FILE, timeout=60, on_poll=logs.check)
    wait_for_tree(remote, base | REMOTE_FILE, on_poll=logs.check)


def test_removing_rule_locally_keeps_both_folders_until_one_is_deleted(
    app: App, logs: LogWatcher, profile: str, remote: Path
) -> None:
    local = detach_on_both_sides(
        app, logs, profile, remote, b"build/\n", FOLDER, LOCAL_ONLY, REMOTE_ONLY, False
    )

    (local / ".sshadowignore").write_bytes(b"")
    base = {".sshadowignore": File(b"")} | MARKER
    expected = REMOTE_FOLDER | renamed(LOCAL_FOLDER, "build 2")
    wait_for_entries(local, expected, timeout=60, on_poll=logs.check)
    wait_for_tree(remote, base | REMOTE_FOLDER, on_poll=logs.check)

    shutil.rmtree(local / "build")
    wait_for_tree(remote, base | LOCAL_FOLDER, timeout=60, on_poll=logs.check)
    wait_for_tree(local, base | LOCAL_FOLDER, on_poll=logs.check)


def test_removing_rule_remotely_keeps_both_folders_until_one_is_deleted(
    app: App, logs: LogWatcher, profile: str, remote: Path
) -> None:
    local = detach_on_both_sides(
        app, logs, profile, remote, b"build/\n", FOLDER, LOCAL_ONLY, REMOTE_ONLY, True
    )

    (remote / ".sshadowignore").write_bytes(b"")
    app.send("poll", name=profile)
    base = {".sshadowignore": File(b"")} | MARKER
    expected = REMOTE_FOLDER | renamed(LOCAL_FOLDER, "build 2")
    wait_for_entries(local, expected, timeout=60, on_poll=logs.check)
    wait_for_tree(remote, base | REMOTE_FOLDER, on_poll=logs.check)

    shutil.rmtree(local / "build 2")
    app.send("poll", name=profile)
    wait_for_tree(local, base | REMOTE_FOLDER, timeout=60, on_poll=logs.check)
    wait_for_tree(remote, base | REMOTE_FOLDER, on_poll=logs.check)


def test_remote_rule_keeps_listed_folder_until_its_files_are_evicted(
    app: App, logs: LogWatcher, profile: str, remote: Path
) -> None:
    make_tree(
        remote,
        {
            "data": Dir(),
            "data/read.txt": File(b"read\n"),
            "data/unread.txt": File(b"unread\n"),
        },
    )
    local = enable(app, logs, profile)
    wait_for(lambda: "" if (local / "data").exists() else "missing")
    assert (local / "data/read.txt").read_bytes() == b"read\n"
    make_dataless(local / "data/unread.txt", logs)

    make_tree(remote, {".sshadowignore": File(b"data/\n")})
    app.send("poll", name=profile)
    logs.expect(hidden("data/unread.txt"), timeout=30)
    wait_until_gone(local / "data/unread.txt", logs)
    assert [p.name for p in (local / "data").iterdir()] == ["read.txt"]

    wait_for(lambda: evict(local / "data/read.txt") or "", on_poll=logs.check)
    logs.expect(evicted("data/read.txt"), timeout=30)
    logs.expect(hidden("data/read.txt"), timeout=30)
    logs.expect(evicted("data"), timeout=30)
    logs.expect(hidden("data"), timeout=30)
    wait_until_gone(local / "data", logs)

    assert (remote / "data/read.txt").read_bytes() == b"read\n"


def test_local_rule_hides_dataless_file(
    app: App, logs: LogWatcher, profile: str, remote: Path
) -> None:
    make_tree(remote, {"a.txt": File(b"a\n")})
    local = enable(app, logs, profile)
    make_dataless(local / "a.txt", logs)

    make_tree(local, {".sshadowignore": File(b"a.txt\n")})
    logs.expect(hidden("a.txt"), timeout=30)
    wait_until_gone(local / "a.txt", logs)

    wait_for(lambda: "" if (remote / ".sshadowignore").exists() else "missing")
    assert (remote / "a.txt").read_bytes() == b"a\n"


def test_removing_rule_remotely_while_quit_uploads_ignored_items(
    app: App,
    logs: LogWatcher,
    profile: str,
    remote: Path,
    relaunch_app: Callable[[], None],
) -> None:
    local = enable(app, logs, profile)
    make_tree(local, {".sshadowignore": File(b"build/\n")})
    wait_for_tree(remote, {".sshadowignore": File(b"build/\n")}, on_poll=logs.check)
    make_tree(local, {"build/x.o": File(b"x\n")})
    logs.expect(ignored("build"), timeout=30)

    app.quit()
    (remote / ".sshadowignore").write_bytes(b"")
    relaunch_app()
    logs.expect_all([brokered(profile), connected(profile)], timeout=60)
    app.send("poll", name=profile)
    expected: Tree = {
        ".sshadowignore": File(b""),
        "build": Dir(),
        "build/x.o": File(b"x\n"),
    }
    wait_for_tree(remote, expected, timeout=60, on_poll=logs.check)
