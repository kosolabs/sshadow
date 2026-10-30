"""A guided manual test of the whole app. Run it with `just manual`.

Each step says what it does and what to look for, then either the script does
it or you do. Either way, the script checks files and console logs afterwards,
and you judge Finder, the menu, Settings and the Event Log.
"""

import getpass
import os
import shutil
import subprocess
import sys
import tempfile
import termios
import textwrap
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from pathlib import Path

from logwatch import LogWatcher, Matcher, msg
from proxy import Proxy
from sshadow import (
    REMOTE_ROOT,
    REPO,
    SERVER_PORT,
    App,
    cloud_storage,
    connected,
    dataless,
    evict,
    find_app,
    named,
    trash,
    uploading,
    wait_for_removal,
)
from tree import Dir, File, Link, Tree, wait_for, wait_for_tree

NAME = "ManualTest"
PROXY_PORT = 2249
WRONG_PORT = 2250
KEY = REPO / "TestKit" / "id_ed25519"
PREDICATE = 'subsystem BEGINSWITH "com.kosolabs.SSHadow"'
MiB = 1024 * 1024
# How long to wait for you to do something.
BY_HAND = 600

L = cloud_storage(NAME)
R = REMOTE_ROOT

BOLD = "\033[1m"
DIM = "\033[2m"
GREEN = "\033[32m"
RED = "\033[31m"
RESET = "\033[0m"
CLEAR_LINE = "\033[K"


@dataclass(frozen=True)
class Check:
    what: str
    wait: Callable[[float], object]
    timeout: float = 30


class Guide:
    def __init__(self, app: App, logs: LogWatcher, proxy: Proxy, key: Path):
        self.app = app
        self.logs = logs
        self.proxy = proxy
        self.key = key
        self.failures: list[str] = []

    def section(self, title: str, about: str) -> None:
        print(f"\n\n{BOLD}━━ {title} {'━' * (60 - len(title))}{RESET}")
        print(wrap(about, 0))

    def act(
        self,
        title: str,
        *,
        run: str | None = None,
        do: Callable[[], object] | None = None,
        doing: str | None = None,
        by_hand: str | None = None,
        expect: Sequence[str] = (),
        checks: Sequence[Check] = (),
        confirm: bool = False,
    ) -> bool:
        """Describe a step, have it done, and check it. Return whether you did it."""
        print(f"\n{BOLD}▸ {title}{RESET}")
        if run:
            print("  The script will run:")
            for line in run.splitlines():
                print(f"    {DIM}${RESET} {line}")
        elif do:
            print(f"  The script will {doing}.")
        if by_hand:
            prefix = "Or do it yourself" if run or do else "Do it yourself"
            print(f"  {wrap(f'{prefix}: {by_hand}', 2)}")
        elif run:
            print("  Or run the commands yourself.")
        if expect:
            print("  Look for:")
            for line in expect:
                print(f"  • {wrap(line, 4)}")

        yourself = self.choose(scripted=bool(run or do), manual=bool(run or by_hand))
        if not yourself:
            if run:
                env = os.environ | {"L": str(L), "R": str(R)}
                subprocess.run(["bash", "-c", run], env=env, check=True)
            elif do:
                do()
        elif confirm or not checks:
            ask("Press Enter when done")

        for check in checks:
            timeout = max(check.timeout, BY_HAND) if yourself else check.timeout
            self.verify(check, timeout)
        return yourself

    def choose(self, *, scripted: bool, manual: bool) -> bool:
        if not scripted:
            return True
        if not manual:
            ask("Press Enter to go")
            return False
        while True:
            answer = ask("Press Enter to go, or m to do it yourself")
            if answer in ("", "m"):
                return answer == "m"

    def verify(self, check: Check, timeout: float) -> None:
        print(f"  {DIM}… {check.what}{RESET}", end="", flush=True)
        try:
            check.wait(timeout)
        except (AssertionError, TimeoutError) as e:
            print(f"\r  {RED}✗ {check.what}{RESET}{CLEAR_LINE}")
            details = str(e).split("\n\nrecent events:")[0]
            print(textwrap.indent(details, "    "))
            self.failures.append(check.what)
        else:
            print(f"\r  {GREEN}✓ {check.what}{RESET}{CLEAR_LINE}")

    def logged(self, what: str, matcher: Matcher, timeout: float = 30) -> Check:
        return Check(what, lambda t: self.logs.expect(matcher, timeout=t), timeout)


def ask(prompt: str) -> str:
    termios.tcflush(sys.stdin, termios.TCIFLUSH)
    return input(f"  {DIM}{prompt}…{RESET} ").strip().lower()


def wrap(text: str, indent: int) -> str:
    return textwrap.fill(text, 78, subsequent_indent=" " * indent)


def until(what: str, condition: Callable[[], str], timeout: float = 30) -> Check:
    return Check(what, lambda t: wait_for(condition, timeout=t), timeout)


def matches(what: str, root: Path, tree: Tree, timeout: float = 30) -> Check:
    return Check(what, lambda t: wait_for_tree(root, tree, timeout=t), timeout)


def exists(path: Path) -> Callable[[], str]:
    return lambda: "" if path.exists() else f"{path} doesn't exist"


def missing(path: Path) -> Callable[[], str]:
    return lambda: f"{path} still exists" if path.exists() else ""


def downloaded(path: Path, want: bool) -> Callable[[], str]:
    def check() -> str:
        if not path.exists():
            return f"{path} doesn't exist"
        if dataless(path) == want:
            return f"{path} is {'still' if want else 'already'} a placeholder"
        return ""

    return check


def size(path: Path, expected: int) -> Callable[[], str]:
    def check() -> str:
        actual = path.stat().st_size if path.exists() else None
        return "" if actual == expected else f"{path} is {actual} bytes"

    return check


def pasted() -> str:
    return subprocess.run(
        ["pbpaste"], capture_output=True, text=True, check=True
    ).stdout


def clipboard(expected: str) -> Check:
    def check(_: float) -> None:
        if (actual := pasted()).rstrip("/") != expected:
            raise AssertionError(f"clipboard has {actual!r}")

    return Check(f"The clipboard has {expected}", check)


def copied_entries(_: float) -> None:
    lines = pasted().splitlines()
    if len(lines) < 10:
        raise AssertionError(f"clipboard has {len(lines)} line(s)")
    print(f"\r  {DIM}The clipboard starts:{RESET}{CLEAR_LINE}")
    for line in lines[:3]:
        print(f"    {DIM}{line[:74]}{RESET}")


def paused(name: str) -> Matcher:
    return msg(rf"^Supervisor paused: .*{named(name, 'displayName')}")


def reconnecting(name: str) -> Matcher:
    return msg(rf"^Session reconnecting: .*{named(name)}")


FULL_POLL = msg(r"^Poll: .*, anchor: \d+$")


def setup() -> Guide:
    print(f"{BOLD}SSHadow manual test{RESET}")
    app = App(find_app())
    while app.started() is not None:
        ask("SSHadow is running. Quit it, then press Enter")

    # The app can only read a key it's asked to open.
    key = Path(tempfile.mkdtemp()) / KEY.name
    shutil.copy(KEY, key)
    logs = LogWatcher(PREDICATE)
    launch(app, logs, key)

    app.send("delete", name=NAME)
    try:
        logs.expect(msg(rf"^Profile deleted: .*{named(NAME)}"), timeout=5)
        print(f"Deleted the {NAME} connection from the last run.")
    except TimeoutError:
        pass
    wait_for_removal(L)

    shutil.rmtree(R, ignore_errors=True)
    R.mkdir()
    proxy = Proxy(("127.0.0.1", SERVER_PORT), host="::", port=PROXY_PORT)

    subprocess.run(["open", R], check=True)
    subprocess.run(
        [
            "osascript",
            "-e",
            f'tell application "Terminal" to do script "cd {REPO} && just log"',
        ],
        check=True,
        capture_output=True,
    )

    print(
        "\nOpen the Event Log from the SSHadow menu, and arrange it beside the "
        f"Finder window on {R} and the `just log` window."
    )
    print("To run commands yourself, first run this in your terminal:")
    print(f'  export L="{L}" R="{R}"')
    ask("Press Enter to start")
    return Guide(app, logs, proxy, key)


def launch(app: App, logs: LogWatcher, key: Path) -> None:
    app.launch(files=[key])
    logs.expect(msg("^Test commands enabled$"))


def create_connection(g: Guide) -> None:
    g.section(
        "1. Create a connection",
        "From the menu's onboarding to a working connection, and the menu's "
        "copy actions.",
    )

    def create() -> None:
        g.app.send(
            "create",
            name=NAME,
            host="localhost",
            port=PROXY_PORT,
            user=getpass.getuser(),
            path=R,
            key=g.key,
        )
        g.logs.expect(msg(rf"Profile created: .*{named(NAME)}"))
        g.app.send("enable", name=NAME)

    g.act(
        "Create and enable the connection",
        do=create,
        doing=f"create {NAME} and enable it",
        by_hand=(
            "Open the SSHadow menu and click Add Your First Connection. If you "
            "have other connections, choose Connections & Settings… → Add "
            f"Connection instead. Fill in Display Name {NAME}, Hostname "
            f"localhost, Port {PROXY_PORT} and Remote Path {R}. Turn on Use "
            f"Private Key and choose {KEY} (press ⇧⌘G and paste the path). "
            "Then turn on Enabled."
        ),
        expect=[
            "Settings' Status row shows Connecting…, then Connected.",
            f"Event Log: INFO Connecting to {NAME}, then NOTICE Connected to {NAME}.",
            "The menu row shows the connection is online.",
        ],
        checks=[
            g.logged("Connected", connected(NAME)),
            until("The mounted folder appeared", exists(L)),
        ],
    )
    g.act(
        "Show the mounted folder in Finder",
        run='open "$L"',
        by_hand="Right-click the connection in the menu and choose Show in Finder.",
        expect=["A Finder window on the mounted folder. Keep it open."],
    )
    g.act(
        "Copy the mounted folder's path",
        by_hand="Right-click the connection and choose Copy Path.",
        checks=[clipboard(str(L))],
        confirm=True,
    )
    g.act(
        "Copy the SSH command",
        by_hand="Right-click the connection and choose Copy SSH Command.",
        checks=[clipboard(f"ssh -p {PROXY_PORT} {getpass.getuser()}@localhost")],
        confirm=True,
    )


def mac_changes(g: Guide) -> None:
    g.section(
        "2. Changes on the Mac",
        "Each change reaches the server, and the Event Log names it in a File entry.",
    )
    g.act(
        "Create a folder, a file and a symlink",
        run='mkdir "$L/docs"\necho one > "$L/docs/a.txt"\nln -s a.txt "$L/docs/link.txt"',
        expect=[
            (
                'Event Log: Create directory "docs", Upload "docs/a.txt" with its '
                'size, and Create symlink from "docs/link.txt" to a.txt, possibly '
                "with Set attributes entries between them."
            )
        ],
        checks=[
            matches(
                "They reached the server",
                R,
                {
                    "docs": Dir(),
                    "docs/a.txt": File(b"one\n"),
                    "docs/link.txt": Link("a.txt"),
                },
            )
        ],
    )
    g.act(
        "Rename the file and delete the symlink",
        run='mv "$L/docs/a.txt" "$L/docs/b.txt"\nrm "$L/docs/link.txt"',
        expect=[
            (
                'Event Log: Move "docs/a.txt" to "docs/b.txt", then Remove file '
                '"docs/link.txt".'
            )
        ],
        checks=[
            matches(
                "The server matches",
                R,
                {"docs": Dir(), "docs/b.txt": File(b"one\n")},
            )
        ],
    )


def server_changes(g: Guide) -> None:
    g.section(
        "3. Changes on the server",
        "Folders open in Finder are checked every 10 seconds. The Event Log "
        "shows a row for each change, then a summary.",
    )
    g.act(
        "Open docs in Finder",
        run='open "$L/docs"',
        by_hand="Open docs in the mounted Finder window.",
        expect=["A Finder window on docs, showing b.txt. Keep it open."],
    )
    r = L / "docs/r.txt"
    g.act(
        "Add a file and edit another on the server",
        run='echo remote > "$R/docs/r.txt"\necho \'server edit\' > "$R/docs/b.txt"',
        expect=[
            "Within 10 seconds, r.txt appears in Finder with a cloud icon.",
            (
                'Event Log: INFO Added "docs/r.txt" and INFO Changed "docs/b.txt" '
                "in either order, then NOTICE Detected 2 change(s) on server."
            ),
        ],
        checks=[until("r.txt appeared", exists(r))],
    )
    g.act(
        "Download r.txt",
        run='cat "$L/docs/r.txt" > /dev/null',
        by_hand="Click r.txt's cloud icon in Finder.",
        expect=['The cloud icon goes away. Event Log: Download "docs/r.txt".'],
        checks=[until("r.txt downloaded", downloaded(r, True))],
    )
    g.act(
        "Remove r.txt's download",
        do=lambda: evict(r),
        doing="evict r.txt, as Remove Download does",
        by_hand="Right-click r.txt in Finder and choose Remove Download.",
        expect=['The cloud icon comes back. Event Log: Evicted "docs/r.txt".'],
        checks=[until("r.txt is a placeholder again", downloaded(r, False))],
    )
    g.act(
        "Delete r.txt on the server",
        run='rm "$R/docs/r.txt"',
        expect=[
            "Within 10 seconds, r.txt disappears from Finder.",
            (
                'Event Log: INFO Removed "docs/r.txt", then NOTICE Detected 1 '
                "change(s) on server."
            ),
        ],
        checks=[until("r.txt disappeared", missing(r))],
    )
    g.act(
        "Check for remote changes when nothing changed",
        do=lambda: g.app.send("poll", name=NAME),
        doing="check the server, as Check for Remote Changes does",
        by_hand="Right-click the connection and choose Check for Remote Changes.",
        expect=["Event Log: INFO No changes on server."],
        checks=[g.logged("Checked the server", FULL_POLL)],
    )
    g.act(
        "Move b.txt to the Trash",
        do=lambda: trash(L / "docs/b.txt"),
        doing="move b.txt to the Trash, as Finder does",
        by_hand="In Finder, move b.txt to the Trash.",
        expect=['Event Log: Move "docs/b.txt" to ".sshadow/trash/b.txt".'],
        checks=[
            until(
                "b.txt is in the server's trash",
                exists(R / ".sshadow/trash/b.txt"),
            )
        ],
    )


def transfers(g: Guide) -> None:
    g.section(
        "4. Transfers, pause and resume",
        "Uploads are slowed to 1 MB/s here, so there's time to look at the "
        "menu and pause partway through.",
    )
    g.proxy.rate = MiB
    big = R / "big.bin"
    g.act(
        "Write a 30 MB file",
        run='mkfile -n 30m "$L/big.bin"',
        expect=[
            (
                "Open the SSHadow menu: a Transfers section shows big.bin with a "
                "progress bar."
            )
        ],
        checks=[g.logged("The upload started", uploading("big.bin"))],
    )
    g.act(
        "Pause during the upload",
        do=lambda: g.app.send("pause", name=NAME),
        doing="pause the connection",
        by_hand="Right-click the connection and choose Pause Connection.",
        expect=[
            "The upload stops, and the menu row shows the connection is paused.",
            f"Event Log: NOTICE Paused connection to {NAME}.",
        ],
        checks=[g.logged("Paused", paused(NAME))],
    )
    g.proxy.rate = None
    g.act(
        "Resume the connection",
        do=lambda: g.app.send("enable", name=NAME),
        doing="resume the connection",
        by_hand="Right-click the connection and choose Resume Connection.",
        expect=[
            f"Event Log: Connecting to {NAME}, then Connected to {NAME}.",
            "The upload starts again at full speed and finishes.",
        ],
        checks=[
            g.logged("Connected", connected(NAME)),
            until("big.bin uploaded", size(big, 30 * MiB), timeout=60),
        ],
    )
    g.act(
        "Delete big.bin",
        run='rm "$L/big.bin"',
        expect=['Event Log: Remove file "big.bin".'],
        checks=[until("big.bin is gone from the server", missing(big))],
    )


def outage(g: Guide) -> None:
    g.section(
        "5. Server outage",
        "The proxy between SSHadow and the server drops the connection and "
        "refuses new ones, as if the server went down.",
    )
    g.act(
        "Take the server down",
        do=g.proxy.refuse,
        doing="drop the connection and refuse new ones",
        expect=[
            (
                f"Within 10 seconds, Event Log: WARNING Lost connection to {NAME}, "
                f"then WARNING Reconnecting to {NAME} with Next attempt at … in "
                "the detail, repeating with longer gaps."
            ),
            (
                "Settings' Status row shows the error and Reconnecting in Ns… "
                "counting down, with a Pause button."
            ),
        ],
        checks=[g.logged("Reconnecting", reconnecting(NAME))],
    )
    g.act(
        "Write a file while the server is down",
        run='echo offline > "$L/docs/offline.txt"',
        expect=["offline.txt appears in Finder, but doesn't upload yet."],
    )
    g.act(
        "Bring the server back",
        do=g.proxy.restore,
        doing="accept connections again",
        expect=[
            (
                "Within a minute, at the next attempt, Event Log: NOTICE Connected "
                f'to {NAME}, then Upload "docs/offline.txt".'
            )
        ],
        checks=[
            g.logged("Connected", connected(NAME), timeout=90),
            matches(
                "offline.txt uploaded",
                R,
                {"docs": Dir(), "docs/offline.txt": File(b"offline\n")},
            ),
        ],
    )


def failed_connection(g: Guide) -> None:
    g.section(
        "6. Failed connection and Clear Status",
        "A connection that fails to connect shows its error until you clear it.",
    )
    g.act(
        "Pause the connection",
        do=lambda: g.app.send("pause", name=NAME),
        doing="pause the connection",
        by_hand="Right-click the connection and choose Pause Connection.",
        expect=["In the connection's right-click menu, Clear Status is greyed out."],
        checks=[g.logged("Paused", paused(NAME))],
    )
    port_changed = g.act(
        "Break the connection",
        do=g.proxy.refuse,
        doing="refuse connections at the proxy",
        by_hand=f"In Settings, set Port to {WRONG_PORT}.",
    )
    g.act(
        "Resume the connection",
        do=lambda: g.app.send("enable", name=NAME),
        doing="resume the connection",
        by_hand="Right-click the connection and choose Resume Connection.",
        expect=[
            (
                f"Event Log: ERROR Failed to connect to {NAME}, with the reason in "
                "the detail."
            ),
            "Settings' Status row shows the error, with Clear and Reconnect buttons.",
            "The menu row shows an error icon.",
        ],
        checks=[
            g.logged("Failed to connect", msg(rf"^Failed to enable .*{named(NAME)}"))
        ],
    )
    g.act(
        "Clear the error",
        do=lambda: g.app.send("pause", name=NAME),
        doing="pause the connection, which is what Clear Status does",
        by_hand="Right-click the connection and choose Clear Status.",
        expect=["The Status row shows Paused, and the error icon is gone."],
        checks=[g.logged("Paused", paused(NAME))],
    )
    if port_changed:
        g.act("Fix the connection", by_hand=f"Set Port back to {PROXY_PORT}.")
    else:
        g.proxy.restore()
    g.act(
        "Reconnect",
        do=lambda: g.app.send("enable", name=NAME),
        doing="resume the connection",
        by_hand="Click Reconnect in Settings.",
        expect=[f"Event Log: Connected to {NAME}."],
        checks=[g.logged("Connected", connected(NAME))],
    )


def event_log(g: Guide) -> None:
    g.section("7. Event Log", "Search, filters, copying and clearing.")
    g.act(
        "Search",
        by_hand="Search for docs/, then for zzz, then clear the search.",
        expect=[
            "For docs/, only entries mentioning docs/ in their message or detail.",
            "For zzz, the window shows there are no results.",
        ],
    )
    g.act(
        "Filter",
        by_hand=(
            "In Filter, turn off Info, then turn off Connection. Turn both back on."
        ),
        expect=[
            "Without Info, only notices, warnings and errors.",
            (
                "Without Connection too, only the Detected … entries and any "
                "failed transfers."
            ),
        ],
    )
    g.act(
        "Copy every entry",
        by_hand="Click an entry, then press ⌘A and ⌘C.",
        checks=[Check("Copied the entries", copied_entries)],
        confirm=True,
    )
    g.act(
        "Reopen and clear",
        by_hand="Close and reopen the Event Log. Then click Clear.",
        expect=[
            "After reopening, the filter shows everything again.",
            "After clearing, the window shows No Events.",
        ],
    )


def relaunch(g: Guide) -> None:
    g.section(
        "8. Quit and relaunch",
        "A change made on the server while SSHadow is quit shows up after it "
        "relaunches.",
    )
    g.act(
        "Quit SSHadow",
        do=g.app.quit,
        doing="quit SSHadow",
        by_hand="Choose Quit SSHadow from its menu.",
        expect=["The menu bar icon goes away."],
        checks=[
            until(
                "SSHadow quit",
                lambda: "SSHadow is running" if g.app.started() else "",
            )
        ],
    )
    g.act(
        "Change the server while SSHadow is quit",
        run='echo quit > "$R/docs/while-quit.txt"',
    )
    g.act(
        "Relaunch SSHadow",
        do=lambda: launch(g.app, g.logs, g.key),
        doing="launch SSHadow",
        expect=[
            (
                "The menu bar icon comes back. Open the Event Log: Connecting to "
                f"{NAME}, then Connected to {NAME}."
            )
        ],
        checks=[g.logged("Connected", connected(NAME), timeout=60)],
    )
    g.act(
        "Check for remote changes",
        do=lambda: g.app.send("poll", name=NAME),
        doing="check the server, as Check for Remote Changes does",
        by_hand="Right-click the connection and choose Check for Remote Changes.",
        expect=[
            (
                "while-quit.txt appears in Finder. Event Log: Added "
                '"docs/while-quit.txt".'
            )
        ],
        checks=[until("while-quit.txt appeared", exists(L / "docs/while-quit.txt"))],
    )


def disable(g: Guide) -> None:
    g.section("9. Disable", "Disabling removes the mounted folder, not the files.")
    g.act(
        "Disable the connection",
        do=lambda: g.app.send("disable", name=NAME),
        doing="disable the connection",
        by_hand="Turn off the connection's toggle in the SSHadow menu.",
        expect=[
            f"Event Log: NOTICE Disconnected from {NAME}.",
            "The connection is gone from Finder's sidebar.",
        ],
        checks=[
            g.logged("Disabled", msg(rf"^Profile disabled: .*{named(NAME)}")),
            Check("The mounted folder is gone", lambda t: wait_for_removal(L, t)),
            matches(
                "The server kept every file",
                R,
                {
                    "docs": Dir(),
                    "docs/offline.txt": File(b"offline\n"),
                    "docs/while-quit.txt": File(b"quit\n"),
                },
            ),
        ],
    )
    g.act(
        "Open the disabled connection's settings",
        by_hand="Click the disabled connection in the SSHadow menu.",
        expect=["Settings opens with that connection selected."],
    )


def finish(g: Guide) -> None:
    g.section("Done", "")
    if g.failures:
        print(f"{RED}{len(g.failures)} check(s) failed:{RESET}")
        for failure in g.failures:
            print(f"  • {failure}")
    else:
        print(f"{GREEN}Every check passed.{RESET}")
    if ask(f"Delete the {NAME} connection? [y/N]") == "y":
        g.app.send("delete", name=NAME)
        g.verify(g.logged("Deleted", msg(rf"^Profile deleted: .*{named(NAME)}")), 30)


def main() -> None:
    g = setup()
    try:
        for step in [
            create_connection,
            mac_changes,
            server_changes,
            transfers,
            outage,
            failed_connection,
            event_log,
            relaunch,
            disable,
        ]:
            step(g)
        finish(g)
    except KeyboardInterrupt:
        print(f"\nStopped. Rerun to start over; it deletes {NAME} first.")
    finally:
        g.proxy.close()
        g.logs.close()


if __name__ == "__main__":
    main()
