import random
import time
from datetime import UTC, datetime
from pathlib import Path

from logwatch import LogWatcher, msg
from sshadow import App
from tree import (
    Delete,
    Dir,
    Edit,
    File,
    Link,
    Move,
    SetAttrs,
    Tree,
    Write,
    apply_edits,
    edit_tree,
    make_tree,
    wait_for_tree,
)


def date(day: str) -> int:
    return int(datetime.fromisoformat(day).replace(tzinfo=UTC).timestamp())


TREE: Tree = {
    "hello.txt": File(b"hello, world\n", mtime=date("2026-01-01")),
    "readonly.txt": File(b"read only\n", mode=0o444),
    "empty.txt": File(b""),
    "with space.txt": File(b"spaces\n"),
    "random.bin": File(random.Random(0).randbytes(1 << 20)),
    "docs": Dir(),
    "docs/readme.md": File(b"# Readme\n"),
    "docs/nested": Dir(),
    "docs/nested/deep.txt": File(b"deep\n"),
    "empty-dir": Dir(),
    "Document.rtfd": Dir(),
    "Document.rtfd/TXT.rtf": File(b"{\\rtf1 hello}\n"),
    "Old.rtfd": Dir(),
    "Old.rtfd/TXT.rtf": File(b"{\\rtf1 old}\n"),
    "link.txt": Link("hello.txt", mtime=date("2026-02-02")),
    "broken.txt": Link("missing.txt", mtime=date("2026-03-03")),
}

EDITS: list[Edit] = [
    Write("hello.txt", File(b"hello, again\n")),
    # macOS updates a package's modification date whenever it's edited.
    Write("Document.rtfd/TXT.rtf", File(b"{\\rtf1 edited}\n")),
    SetAttrs("Document.rtfd", mtime=date("2026-05-05")),
    Move("with space.txt", "renamed.txt"),
    Move("docs/readme.md", "readme.md"),
    Move("docs/nested", "nested"),
    Move("broken.txt", "docs/broken.txt"),
    Move("docs", "documents"),
    Write("link.txt", Link("readme.md")),
    SetAttrs("readonly.txt", mode=0o644),
    SetAttrs("random.bin", mtime=date("2026-04-04")),
    Delete("empty.txt"),
    Delete("empty-dir"),
    Delete("Old.rtfd"),
]


def enable(app: App, logs: LogWatcher, profile: str) -> Path:
    app.send("enable", name=profile)
    # The extension can take a while to launch the first time, e.g. on CI.
    logs.expect(msg(rf"Profile enabled: .*\bname: {profile}\b"), timeout=60)
    root = Path.home() / "Library" / "CloudStorage" / f"SSHadow-{profile}"
    deadline = time.monotonic() + 10
    while not root.is_dir():
        assert time.monotonic() < deadline, f"{root} never appeared"
        logs.check()
        time.sleep(0.1)
    return root


def test_upload(app: App, logs: LogWatcher, profile: str, remote: Path) -> None:
    local = enable(app, logs, profile)
    make_tree(local, TREE)
    wait_for_tree(remote, TREE, on_poll=logs.check)


def test_download(app: App, logs: LogWatcher, profile: str, remote: Path) -> None:
    make_tree(remote, TREE)
    local = enable(app, logs, profile)
    wait_for_tree(local, TREE, on_poll=logs.check)


def test_local_edits(app: App, logs: LogWatcher, profile: str, remote: Path) -> None:
    local = enable(app, logs, profile)
    make_tree(local, TREE)
    wait_for_tree(remote, TREE, on_poll=logs.check)

    apply_edits(local, EDITS)
    wait_for_tree(remote, edit_tree(TREE, EDITS), on_poll=logs.check)


def test_remote_edits(app: App, logs: LogWatcher, profile: str, remote: Path) -> None:
    make_tree(remote, TREE)
    local = enable(app, logs, profile)
    wait_for_tree(local, TREE, on_poll=logs.check)

    apply_edits(remote, EDITS)
    app.send("poll", name=profile)
    wait_for_tree(local, edit_tree(TREE, EDITS), on_poll=logs.check)
