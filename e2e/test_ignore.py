import re
from pathlib import Path

import pytest

from logwatch import LogWatcher, Matcher, msg
from sshadow import PROFILE_NAME, App, Profiles, dataless, enable, evict, trash
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


@pytest.mark.skip(reason="ignore files not implemented")
def test_ignored_items_stay_local(
    app: App, logs: LogWatcher, profile: str, remote: Path
) -> None:
    local = enable(app, logs, profile)
    make_tree(local, TREE)
    logs.expect_all([excluded("build"), excluded("src/debug.log")], timeout=30)
    wait_for_tree(remote, SYNCED, on_poll=logs.check)
    wait_for_tree(local, TREE, on_poll=logs.check)


@pytest.mark.skip(reason="ignore files not implemented")
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


@pytest.mark.skip(reason="ignore files not implemented")
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


@pytest.mark.skip(reason="ignore files not implemented")
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


@pytest.mark.skip(reason="ignore files not implemented")
def test_unignored_remote_items_download(
    app: App, logs: LogWatcher, profile: str, remote: Path
) -> None:
    make_tree(remote, TREE)
    local = enable(app, logs, profile)
    wait_for_tree(local, SYNCED, on_poll=logs.check)

    (remote / ".sshadowignore").write_bytes(b"")
    app.send("poll", name=profile)
    wait_for_tree(local, TREE | {".sshadowignore": File(b"")}, on_poll=logs.check)


def poll_until(
    app: App, logs: LogWatcher, profile: str, remote: Path, local: Path, marker: str
) -> None:
    """Poll until a new remote file appears locally, so the poll has finished."""
    make_tree(remote, {marker: File(b"marker\n")})
    app.send("poll", name=profile)
    wait_for(
        lambda: "" if (local / marker).exists() else f"no {marker}", on_poll=logs.check
    )


@pytest.mark.skip(reason="ignore files not implemented")
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


@pytest.mark.skip(reason="ignore files not implemented")
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


@pytest.mark.skip(reason="ignore files not implemented")
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


@pytest.mark.skip(reason="ignore files not implemented")
def test_renaming_synced_item_to_ignored_name_deletes_remote_copy(
    app: App, logs: LogWatcher, profile: str, remote: Path
) -> None:
    local = enable(app, logs, profile)
    synced: Tree = {".sshadowignore": File(b"*.log\n"), "a.txt": File(b"a\n")}
    make_tree(local, synced)
    wait_for_tree(remote, synced, on_poll=logs.check)

    (local / "a.txt").rename(local / "a.log")
    logs.expect(excluded("a.log"), timeout=30)
    wait_for_tree(remote, {".sshadowignore": File(b"*.log\n")}, on_poll=logs.check)
    assert (local / "a.log").read_bytes() == b"a\n"


@pytest.mark.skip(reason="ignore files not implemented")
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
    logs.expect(excluded("build"), timeout=30)

    (local / "a.txt").rename(local / "build/a.txt")
    (local / "docs").rename(local / "build/docs")
    wait_for_tree(remote, {".sshadowignore": File(b"build/\n")}, on_poll=logs.check)
    assert (local / "build/a.txt").read_bytes() == b"a\n"
    assert (local / "build/docs/d.txt").read_bytes() == b"d\n"


@pytest.mark.skip(reason="ignore files not implemented")
def test_renaming_ignored_items_to_synced_names_uploads_them(
    app: App, logs: LogWatcher, profile: str, remote: Path
) -> None:
    local = enable(app, logs, profile)
    make_tree(local, {".sshadowignore": File(b"build/\n*.log\n")})
    wait_for_tree(
        remote, {".sshadowignore": File(b"build/\n*.log\n")}, on_poll=logs.check
    )
    make_tree(local, {"x.log": File(b"x\n"), "build/y.o": File(b"y\n")})
    logs.expect_all([excluded("x.log"), excluded("build")], timeout=30)

    (local / "x.log").rename(local / "x.txt")
    (local / "build").rename(local / "out")
    expected: Tree = {
        ".sshadowignore": File(b"build/\n*.log\n"),
        "x.txt": File(b"x\n"),
        "out": Dir(),
        "out/y.o": File(b"y\n"),
    }
    wait_for_tree(remote, expected, on_poll=logs.check)


@pytest.mark.skip(reason="ignore files not implemented")
def test_remote_rename_into_ignored_name_removes_local_copy(
    app: App, logs: LogWatcher, profile: str, remote: Path
) -> None:
    synced: Tree = {".sshadowignore": File(b"*.log\n"), "a.txt": File(b"a\n")}
    make_tree(remote, synced)
    local = enable(app, logs, profile)
    wait_for_tree(local, synced, on_poll=logs.check)

    (remote / "a.txt").rename(remote / "a.log")
    app.send("poll", name=profile)
    wait_for_tree(local, {".sshadowignore": File(b"*.log\n")}, on_poll=logs.check)


@pytest.mark.skip(reason="ignore files not implemented")
def test_remote_rename_out_of_ignored_name_downloads(
    app: App, logs: LogWatcher, profile: str, remote: Path
) -> None:
    make_tree(remote, {".sshadowignore": File(b"*.log\n"), "a.log": File(b"a\n")})
    local = enable(app, logs, profile)
    wait_for_tree(local, {".sshadowignore": File(b"*.log\n")}, on_poll=logs.check)

    (remote / "a.log").rename(remote / "a.txt")
    app.send("poll", name=profile)
    expected: Tree = {".sshadowignore": File(b"*.log\n"), "a.txt": File(b"a\n")}
    wait_for_tree(local, expected, on_poll=logs.check)


@pytest.mark.skip(reason="ignore files not implemented")
def test_moving_ignore_file_applies_to_both_folders(
    app: App, logs: LogWatcher, profile: str, remote: Path
) -> None:
    local = enable(app, logs, profile)
    synced: Tree = {"src": Dir(), "src/.sshadowignore": File(b"*.log\n"), "docs": Dir()}
    make_tree(local, synced)
    wait_for_tree(remote, synced, on_poll=logs.check)
    make_tree(local, {"src/x.log": File(b"x\n")})
    logs.expect(excluded("src/x.log"), timeout=30)
    make_tree(remote, {"src/y.log": File(b"y\n")})
    poll_until(app, logs, profile, remote, local, "marker.md")
    assert not (local / "src/y.log").exists()

    (local / "src/.sshadowignore").rename(local / "docs/.sshadowignore")
    expected: Tree = {
        "src": Dir(),
        "src/x.log": File(b"x\n"),
        "src/y.log": File(b"y\n"),
        "docs": Dir(),
        "docs/.sshadowignore": File(b"*.log\n"),
        "marker.md": File(b"marker\n"),
    }
    wait_for_tree(remote, expected, on_poll=logs.check)
    wait_for_tree(local, expected, on_poll=logs.check)


@pytest.mark.skip(reason="ignore files not implemented")
def test_deleting_ignore_file_locally_unignores_items(
    app: App, logs: LogWatcher, profile: str, remote: Path
) -> None:
    local = enable(app, logs, profile)
    make_tree(local, {".sshadowignore": File(b"build/\n")})
    wait_for_tree(remote, {".sshadowignore": File(b"build/\n")}, on_poll=logs.check)
    make_tree(local, {"build/x.o": File(b"x\n")})
    logs.expect(excluded("build"), timeout=30)

    (local / ".sshadowignore").unlink()
    expected: Tree = {"build": Dir(), "build/x.o": File(b"x\n")}
    wait_for_tree(remote, expected, on_poll=logs.check)


@pytest.mark.skip(reason="ignore files not implemented")
def test_deleting_ignore_file_remotely_unignores_items(
    app: App, logs: LogWatcher, profile: str, remote: Path
) -> None:
    make_tree(remote, TREE)
    local = enable(app, logs, profile)
    wait_for_tree(local, SYNCED, on_poll=logs.check)

    (remote / ".sshadowignore").unlink()
    app.send("poll", name=profile)
    wait_for_tree(local, CONTENT, on_poll=logs.check)


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
    top = sorted(both)[0]
    logs.expect(excluded(top), timeout=30)
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
FOLDER: Tree = {"build": Dir(), "build/a.o": File(b"a\n")}
LOCAL_ONLY: Tree = {"build/local-only.o": File(b"l\n")}
REMOTE_ONLY: Tree = {"build/remote-only.o": File(b"r\n")}
MARKER: Tree = {"marker.md": File(b"marker\n")}


@pytest.mark.skip(reason="ignore files not implemented")
def test_removing_rule_locally_pushes_local_file(
    app: App, logs: LogWatcher, profile: str, remote: Path
) -> None:
    local = detach_on_both_sides(
        app, logs, profile, remote, b"*.log\n", FILE, {}, {}, False
    )

    (local / ".sshadowignore").write_bytes(b"")
    expected = {".sshadowignore": File(b"")} | MARKER | side(FILE, b"local ")
    wait_for_tree(remote, expected, on_poll=logs.check)
    wait_for_tree(local, expected, on_poll=logs.check)


@pytest.mark.skip(reason="ignore files not implemented")
def test_removing_rule_locally_replaces_remote_folder(
    app: App, logs: LogWatcher, profile: str, remote: Path
) -> None:
    local = detach_on_both_sides(
        app, logs, profile, remote, b"build/\n", FOLDER, LOCAL_ONLY, REMOTE_ONLY, False
    )

    (local / ".sshadowignore").write_bytes(b"")
    expected = (
        {".sshadowignore": File(b"")} | MARKER | side(FOLDER, b"local ") | LOCAL_ONLY
    )
    wait_for_tree(remote, expected, on_poll=logs.check)
    app.send("poll", name=profile)
    wait_for_tree(local, expected, on_poll=logs.check)


@pytest.mark.skip(reason="ignore files not implemented")
def test_removing_rule_remotely_pulls_remote_file(
    app: App, logs: LogWatcher, profile: str, remote: Path
) -> None:
    local = detach_on_both_sides(
        app, logs, profile, remote, b"*.log\n", FILE, {}, {}, True
    )

    (remote / ".sshadowignore").write_bytes(b"")
    app.send("poll", name=profile)
    expected = {".sshadowignore": File(b"")} | MARKER | side(FILE, b"remote ")
    wait_for_tree(local, expected, on_poll=logs.check)
    wait_for_tree(remote, expected, on_poll=logs.check)


@pytest.mark.skip(reason="ignore files not implemented")
def test_removing_rule_remotely_replaces_local_folder(
    app: App, logs: LogWatcher, profile: str, remote: Path
) -> None:
    local = detach_on_both_sides(
        app, logs, profile, remote, b"build/\n", FOLDER, LOCAL_ONLY, REMOTE_ONLY, True
    )

    (remote / ".sshadowignore").write_bytes(b"")
    app.send("poll", name=profile)
    expected = (
        {".sshadowignore": File(b"")} | MARKER | side(FOLDER, b"remote ") | REMOTE_ONLY
    )
    # Files only the local side had stay local, and excluded.
    wait_for_tree(local, expected | LOCAL_ONLY, on_poll=logs.check)
    wait_for_tree(remote, expected, on_poll=logs.check)


@pytest.mark.skip(reason="ignore files not implemented")
def test_removing_rule_locally_pushes_synced_item(
    app: App, logs: LogWatcher, profile: str, remote: Path
) -> None:
    local = enable(app, logs, profile)
    synced: Tree = {"data": Dir(), "data/a.txt": File(b"a\n")}
    make_tree(local, synced)
    wait_for_tree(remote, synced, on_poll=logs.check)
    make_tree(local, {".sshadowignore": File(b"data/\n")})
    wait_for(lambda: "" if (remote / ".sshadowignore").exists() else "missing")
    make_tree(remote, {"data/a.txt": File(b"remote edit\n")})
    poll_until(app, logs, profile, remote, local, "marker.md")

    (local / ".sshadowignore").write_bytes(b"")
    expected = {".sshadowignore": File(b"")} | MARKER | synced
    wait_for_tree(remote, expected, on_poll=logs.check)
    app.send("poll", name=profile)
    wait_for_tree(local, expected, on_poll=logs.check)


@pytest.mark.skip(reason="ignore files not implemented")
def test_removing_rule_remotely_pulls_synced_item(
    app: App, logs: LogWatcher, profile: str, remote: Path
) -> None:
    synced: Tree = {"data": Dir(), "data/a.txt": File(b"a\n")}
    make_tree(remote, synced)
    local = enable(app, logs, profile)
    wait_for_tree(local, synced, on_poll=logs.check)
    make_tree(remote, {".sshadowignore": File(b"data/\n")})
    poll_until(app, logs, profile, remote, local, "marker-1.md")
    make_tree(remote, {"data/a.txt": File(b"remote edit\n")})
    poll_until(app, logs, profile, remote, local, "marker-2.md")
    assert (local / "data/a.txt").read_bytes() == b"a\n"

    (remote / ".sshadowignore").write_bytes(b"")
    app.send("poll", name=profile)
    expected = {
        ".sshadowignore": File(b""),
        "data": Dir(),
        "data/a.txt": File(b"remote edit\n"),
    } | {"marker-1.md": File(b"marker\n"), "marker-2.md": File(b"marker\n")}
    wait_for_tree(local, expected, on_poll=logs.check)


@pytest.mark.skip(reason="ignore files not implemented")
def test_removing_rule_locally_drops_remote_additions_to_synced_folder(
    app: App, logs: LogWatcher, profile: str, remote: Path
) -> None:
    local = enable(app, logs, profile)
    synced: Tree = {"data": Dir(), "data/a.txt": File(b"a\n")}
    make_tree(local, synced)
    wait_for_tree(remote, synced, on_poll=logs.check)
    make_tree(local, {".sshadowignore": File(b"data/\n")})
    wait_for(lambda: "" if (remote / ".sshadowignore").exists() else "missing")
    make_tree(
        remote,
        {
            "data/a.txt": File(b"remote edit\n"),
            "data/new.txt": File(b"new\n"),
            "data/sub": Dir(),
            "data/sub/deep.txt": File(b"deep\n"),
        },
    )
    poll_until(app, logs, profile, remote, local, "marker.md")

    (local / ".sshadowignore").write_bytes(b"")
    expected = {".sshadowignore": File(b"")} | MARKER | synced
    wait_for_tree(remote, expected, on_poll=logs.check)


@pytest.mark.skip(reason="ignore files not implemented")
def test_removing_rule_locally_skips_items_never_downloaded(
    app: App, logs: LogWatcher, profile: str, remote: Path
) -> None:
    synced: Tree = {"data": Dir(), "data/a.txt": File(b"a\n")}
    make_tree(remote, synced)
    local = enable(app, logs, profile)
    wait_for(
        lambda: "" if (local / "data/a.txt").exists() else "missing", on_poll=logs.check
    )
    if not dataless(local / "data/a.txt"):
        evict(local / "data/a.txt")
    wait_for(
        lambda: "" if dataless(local / "data/a.txt") else "downloaded",
        on_poll=logs.check,
    )

    make_tree(local, {".sshadowignore": File(b"data/\n")})
    wait_for(lambda: "" if (remote / ".sshadowignore").exists() else "missing")
    make_tree(remote, {"data/a.txt": File(b"remote edit\n")})
    poll_until(app, logs, profile, remote, local, "marker.md")

    (local / ".sshadowignore").write_bytes(b"")
    app.send("poll", name=profile)
    expected = {
        ".sshadowignore": File(b""),
        "data": Dir(),
        "data/a.txt": File(b"remote edit\n"),
    } | MARKER
    wait_for_tree(local, expected, on_poll=logs.check)
    wait_for_tree(remote, expected, on_poll=logs.check)


@pytest.mark.skip(reason="ignore files not implemented")
def test_renaming_detached_item_within_ignored_paths_keeps_remote_copy(
    app: App, logs: LogWatcher, profile: str, remote: Path
) -> None:
    local = enable(app, logs, profile)
    synced: Tree = {"data": Dir(), "data/a.txt": File(b"a\n")}
    make_tree(local, synced)
    wait_for_tree(remote, synced, on_poll=logs.check)
    make_tree(local, {".sshadowignore": File(b"data/\n")})
    wait_for(lambda: "" if (remote / ".sshadowignore").exists() else "missing")

    (local / "data/a.txt").rename(local / "data/b.txt")
    logs.expect(excluded("data/b.txt"), timeout=30)
    poll_until(app, logs, profile, remote, local, "marker.md")

    assert (remote / "data/a.txt").read_bytes() == b"a\n"
    assert not (remote / "data/b.txt").exists()
    assert (local / "data/b.txt").read_bytes() == b"a\n"
    assert not (local / "data/a.txt").exists()


@pytest.mark.skip(reason="ignore files not implemented")
def test_remote_delete_of_detached_item_keeps_local_copy(
    app: App, logs: LogWatcher, profile: str, remote: Path
) -> None:
    synced: Tree = {"data": Dir(), "data/a.txt": File(b"a\n")}
    make_tree(remote, synced)
    local = enable(app, logs, profile)
    wait_for_tree(local, synced, on_poll=logs.check)
    make_tree(remote, {".sshadowignore": File(b"data/\n")})
    poll_until(app, logs, profile, remote, local, "marker-1.md")

    (remote / "data/a.txt").unlink()
    poll_until(app, logs, profile, remote, local, "marker-2.md")

    assert (local / "data/a.txt").read_bytes() == b"a\n"


@pytest.mark.skip(reason="ignore files not implemented")
def test_later_ignore_files_take_precedence(
    app: App, logs: LogWatcher, profiles: Profiles, remote: Path
) -> None:
    profile = profiles.create(PROFILE_NAME, ignore=[".gitignore", ".sshadowignore"])
    local = enable(app, logs, profile)
    rules: Tree = {
        ".gitignore": File(b"*.log\n"),
        ".sshadowignore": File(b"!keep.log\n"),
    }
    make_tree(local, rules)
    wait_for_tree(remote, rules, on_poll=logs.check)

    files: Tree = {
        "a.log": File(b"a\n"),
        "keep.log": File(b"k\n"),
        "b.txt": File(b"b\n"),
    }
    make_tree(local, files)
    logs.expect(excluded("a.log"), timeout=30)
    expected = rules | {k: v for k, v in files.items() if k != "a.log"}
    wait_for_tree(remote, expected, on_poll=logs.check)


def test_unlisted_ignore_files_do_not_apply(
    app: App, logs: LogWatcher, profile: str, remote: Path
) -> None:
    local = enable(app, logs, profile)
    tree: Tree = {".gitignore": File(b"*.log\n"), "a.log": File(b"a\n")}
    make_tree(local, tree)
    wait_for_tree(remote, tree, on_poll=logs.check)
