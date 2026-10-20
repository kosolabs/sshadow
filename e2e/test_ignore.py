import re
from pathlib import Path

from logwatch import LogWatcher, Matcher, msg
from sshadow import App, dataless, enable, evict
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
