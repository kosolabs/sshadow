import random
from collections.abc import Callable
from datetime import UTC, datetime
from pathlib import Path

import pytest

from logwatch import LogWatcher
from sshadow import App, enable, evict, replace_item, trash
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
    wait_for,
    wait_for_tree,
)

# File.defaultChunkSize, the unit the app reads and caches files in.
CHUNK = 256 * 1024
TRASH = ".sshadow/trash"


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


def test_upload_local_edits(
    app: App, logs: LogWatcher, profile: str, remote: Path
) -> None:
    local = enable(app, logs, profile)
    make_tree(local, TREE)
    wait_for_tree(remote, TREE, on_poll=logs.check)

    apply_edits(local, EDITS)
    wait_for_tree(remote, edit_tree(TREE, EDITS), on_poll=logs.check)


def test_download_remote_edits(
    app: App, logs: LogWatcher, profile: str, remote: Path
) -> None:
    make_tree(remote, TREE)
    local = enable(app, logs, profile)
    wait_for_tree(local, TREE, on_poll=logs.check)

    apply_edits(remote, EDITS)
    app.send("poll", name=profile)
    wait_for_tree(local, edit_tree(TREE, EDITS), on_poll=logs.check)


def save_by_rename(path: Path, contents: bytes) -> None:
    tmp = path.with_name(f".{path.name}.tmp")
    tmp.write_bytes(contents)
    tmp.replace(path)


def save_with_backup(path: Path, contents: bytes) -> None:
    backup = path.with_name(f"{path.name}~")
    path.rename(backup)
    path.write_bytes(contents)
    backup.unlink()


@pytest.mark.parametrize(
    "save",
    [save_by_rename, replace_item, save_with_backup],
    ids=["rename", "replace-item", "backup"],
)
def test_atomic_save(
    app: App,
    logs: LogWatcher,
    profile: str,
    remote: Path,
    save: Callable[[Path, bytes], None],
) -> None:
    local = enable(app, logs, profile)
    tree: Tree = {"doc.txt": File(b"version 0\n")}
    make_tree(local, tree)
    wait_for_tree(remote, tree, on_poll=logs.check)

    for i in range(1, 3):
        contents = f"version {i}\n".encode()
        save(local / "doc.txt", contents)
        tree = {"doc.txt": File(contents)}
        wait_for_tree(remote, tree, on_poll=logs.check)
        wait_for_tree(local, tree, on_poll=logs.check)

    # Saving again before the last save has synced, as autosave can.
    for i in range(3, 8):
        save(local / "doc.txt", f"version {i}\n".encode())
    tree = {"doc.txt": File(b"version 7\n")}
    wait_for_tree(remote, tree, on_poll=logs.check)
    wait_for_tree(local, tree, on_poll=logs.check)


def read_range(path: Path, offset: int, length: int) -> bytes:
    with path.open("rb") as f:
        f.seek(offset)
        return f.read(length)


def range_matches(path: Path, offset: int, expected: bytes) -> Callable[[], str]:
    def check() -> str:
        if read_range(path, offset, len(expected)) == expected:
            return ""
        return f"{path} has the wrong contents at {offset}"

    return check


def exists(path: Path) -> Callable[[], str]:
    return lambda: "" if path.exists() else f"{path} doesn't exist"


def evicted(path: Path) -> Callable[[], str]:
    # Eviction fails while File Provider is still syncing the item.
    return lambda: evict(path) or ""


# Offsets in a chunk the first read fetches, and in one it prefetches.
OFFSETS = [4 * CHUNK + 100, 5 * CHUNK + 100]


def test_remote_edit_after_read(
    app: App, logs: LogWatcher, profile: str, remote: Path
) -> None:
    old = random.Random(1).randbytes(16 * CHUNK)
    new = random.Random(2).randbytes(16 * CHUNK)
    make_tree(remote, {"big.bin": File(old, mtime=date("2026-01-01"))})
    local = enable(app, logs, profile)
    path = local / "big.bin"
    wait_for(exists(path), on_poll=logs.check)
    assert read_range(path, OFFSETS[0], 4096) == old[OFFSETS[0] : OFFSETS[0] + 4096]

    make_tree(remote, {"big.bin": File(new, mtime=date("2026-02-02"))})
    app.send("poll", name=profile)
    for offset in OFFSETS:
        expected = new[offset : offset + 4096]
        wait_for(range_matches(path, offset, expected), on_poll=logs.check)
    wait_for_tree(local, {"big.bin": File(new)}, on_poll=logs.check)


def evict_files(root: Path, tree: Tree, logs: LogWatcher) -> None:
    for rel, e in tree.items():
        # A package is one item, evicted as a whole.
        parents = Path(rel).parts[:-1]
        if any(Path(p).suffix == ".rtfd" for p in parents):
            continue
        if isinstance(e, File) or Path(rel).suffix == ".rtfd":
            wait_for(evicted(root / rel), on_poll=logs.check)


def test_evict(app: App, logs: LogWatcher, profile: str, remote: Path) -> None:
    make_tree(remote, TREE)
    local = enable(app, logs, profile)
    wait_for_tree(local, TREE, on_poll=logs.check)

    evict_files(local, TREE, logs)
    apply_edits(remote, EDITS)
    app.send("poll", name=profile)
    wait_for_tree(local, edit_tree(TREE, EDITS), on_poll=logs.check)


def test_trash(app: App, logs: LogWatcher, profile: str, remote: Path) -> None:
    tree: Tree = {
        "hello.txt": File(b"hello\n"),
        "docs": Dir(),
        "docs/readme.md": File(b"# Readme\n"),
    }
    local = enable(app, logs, profile)
    make_tree(local, tree)
    wait_for_tree(remote, tree, on_poll=logs.check)

    trashed = [trash(local / "hello.txt"), trash(local / "docs")]
    wait_for_tree(local, {}, on_poll=logs.check)
    wait_for_tree(local / ".Trash", tree, on_poll=logs.check)
    wait_for_tree(remote, {}, on_poll=logs.check)
    wait_for_tree(remote / TRASH, tree, on_poll=logs.check)

    # Trash another file with the same name.
    again: Tree = {"hello.txt": File(b"hello again\n")}
    make_tree(local, again)
    wait_for_tree(remote, again, on_poll=logs.check)
    second = trash(local / "hello.txt")
    left: Tree = {second.name: File(b"hello again\n")}
    wait_for_tree(local, {}, on_poll=logs.check)
    wait_for_tree(local / ".Trash", tree | left, on_poll=logs.check)
    wait_for_tree(remote, {}, on_poll=logs.check)
    wait_for_tree(remote / TRASH, tree | left, on_poll=logs.check)

    # Put back.
    for path in trashed:
        path.rename(local / path.name)
    wait_for_tree(local, tree, on_poll=logs.check)
    wait_for_tree(local / ".Trash", left, on_poll=logs.check)
    wait_for_tree(remote, tree, on_poll=logs.check)
    wait_for_tree(remote / TRASH, left, on_poll=logs.check)

    # Empty the Trash.
    second.unlink()
    wait_for_tree(local / ".Trash", {}, on_poll=logs.check)
    wait_for_tree(remote, tree, on_poll=logs.check)
    wait_for_tree(remote / TRASH, {}, on_poll=logs.check)
