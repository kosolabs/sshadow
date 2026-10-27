import re
from collections.abc import Callable
from pathlib import Path

from logwatch import LogWatcher, Matcher, msg
from sshadow import App, brokered, connected, dataless, enable, evict
from tree import Dir, File, Tree, make_tree, wait_for, wait_for_tree

TREE: Tree = {
    "a.txt": File(b"a\n"),
    "docs": Dir(),
    "docs/readme.md": File(b"# Readme\n"),
}


def materialized(path: str) -> Matcher:
    return msg(rf'^Materialized: .*\bpath: "{re.escape(path)}"[,)]')


def dematerialized(path: str) -> Matcher:
    return msg(rf'^Dematerialized: .*\bpath: "{re.escape(path)}"[,)]')


def evicted(path: Path) -> Callable[[], str]:
    # Eviction fails while File Provider is still syncing the item.
    return lambda: evict(path) or ""


def make_dataless(path: Path, logs: LogWatcher) -> None:
    wait_for(lambda: "" if path.exists() else "missing", on_poll=logs.check)
    if not dataless(path):
        wait_for(evicted(path), on_poll=logs.check)
        logs.expect(dematerialized(path.name), timeout=30)


def test_reading_and_evicting_file_updates_materialized_set(
    app: App, logs: LogWatcher, profile: str, remote: Path
) -> None:
    make_tree(remote, TREE)
    local = enable(app, logs, profile)
    path = local / "a.txt"
    make_dataless(path, logs)

    assert path.read_bytes() == b"a\n"
    logs.expect(materialized("a.txt"), timeout=30)

    wait_for(evicted(path), on_poll=logs.check)
    logs.expect(dematerialized("a.txt"), timeout=30)


def test_listing_folder_materializes_it(
    app: App, logs: LogWatcher, profile: str, remote: Path
) -> None:
    make_tree(remote, TREE)
    local = enable(app, logs, profile)
    wait_for(lambda: "" if (local / "docs").exists() else "missing")

    assert [p.name for p in (local / "docs").iterdir()] == ["readme.md"]
    logs.expect(materialized("docs"), timeout=30)


def test_new_local_file_is_materialized(
    app: App, logs: LogWatcher, profile: str, remote: Path
) -> None:
    local = enable(app, logs, profile)
    new: Tree = {"new.txt": File(b"new\n")}
    make_tree(local, new)

    logs.expect(materialized("new.txt"), timeout=30)
    wait_for_tree(remote, new, on_poll=logs.check)


def test_relaunch_reloads_materialized_set(
    app: App,
    logs: LogWatcher,
    profile: str,
    remote: Path,
    relaunch_app: Callable[[], None],
) -> None:
    make_tree(remote, TREE)
    local = enable(app, logs, profile)
    path = local / "a.txt"
    make_dataless(path, logs)
    path.read_bytes()
    logs.expect(materialized("a.txt"), timeout=30)

    app.quit()
    relaunch_app()
    logs.expect_all(
        [brokered(profile), connected(profile), materialized("a.txt")], timeout=60
    )

    wait_for(evicted(path), on_poll=logs.check)
    logs.expect(dematerialized("a.txt"), timeout=30)
