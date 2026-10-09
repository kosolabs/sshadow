import os
import stat
import time
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class File:
    contents: bytes
    mode: int | None = None
    mtime: int | None = None


@dataclass(frozen=True)
class Dir:
    mode: int | None = None
    mtime: int | None = None


@dataclass(frozen=True)
class Link:
    target: str
    mtime: int | None = None


Entry = File | Dir | Link
Tree = dict[str, Entry]

IGNORED = {".Trash", ".DS_Store"}


def make_tree(root: Path, tree: Tree) -> None:
    for rel, e in sorted(tree.items()):
        path = root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        match e:
            case Dir():
                path.mkdir(exist_ok=True)
            case Link(target):
                path.symlink_to(target)
            case File(contents):
                path.write_bytes(contents)
    # Children first, so creating them doesn't bump a parent's mtime.
    for rel, e in sorted(tree.items(), reverse=True):
        path = root / rel
        if not isinstance(e, Link) and e.mode is not None:
            path.chmod(e.mode)
        if e.mtime is not None:
            os.utime(path, (e.mtime, e.mtime), follow_symlinks=False)


def read_tree(root: Path) -> Tree:
    """Read every file under `root`, which downloads File Provider items."""
    tree: Tree = {}
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in IGNORED]
        base = Path(dirpath).relative_to(root)
        for name in dirnames + filenames:
            if name in IGNORED:
                continue
            path = Path(dirpath) / name
            st = path.lstat()
            mode, mtime = stat.S_IMODE(st.st_mode), int(st.st_mtime)
            if stat.S_ISLNK(st.st_mode):
                e = Link(os.readlink(path), mtime)
            elif stat.S_ISDIR(st.st_mode):
                e = Dir(mode, mtime)
            else:
                e = File(path.read_bytes(), mode, mtime)
            tree[str(base / name)] = e
    return tree


def same_mode(actual: int | None, expected: int | None) -> bool:
    if expected is None:
        return True
    return actual is not None and (actual & 0o700) == (expected & 0o700)


def matches(actual: Entry, expected: Entry) -> bool:
    if expected.mtime not in (None, actual.mtime):
        return False
    match actual, expected:
        case File(), File():
            return actual.contents == expected.contents and same_mode(
                actual.mode, expected.mode
            )
        case Dir(), Dir():
            return same_mode(actual.mode, expected.mode)
        case Link(), Link():
            return actual.target == expected.target
        case _:
            return False


def describe(e: Entry) -> str:
    match e:
        case File(contents, mode, mtime):
            desc = f"file ({len(contents)} bytes)"
        case Dir(mode, mtime):
            desc = "directory"
        case Link(target, mtime):
            desc, mode = f"symlink -> {target}", None
    if mode is not None:
        desc += f", mode {mode:o}"
    if mtime is not None:
        desc += f", mtime {time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(mtime))}"
    return desc


def diff_trees(actual: Tree, expected: Tree) -> str:
    lines = [f"missing: {p}" for p in sorted(expected.keys() - actual.keys())]
    lines += [f"unexpected: {p}" for p in sorted(actual.keys() - expected.keys())]
    lines += [
        f"differs: {p}: {describe(actual[p])}; expected {describe(expected[p])}"
        for p in sorted(expected.keys() & actual.keys())
        if not matches(actual[p], expected[p])
    ]
    return "\n".join(lines)


def wait_for_tree(
    root: Path,
    expected: Tree,
    *,
    timeout: float = 30,
    interval: float = 0.5,
    on_poll: Callable[[], None] = lambda: None,
) -> None:
    deadline = time.monotonic() + timeout
    while True:
        on_poll()
        actual = read_tree(root) if root.is_dir() else {}
        diff = diff_trees(actual, expected)
        if not diff:
            return
        if time.monotonic() >= deadline:
            raise AssertionError(f"{root} did not match within {timeout}s:\n{diff}")
        time.sleep(interval)
