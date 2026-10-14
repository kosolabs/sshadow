import os
import signal
import subprocess
import time
from collections.abc import Sequence
from datetime import datetime
from pathlib import Path
from urllib.parse import urlencode

from logwatch import LogWatcher, msg

REPO = Path(__file__).parent.parent
ENABLE_URL_COMMANDS = "-enableURLCommands"


def find_app() -> Path:
    if path := os.environ.get("SSHADOW_APP"):
        return Path(path)
    settings = subprocess.run(
        [
            "xcodebuild",
            "-showBuildSettings",
            "-scheme",
            "SSHadow",
            "-configuration",
            "Debug",
        ],
        cwd=REPO,
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    for line in settings.splitlines():
        key, _, value = line.strip().partition(" = ")
        if key == "BUILT_PRODUCTS_DIR":
            return Path(value) / "SSHadow.app"
    raise RuntimeError("BUILT_PRODUCTS_DIR not found in xcodebuild settings")


def find_processes(executable: Path) -> list[tuple[int, datetime]]:
    """The pid and start time of every process running `executable`."""
    env = os.environ | {"LC_ALL": "C"}
    ps = subprocess.run(
        ["ps", "-axo", "pid=,lstart=,comm="],
        capture_output=True,
        text=True,
        check=True,
        env=env,
    ).stdout
    processes: list[tuple[int, datetime]] = []
    for line in ps.splitlines():
        # e.g. "38730 Fri Oct  9 15:23:45 2026 /path/to/SSHadow"
        fields = line.split(maxsplit=6)
        if fields[6] == str(executable):
            # lstart is in local time.
            started = datetime.strptime(
                " ".join(fields[1:6]), "%a %b %d %H:%M:%S %Y"
            ).astimezone()
            processes.append((int(fields[0]), started))
    return processes


def kill(executable: Path, timeout: float) -> None:
    """SIGKILL every process running `executable` and wait for them to exit."""
    pids = {pid for pid, _ in find_processes(executable)}
    if not pids:
        raise RuntimeError(f"{executable.name} isn't running")
    for pid in pids:
        os.kill(pid, signal.SIGKILL)
    deadline = time.monotonic() + timeout
    # Only wait for these pids, since launchd may start the process again.
    while pids & {pid for pid, _ in find_processes(executable)}:
        if time.monotonic() >= deadline:
            raise TimeoutError(f"{executable.name} didn't exit within {timeout}s")
        time.sleep(0.1)


class App:
    def __init__(self, path: Path):
        if not path.is_dir():
            raise FileNotFoundError(f"SSHadow.app not found at {path}")
        self.path = path.resolve()
        self.executable = self.path / "Contents" / "MacOS" / "SSHadow"
        self.extension = (
            self.path / "Contents/PlugIns/Extension.appex/Contents/MacOS/Extension"
        )

    def started(self) -> datetime | None:
        processes = find_processes(self.executable)
        return processes[0][1] if processes else None

    def launch(self, files: Sequence[Path] = ()) -> None:
        if self.started() is not None:
            raise RuntimeError("SSHadow is already running. Quit it and rerun.")
        subprocess.run(
            ["open", "-a", self.path, *files, "--args", ENABLE_URL_COMMANDS], check=True
        )

    def quit(self, timeout: float = 10) -> None:
        self.send("quit")
        deadline = time.monotonic() + timeout
        while self.started() is not None:
            if time.monotonic() >= deadline:
                raise TimeoutError(f"SSHadow didn't quit within {timeout}s")
            time.sleep(0.1)

    def kill(self, timeout: float = 10) -> None:
        kill(self.executable, timeout)

    def kill_extension(self, timeout: float = 10) -> None:
        kill(self.extension, timeout)

    def send(self, command: str, **params: str | int | Path) -> None:
        # Named explicitly so the URL can't go to another installed copy.
        url = f"sshadow://{command}"
        if params:
            url += "?" + urlencode({k: str(v) for k, v in params.items()})
        subprocess.run(["open", "-a", self.path, url], check=True)


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
