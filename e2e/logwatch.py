import json
import queue
import re
import subprocess
import threading
import time
from collections.abc import Callable, Sequence
from typing import Any

Event = dict[str, Any]
Matcher = Callable[[Event], bool]

APP = "com.kosolabs.SSHadow"
EXTENSION = "com.kosolabs.SSHadow.Extension"


def msg(
    pattern: str,
    *,
    category: str | None = None,
    subsystem: str | None = None,
    level: str | None = None,
) -> Matcher:
    """Match events whose eventMessage contains `pattern` (a regex)."""
    rx = re.compile(pattern)

    def match(e: Event) -> bool:
        return (
            (category is None or e.get("category") == category)
            and (subsystem is None or e.get("subsystem") == subsystem)
            and (level is None or e.get("messageType") == level)
            and rx.search(e.get("eventMessage", "")) is not None
        )

    return match


def fault(e: Event) -> bool:
    return e.get("messageType") == "Fault"


def format_event(e: Event) -> str:
    subsystem = e.get("subsystem", "").rsplit(".", 1)[-1]
    return (
        f"{e.get('timestamp', '')[11:26]} {e.get('messageType', ''):<7} "
        f"{subsystem}:{e.get('category', '')} {e.get('eventMessage', '')}"
    )


class LogWatcher:
    def __init__(
        self, predicate: str, *, level: str = "info", startup_timeout: float = 10
    ):
        self.predicate = predicate
        self.seen: list[Event] = []
        self._queue: queue.Queue[Event] = queue.Queue()
        self._ready = threading.Event()
        self._proc = subprocess.Popen(
            [
                "log",
                "stream",
                "--style",
                "ndjson",
                "--level",
                level,
                "--predicate",
                predicate,
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            bufsize=1,
        )
        threading.Thread(target=self._pump, daemon=True).start()
        if not self._ready.wait(startup_timeout):
            self.close()
            raise RuntimeError(f"log stream did not start within {startup_timeout}s")

    def _pump(self) -> None:
        assert self._proc.stdout is not None
        for line in self._proc.stdout:
            try:
                self._queue.put(json.loads(line))
            except json.JSONDecodeError:
                # `log stream` prints a plain-text "Filtering the log data
                # using ..." header once it's live.
                self._ready.set()
        self._ready.set()

    def expect(
        self,
        success: Matcher,
        *,
        fail: Sequence[Matcher] = (fault,),
        timeout: float = 10,
    ) -> Event:
        deadline = time.monotonic() + timeout
        while (remaining := deadline - time.monotonic()) > 0:
            try:
                e = self._queue.get(timeout=remaining)
            except queue.Empty:
                break
            self.seen.append(e)
            if any(f(e) for f in fail):
                raise AssertionError(
                    f"failure event: {format_event(e)}\n\n{self.tail()}"
                )
            if success(e):
                return e
        raise TimeoutError(f"no matching event within {timeout}s\n\n{self.tail()}")

    def drain(self) -> list[Event]:
        """Consume and return all events received so far."""
        events: list[Event] = []
        while True:
            try:
                events.append(self._queue.get_nowait())
            except queue.Empty:
                break
        self.seen.extend(events)
        return events

    def check(self, fail: Sequence[Matcher] = (fault,)) -> None:
        """Consume events received so far, raising AssertionError on any `fail`."""
        for e in self.drain():
            if any(f(e) for f in fail):
                raise AssertionError(
                    f"failure event: {format_event(e)}\n\n{self.tail()}"
                )

    def tail(self, n: int = 30) -> str:
        lines = [format_event(e) for e in self.seen[-n:]]
        return "recent events:\n" + ("\n".join(lines) if lines else "(none)")

    def close(self) -> None:
        self._proc.terminate()
        try:
            self._proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self._proc.kill()
