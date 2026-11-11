"""A guided manual test of the whole app. Run it with `just manual`.

Each section can be walked through or run automatically. When walking through,
each step says what it does and what to look for. Press Enter and the script
does it, or do it yourself and the script notices. Either way, the script
checks files and console logs afterwards, and you judge Finder, the menu,
Settings and the Event Log.

The walkthrough tells one story in parts: setup, sync, connection, the
interface (the SSHadow menu, Settings and the Event Log), then teardown. Each
section picks up where the last one left off, so related steps sit together
and you don't have to switch context to follow along. Running a section
automatically skips the steps that need you.

Churn in this file is fine when it serves that story: move, merge or split
steps and sections whenever it keeps related things together.
"""

import getpass
import os
import re
import shutil
import subprocess
import sys
import tempfile
import termios
import threading
import time
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from pathlib import Path

import questionary
from prompt_toolkit.filters import IsDone
from prompt_toolkit.formatted_text import StyleAndTextTuples
from prompt_toolkit.layout import ConditionalContainer, HSplit, Window
from prompt_toolkit.layout.controls import FormattedTextControl
from rich.console import Console
from rich.markup import escape
from rich.padding import Padding
from rich.table import Table

from impostor import Impostor
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
    reset_settings,
    trash,
    uploading,
    wait_for_removal,
)
from tree import Dir, File, Link, Tree, wait_for, wait_for_tree

NAME = "ManualTest"
PROXY_PORT = 2249
WRONG_PORT = 2250
IMPOSTOR_PORT = 2251
KEY = REPO / "TestKit" / "id_ed25519"
PREDICATE = 'subsystem BEGINSWITH "com.kosolabs.SSHadow"'
MiB = 1024 * 1024
# How long to wait for you to do something.
BY_HAND = 600

L = cloud_storage(NAME)
R = REMOTE_ROOT

console = Console(highlight=False)
# Rich's default spinner, so waiting looks the same in menus as elsewhere.
SPINNER = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
SPINNER_INTERVAL = 0.08


@dataclass(frozen=True)
class Check:
    what: str
    wait: Callable[[float], object]
    timeout: float = 30


class Guide:
    def __init__(
        self,
        app: App,
        logs: LogWatcher,
        proxy: Proxy,
        impostor: Impostor,
        key: Path,
    ):
        self.app = app
        self.logs = logs
        self.proxy = proxy
        self.impostor = impostor
        self.key = key
        self.failures: list[str] = []
        self.auto = False
        self.parts = 0
        self.sections = 0
        self.steps = 0

    def part(self, title: str) -> None:
        self.parts += 1
        self.sections = 0
        console.print()
        console.rule(f"[bold]{self.parts}. {escape(title)}", characters="═")

    def section(self, title: str, about: str) -> None:
        self.sections += 1
        self.steps = 0
        console.print()
        number = f"{self.parts}.{self.sections}"
        console.rule(f"[bold]{number}. {escape(title)}", align="left")
        console.print(escape(about))
        automatically = "Run it automatically"
        self.auto = menu([automatically, "Walk me through it"]) == automatically

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
        self.steps += 1
        heading = f"{self.parts}.{self.sections}.{self.steps} {escape(title)}"
        scripted = bool(run or do)
        manual = bool(run or by_hand)

        if self.auto:
            if not scripted:
                console.print(
                    f"\n[bold dim]{heading}[/] [dim]skipped, since it needs you"
                )
                return False
            console.print(f"\n[bold]{heading}")
            self.perform(run, do)
            for check in checks:
                self.verify(check, check.timeout)
            return False

        console.print(f"\n[bold]{heading}")
        if run:
            several = "\n" in run
            lead = (
                f"{by_hand} Or let the script run:"
                if by_hand
                else "Run these yourself, or let the script run them:"
                if several
                else "Run this yourself, or let the script run it:"
            )
            indented(escape(lead))
            for line in run.splitlines():
                indented(f"[dim]$[/] {escape(line)}", 4)
        elif do and by_hand:
            indented(escape(f"{by_hand} Or let the script {doing}."))
        elif do:
            indented(escape(f"The script will {doing}."))
        elif by_hand:
            indented(escape(by_hand))
        if expect:
            indented("Look for:")
            for line in expect:
                bullet(line)

        if not scripted:
            yourself = True
            if confirm or not checks:
                menu(["Done"])
        else:
            watch = checks[0] if manual and checks else None
            yourself = self.go(run, watch, manual=manual)
            if yourself and watch:
                checks = checks[1:]

        if not yourself:
            self.perform(run, do)
        for check in checks:
            timeout = max(check.timeout, BY_HAND) if yourself else check.timeout
            self.verify(check, timeout)
        return yourself

    def perform(self, run: str | None, do: Callable[[], object] | None) -> None:
        if run:
            env = os.environ | {"L": str(L), "R": str(R)}
            subprocess.run(["bash", "-c", run], env=env, check=True)
        elif do:
            do()

    def go(self, run: str | None, watch: Check | None, *, manual: bool) -> bool:
        """Ask whether to do a step, watching for you to do it instead.

        Return whether you did it. Without `watch` to tell, you say so.
        """
        go, done = "Let the script do it", "I've done it"
        copy = "Copy the commands" if run and "\n" in run else "Copy the command"
        choices = [go]
        if run:
            choices.append(copy)
        if manual and watch is None:
            choices.append(done)
        while True:
            answer = menu(choices, watch=watch)
            if answer is None and watch:
                passed(watch.what)
                return True
            if answer != copy or run is None:
                return answer == done
            commands = run.replace("$L", str(L)).replace("$R", str(R))
            subprocess.run(["pbcopy"], input=commands, text=True, check=True)
            indented("[dim]Copied.")

    def verify(self, check: Check, timeout: float) -> None:
        errors: list[Exception] = []

        def attempt() -> None:
            try:
                check.wait(timeout)
            except (AssertionError, TimeoutError, OSError) as e:
                errors.append(e)

        thread = threading.Thread(target=attempt, daemon=True)
        started = time.monotonic()
        with console.status(escape(check.what)) as status:
            thread.start()
            while thread.is_alive():
                elapsed = int(time.monotonic() - started)
                status.update(f"{escape(check.what)} [dim]{elapsed}s")
                thread.join(0.2)
        if errors:
            console.print(f"  [red]✗ {escape(check.what)}")
            details = str(errors[0]).split("\n\nrecent events:")[0]
            indented(f"[dim]{escape(details)}", 4)
            self.failures.append(check.what)
        else:
            passed(check.what)

    def logged(self, what: str, matcher: Matcher, timeout: float = 30) -> Check:
        return Check(what, lambda t: self.logs.expect(matcher, timeout=t), timeout)

    def watching(self, what: str, path: str) -> Check:
        """Wait for a Finder window on `path`, which keeps it watched.

        File Provider also watches folders briefly when it enumerates them, so
        the watch has to last a second.
        """
        matcher = msg(r"^Watching: ")
        ref = f'Ref(path: "{path}",'
        since: float | None = None

        def wait(timeout: float) -> None:
            nonlocal since
            deadline = time.monotonic() + timeout
            while since is None or time.monotonic() - since < 1:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise TimeoutError(f"{L / path} isn't open in Finder")
                try:
                    event = self.logs.expect(matcher, timeout=min(remaining, 0.25))
                except TimeoutError:
                    continue
                if ref not in event["eventMessage"]:
                    since = None
                elif since is None:
                    since = time.monotonic()

        return Check(what, wait)


def menu(
    choices: list[str], *, question: str = "", watch: Check | None = None
) -> str | None:
    """Ask you to pick one of `choices`. Return None if `watch` passes first."""
    termios.tcflush(sys.stdin, termios.TCIFLUSH)
    prompt = questionary.select(
        question,
        choices=choices,
        qmark=" ",
        pointer="▸",
        instruction=" ",
        refresh_interval=SPINNER_INTERVAL if watch else None,
    )
    if watch is None:
        return prompt.unsafe_ask()

    app = prompt.application
    started = time.monotonic()

    def status() -> StyleAndTextTuples:
        elapsed = time.monotonic() - started
        frame = SPINNER[int(elapsed / SPINNER_INTERVAL) % len(SPINNER)]
        return [
            ("fg:ansigreen", f"  {frame} "),
            ("", f"{watch.what} "),
            ("fg:ansibrightblack", f"{int(elapsed)}s"),
        ]

    layout = app.layout.container
    assert isinstance(layout, HSplit)
    layout.children.append(
        ConditionalContainer(
            Window(FormattedTextControl(status), height=1), filter=~IsDone()
        )
    )
    stop = threading.Event()
    watched = threading.Event()

    def poll() -> None:
        while not stop.is_set() and not watched.is_set():
            try:
                watch.wait(0.25)
            except (AssertionError, TimeoutError, OSError):
                continue
            watched.set()
        while not stop.is_set():
            if app.is_running and (loop := app.loop):
                loop.call_soon_threadsafe(exit_unanswered)
                return
            time.sleep(0.05)

    def exit_unanswered() -> None:
        if app.future and not app.future.done():
            app.exit()

    thread = threading.Thread(target=poll, daemon=True)
    thread.start()
    try:
        answer = prompt.unsafe_ask()
    finally:
        stop.set()
        thread.join()
    return None if watched.is_set() else answer


def indented(markup: str, indent: int = 2) -> None:
    console.print(Padding(markup, (0, 0, 0, indent)))


def bullet(text: str) -> None:
    grid = Table.grid(padding=(0, 1))
    grid.add_column()
    grid.add_column()
    grid.add_row("•", escape(text))
    console.print(Padding(grid, (0, 0, 0, 2)))


def passed(what: str) -> None:
    console.print(f"  [green]✓ {escape(what)}")


def until(what: str, condition: Callable[[], str], timeout: float = 30) -> Check:
    return Check(what, lambda t: wait_for(condition, timeout=t), timeout)


def stays(what: str, condition: Callable[[], str], seconds: float) -> Check:
    """Fail if `condition` reports a problem at any point in the next `seconds`."""

    def hold(_: float) -> None:
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            if problem := condition():
                raise AssertionError(problem)
            time.sleep(0.5)

    return Check(what, hold, seconds)


def matches(what: str, root: Path, tree: Tree, timeout: float = 30) -> Check:
    return Check(what, lambda t: wait_for_tree(root, tree, timeout=t), timeout)


def exists(path: Path) -> Callable[[], str]:
    return lambda: "" if path.exists() else f"{path} doesn't exist"


def missing(path: Path) -> Callable[[], str]:
    return lambda: f"{path} still exists" if path.exists() else ""


def in_trash(expected: bytes) -> Callable[[], str]:
    trash = R / ".sshadow/trash"

    def check() -> str:
        found = any(p.is_file() and p.read_bytes() == expected for p in trash.iterdir())
        return "" if found else f"Nothing in {trash} has {expected!r}"

    return check


def contains(path: Path, expected: bytes) -> Callable[[], str]:
    def check() -> str:
        actual = path.read_bytes() if path.exists() else None
        return "" if actual == expected else f"{path} has {actual!r}"

    return check


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


def paused(name: str) -> Matcher:
    return msg(rf"^Supervisor paused: .*{named(name, 'displayName')}")


def reconnecting(name: str) -> Matcher:
    return msg(rf"^Session reconnecting: .*{named(name)}")


def host_key_refused(name: str) -> Matcher:
    return msg(rf"^Failed to connect SSH config .*{named(name)}.*hostKeyMismatch")


def refused_once(impostor: Impostor, before: int) -> None:
    """Fail if SSHadow signed in to `impostor`, or connected more than once.

    Waits first, to give a retry time to happen.
    """
    time.sleep(5)
    if impostor.authenticated():
        raise AssertionError("SSHadow signed in to the second server")
    if (attempts := impostor.connections() - before) != 1:
        raise AssertionError(f"SSHadow connected {attempts} times, not once")


FULL_POLL = msg(r"^Poll: .*, anchor: \d+$")


def setup() -> Guide:
    console.rule("[bold]SSHadow manual test")
    app = App(find_app())
    while app.started() is not None:
        menu(["Done"], question="SSHadow is running. Quit it, then choose Done.")

    # The app can only read a key it's asked to open.
    key = Path(tempfile.mkdtemp()) / KEY.name
    shutil.copy(KEY, key)
    logs = LogWatcher(PREDICATE)
    launch(app, logs, key)
    reset_settings(app, logs)

    app.send("delete", name=NAME)
    try:
        logs.expect(msg(rf"^Profile deleted: .*{named(NAME)}"), timeout=5)
        console.print(f"Deleted the {NAME} connection from the last run.")
    except TimeoutError:
        pass
    wait_for_removal(L)

    app.send("open", window="events")
    logs.expect(msg("^Opened window: events$"))

    shutil.rmtree(R, ignore_errors=True)
    R.mkdir()
    proxy = Proxy(("127.0.0.1", SERVER_PORT), host="::", port=PROXY_PORT)
    impostor = Impostor(IMPOSTOR_PORT)

    subprocess.run(["open", R], check=True)

    console.print(f"\nArrange the Event Log beside the Finder window on {R}.")
    console.print("To run commands yourself, first run this in your terminal:")
    indented(f'export L="{L}" R="{R}"')
    menu(["Start"])
    return Guide(app, logs, proxy, impostor, key)


def launch(app: App, logs: LogWatcher, key: Path) -> None:
    app.launch(files=[key])
    logs.expect(msg("^Test commands enabled$"))


def open_event_log(g: Guide, title: str, expect: Sequence[str]) -> None:
    g.act(
        title,
        do=lambda: g.app.send("open", window="events"),
        doing="open the Event Log",
        by_hand="Choose Event Log from the SSHadow menu.",
        expect=expect,
    )


def create_connection(g: Guide) -> None:
    g.section(
        "Create a connection",
        "From the menu's onboarding to a working connection.",
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
        checks=[g.watching("Finder shows the mounted folder", "")],
    )


def mac_changes(g: Guide) -> None:
    g.section(
        "Changes on the Mac",
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
        "Changes on the server",
        "Folders open in Finder are checked every 10 seconds. The Event Log "
        "shows a row for each change, then a summary.",
    )
    g.act(
        "Open docs in Finder",
        run='open "$L/docs"',
        by_hand="Open docs in the mounted Finder window.",
        expect=["A Finder window on docs, showing b.txt. Keep it open."],
        checks=[g.watching("Finder shows docs", "docs")],
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


def remote_checks(g: Guide) -> None:
    g.section(
        "Checking for remote changes",
        "Sync settings apply right away, without reconnecting. Checking manually "
        "stops all automatic checks, but an ignore file edit still triggers one. "
        "When the Mac creates, edits or deletes a file the server changed "
        "unseen, the Mac's change wins and the server's copy moves to the Trash.",
    )
    manual = L / "docs/manual.txt"
    temp = L / "docs/remote.tmp"
    g.act(
        "Check manually",
        do=lambda: g.app.send("settings", check_every="manual"),
        doing="set Check for Remote Changes to Manually",
        by_hand="In Settings → General, set Check for Remote Changes to Manually.",
        expect=[
            (
                "General's Sync footer says changes appear when you choose Check "
                "for Remote Changes in the menu bar."
            ),
            "In Advanced, the Sync section is greyed out and says why.",
        ],
        checks=[g.logged("Stopped checking", msg(r"^Poll updated: manual$"))],
    )
    g.act(
        "Change the server while checking manually",
        run='echo manual > "$R/docs/manual.txt"\necho temp > "$R/docs/remote.tmp"',
        expect=[
            (
                "Neither file appears in Finder for the next 15 seconds, though "
                "docs is open."
            )
        ],
        checks=[
            until("They're on the server", exists(R / "docs/remote.tmp")),
            stays("They stay out of Finder", missing(manual), 15),
        ],
    )
    g.act(
        "Check for remote changes",
        do=lambda: g.app.send("poll", name=NAME),
        doing="check the server, as Check for Remote Changes does",
        by_hand="Right-click the connection and choose Check for Remote Changes.",
        expect=[
            "manual.txt and remote.tmp appear in Finder with cloud icons.",
            "Event Log: NOTICE Detected 2 change(s) on server.",
        ],
        checks=[
            until("manual.txt appeared", exists(manual)),
            until("remote.tmp appeared", exists(temp)),
        ],
    )
    g.act(
        "Create a file the server already has",
        run='echo server > "$R/docs/clash.txt"\necho mac > "$L/docs/clash.txt"',
        expect=[
            "clash.txt shows up in Finder once, with no clash 2.txt.",
            (
                'Event Log: Move conflicting "docs/clash.txt" to '
                '".sshadow/trash/clash.txt" and Upload "docs/clash.txt" with its size.'
            ),
            "The Finder Trash has a clash.txt containing server.",
        ],
        checks=[
            until(
                "The server has the Mac's clash.txt",
                contains(R / "docs/clash.txt", b"mac\n"),
            ),
            until(
                "The server's clash.txt is in its trash",
                contains(R / ".sshadow/trash/clash.txt", b"server\n"),
            ),
        ],
    )
    g.act(
        "Edit clash.txt on both sides",
        run=(
            'echo "server edit" > "$R/docs/clash.txt"\n'
            'echo "mac edit" > "$L/docs/clash.txt"'
        ),
        expect=[
            "clash.txt in Finder keeps mac edit.",
            (
                'Event Log: Move conflicting "docs/clash.txt" to ".sshadow/trash/'
                'clash.txt" with the time added to the name, and Upload '
                '"docs/clash.txt".'
            ),
            "The Finder Trash has a second clash.txt, named with the time.",
        ],
        checks=[
            until(
                "The server has the Mac's edit",
                contains(R / "docs/clash.txt", b"mac edit\n"),
            ),
            until("The server's edit is in its trash", in_trash(b"server edit\n")),
        ],
    )
    g.act(
        "Delete clash.txt after the server edits it",
        run='echo "server again" > "$R/docs/clash.txt"\nrm "$L/docs/clash.txt"',
        expect=[
            "clash.txt is gone from Finder.",
            (
                'Event Log: Move conflicting "docs/clash.txt" to ".sshadow/trash/'
                '…", not Remove file.'
            ),
            "The Finder Trash has a third clash.txt.",
        ],
        checks=[
            until("clash.txt is gone from the server", missing(R / "docs/clash.txt")),
            until("The server's edit is in its trash", in_trash(b"server again\n")),
        ],
    )
    g.act(
        "Ignore .tmp files while checking manually",
        run="echo '*.tmp' > \"$L/docs/.sshadowignore\"",
        expect=[
            "Within a few seconds, remote.tmp disappears from Finder.",
            (
                'Event Log: Ignore rules changed in "docs", then Hide ignored '
                '"docs/remote.tmp" with the rule in the detail.'
            ),
        ],
        checks=[until("remote.tmp disappeared", missing(temp))],
    )
    g.act(
        "Check automatically again",
        do=lambda: g.app.send("settings", check_every="default"),
        doing="set Check for Remote Changes back to its default",
        by_hand=("Set Check for Remote Changes back to Every 5 minutes (Default)."),
        checks=[g.logged("Started checking", msg(r"^Poll updated: PollSettings\("))],
    )
    auto = L / "docs/auto.txt"
    g.act(
        "Change the server again",
        run='echo auto > "$R/docs/auto.txt"',
        expect=["Within 10 seconds, auto.txt appears in Finder."],
        checks=[until("auto.txt appeared", exists(auto))],
    )


def ignore_files(g: Guide) -> None:
    g.section(
        "Ignore files",
        "Changing which files hold ignore rules applies right away. General sets "
        "the default, and a connection can customize its own.",
    )
    old = L / "docs/old.bak"
    g.act(
        "Add a .gitignore on the server",
        run=(
            'printf \'*.bak\\n\' > "$R/docs/.gitignore"\necho old > "$R/docs/old.bak"'
        ),
        expect=[
            (
                "Within 10 seconds, .gitignore and old.bak appear in Finder, since "
                ".gitignore isn't an ignore file yet."
            )
        ],
        checks=[until("old.bak appeared", exists(old))],
    )
    g.act(
        "Read .gitignore files for every connection",
        do=lambda: g.app.send(
            "settings", ignore_filenames=[".sshadowignore", ".gitignore"]
        ),
        doing="add .gitignore to the default ignore files",
        by_hand=(
            "In Settings → General, turn on Customize Ignore Files and add "
            ".gitignore below .sshadowignore."
        ),
        expect=[
            "Within a few seconds, old.bak disappears from Finder.",
            "Event Log: Ignore files changed, with .sshadowignore, .gitignore.",
        ],
        checks=[
            g.logged(
                "Ignore files changed", msg(r"^Ignore files changed: .*gitignore")
            ),
            until("old.bak disappeared", missing(old)),
        ],
    )
    g.act(
        "Customize the connection's ignore files",
        by_hand=(
            f"In Connections, select {NAME} and turn on Customize Ignore Files. "
            "Remove .gitignore from its list, then turn Customize Ignore Files "
            "off again."
        ),
        expect=[
            "Turning it on starts the list from General's: .sshadowignore, .gitignore.",
            "Removing .gitignore brings old.bak back to Finder within a few seconds.",
            "Turning it off hides old.bak again.",
        ],
        checks=[
            until("old.bak came back", exists(old)),
            until("old.bak is hidden again", missing(old)),
        ],
    )
    g.act(
        "Restore the default ignore files",
        do=lambda: g.app.send("settings", ignore_filenames="default"),
        doing="restore the default ignore files",
        by_hand="In General, turn off Customize Ignore Files.",
        expect=["old.bak comes back to Finder within a few seconds."],
        checks=[until("old.bak came back", exists(old))],
    )


def transfers(g: Guide) -> None:
    g.section(
        "Transfers, pause and resume",
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
        "Server outage",
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
        checks=[until("offline.txt is on the Mac", exists(L / "docs/offline.txt"))],
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
            until(
                "offline.txt uploaded", contains(R / "docs/offline.txt", b"offline\n")
            ),
        ],
    )


def failed_connection(g: Guide) -> None:
    g.section(
        "Failed connection and Clear Status",
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


def host_key_change(g: Guide) -> None:
    g.section(
        "Host key change",
        "The proxy switches to a second SSH server with its own host key, as if "
        "someone were intercepting the connection. SSHadow refuses it before "
        "signing in, and connects only once you trust the new key.",
    )
    fingerprint = g.impostor.fingerprint
    before = g.impostor.connections()

    def switch() -> None:
        g.proxy.redirect(("127.0.0.1", IMPOSTOR_PORT))
        g.app.send("poll", name=NAME)

    g.act(
        "Switch to a server with a different host key",
        do=switch,
        doing=(
            "send the connection to the second server, then check for remote "
            "changes so SSHadow notices right away"
        ),
        expect=[
            (
                f"Event Log: WARNING Lost connection to {NAME}, then ERROR "
                f"Reconnection to {NAME} failed, with the detail Host key "
                f"changed; the server now presents {fingerprint}. Nothing after it."
            ),
            (
                "Settings' Status row shows Host key changed in red, with Trust "
                "New Key… and Clear buttons and no Reconnecting countdown."
            ),
            "The menu row shows an error icon.",
        ],
        checks=[
            g.logged("Refused the new host key", host_key_refused(NAME)),
            Check(
                "It didn't sign in or retry",
                lambda _: refused_once(g.impostor, before),
            ),
        ],
    )
    g.act(
        "Look at the new key, then cancel",
        by_hand=(
            "In Settings, click Trust New Key…. Check that the fingerprint is "
            f"{fingerprint}, then click Cancel."
        ),
        expect=["The Status row still shows Host key changed."],
    )
    g.act(
        "Trust the new key",
        do=lambda: g.app.send("trust-host-key", name=NAME),
        doing="trust the new key, as Trust and Reconnect does",
        by_hand="Click Trust New Key… again, then Trust and Reconnect.",
        expect=[
            "Settings' Status row shows Connected.",
            (
                f"Event Log: NOTICE Trusted host key for {NAME}, with {fingerprint} "
                f"for localhost:{PROXY_PORT}, replacing the old key's fingerprint, "
                f"in the detail. Then Connecting to {NAME} and Connected to {NAME}."
            ),
        ],
        checks=[
            g.logged(
                "Trusted the new key",
                msg(
                    rf"^Trusted host key for localhost:{PROXY_PORT}: "
                    rf"{re.escape(fingerprint)}$"
                ),
            ),
            g.logged("Connected", connected(NAME)),
        ],
    )

    def reconnect() -> None:
        g.app.send("pause", name=NAME)
        g.logs.expect(paused(NAME))
        g.app.send("enable", name=NAME)

    g.act(
        "Reconnect with the trusted key",
        do=reconnect,
        doing="pause and resume the connection",
        by_hand="Click Pause in Settings, then Reconnect.",
        expect=["Connected again, without asking about the host key."],
        checks=[g.logged("Connected", connected(NAME))],
    )


def relaunch(g: Guide) -> None:
    g.section(
        "Quit and relaunch",
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
        checks=[
            until("while-quit.txt is on the server", exists(R / "docs/while-quit.txt"))
        ],
    )
    g.act(
        "Relaunch SSHadow",
        do=lambda: launch(g.app, g.logs, g.key),
        doing="launch SSHadow",
        expect=["The menu bar icon comes back."],
        checks=[g.logged("Connected", connected(NAME), timeout=60)],
    )
    open_event_log(
        g,
        "Open the Event Log",
        [f"Connecting to {NAME}, then Connected to {NAME}."],
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


def connection_menu(g: Guide) -> None:
    g.section(
        "SSHadow menu",
        "The connection's right-click menu.",
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
    g.act(
        "Edit the connection",
        by_hand=(
            "Choose Connections & Settings… and click General in the sidebar. "
            "Then right-click the connection in the SSHadow menu and choose "
            "Edit Connection…."
        ),
        expect=[f"Settings switches to Connections with {NAME} selected."],
    )


def settings_window(g: Guide) -> None:
    g.section(
        "Settings window",
        "The sidebar has Connections, General and Advanced. Open at Login "
        "registers the copy of SSHadow you're testing as a login item, then "
        "removes it again.",
    )
    g.act(
        "Open General",
        by_hand=(
            "Choose Connections & Settings… from the SSHadow menu, then click "
            "General in the sidebar."
        ),
        expect=[
            "The sidebar lists Connections, General and Advanced, in that order.",
            (
                "General has Open at Login, Sync and Ignore Files, and no note "
                "about changes applying when a connection starts."
            ),
        ],
    )
    g.act(
        "Try an invalid ignore file name",
        by_hand=(
            "In General, turn on Customize Ignore Files and add an ignore file "
            f"named dir/x. Then select {NAME} in Connections. Afterwards, turn "
            "Customize Ignore Files off again."
        ),
        expect=[
            "General says Ignore file names can't be empty or contain slashes. in red.",
            f"{NAME}'s Status row shows the same message.",
        ],
    )
    g.act(
        "Turn on Open at Login",
        by_hand="In General, turn on Open at Login.",
        expect=["System Settings → General → Login Items lists SSHadow."],
        checks=[g.logged("Turned on", msg(r"^Open at login enabled$"))],
    )
    g.act(
        "Turn it off",
        by_hand="Turn off Open at Login.",
        expect=["SSHadow is gone from Login Items."],
        checks=[g.logged("Turned off", msg(r"^Open at login disabled$"))],
    )
    g.act(
        "Look at Advanced",
        by_hand="Click Advanced in the sidebar.",
        expect=[
            "Every picker shows its (Default) choice.",
            (
                "Only the Connection section says changes apply the next time a "
                "connection starts."
            ),
        ],
    )


def event_log(g: Guide) -> None:
    g.section("Event Log", "Search, filters, copying and clearing.")
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
    copied = g.act(
        "Copy every entry",
        by_hand="Click an entry, then press ⌘A and ⌘C.",
        checks=[Check("Copied the entries", copied_entries)],
        confirm=True,
    )
    if copied:
        for line in pasted().splitlines()[:3]:
            indented(f"[dim]{escape(line)}", 4)
    g.act("Close the Event Log", by_hand="Close the Event Log window.")
    open_event_log(g, "Reopen the Event Log", ["The filter shows everything again."])
    g.act(
        "Clear the Event Log",
        by_hand="Click Clear.",
        expect=["The window shows No Events."],
    )


def disable(g: Guide) -> None:
    g.section("Disable", "Disabling removes the mounted folder, not the files.")
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
                    "docs/.gitignore": File(b"*.bak\n"),
                    "docs/.sshadowignore": File(b"*.tmp\n"),
                    "docs/auto.txt": File(b"auto\n"),
                    "docs/manual.txt": File(b"manual\n"),
                    "docs/offline.txt": File(b"offline\n"),
                    "docs/old.bak": File(b"old\n"),
                    "docs/remote.tmp": File(b"temp\n"),
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
    console.print()
    console.rule("[bold]Done", align="left")
    if g.failures:
        console.print(f"[red]{len(g.failures)} check(s) failed:")
        for failure in g.failures:
            bullet(failure)
    else:
        console.print("[green]Every check passed.")
    delete = f"Delete {NAME}"
    if menu([f"Keep {NAME}", delete], question="Keep the connection?") == delete:
        g.app.send("delete", name=NAME)
        g.verify(g.logged("Deleted", msg(rf"^Profile deleted: .*{named(NAME)}")), 30)


def main() -> None:
    parts: list[tuple[str, list[Callable[[Guide], None]]]] = [
        ("Setup", [create_connection]),
        (
            "Sync",
            [mac_changes, server_changes, remote_checks, ignore_files, transfers],
        ),
        ("Connection", [outage, failed_connection, host_key_change, relaunch]),
        ("Interface", [connection_menu, settings_window, event_log]),
        ("Teardown", [disable]),
    ]
    g = setup()
    try:
        for title, sections in parts:
            g.part(title)
            for section in sections:
                section(g)
        finish(g)
    except KeyboardInterrupt:
        console.print(f"\nStopped. Rerun to start over; it deletes {NAME} first.")
    finally:
        if g.app.started() is not None:
            reset_settings(g.app, g.logs)
        g.proxy.close()
        g.impostor.close()
        g.logs.close()


if __name__ == "__main__":
    main()
