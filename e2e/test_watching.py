from pathlib import Path

from logwatch import LogWatcher
from sshadow import App, enable, presenting, wait_for_watching
from tree import Dir, Tree, make_tree, wait_for

TREE: Tree = {"docs": Dir()}


def test_presented_folder_is_watched_until_dismissed(
    app: App, logs: LogWatcher, profile: str, remote: Path
) -> None:
    make_tree(remote, TREE)
    local = enable(app, logs, profile)
    wait_for(lambda: "" if (local / "docs").exists() else "missing")

    with presenting(local / "docs"):
        wait_for_watching(logs, r'^Watching: \[Ref\(path: "docs", [^]]*\)\]$')
    wait_for_watching(logs, r"^Watching: \[\]$")
