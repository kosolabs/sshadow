import json
import os
import signal
import subprocess
import time
from collections.abc import Sequence
from datetime import datetime
from pathlib import Path

from Foundation import NSDistributedNotificationCenter  # pyright: ignore[reportAttributeAccessIssue]

from logwatch import LogWatcher, msg

REPO = Path(__file__).parent.parent
ENABLE_TEST_COMMANDS = "-enableTestCommands"
COMMAND_NOTIFICATION = "com.kosolabs.SSHadow.command"


def post_distributed_notification(name: str, obj: str) -> None:
    center = NSDistributedNotificationCenter.defaultCenter()
    center.postNotificationName_object_userInfo_deliverImmediately_(
        name, obj, None, True
    )


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
            ["open", "-a", self.path, *files, "--args", ENABLE_TEST_COMMANDS],
            check=True,
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
        if self.started() is None:
            raise RuntimeError(f"{self.path} isn't running")
        payload = {"command": command} | {k: str(v) for k, v in params.items()}
        post_distributed_notification(COMMAND_NOTIFICATION, json.dumps(payload))


def cloud_storage(profile: str) -> Path:
    return Path.home() / "Library" / "CloudStorage" / f"SSHadow-{profile}"


def enable(app: App, logs: LogWatcher, profile: str) -> Path:
    app.send("enable", name=profile)
    logs.expect(msg(rf"Profile enabled: .*\bname: {profile}\b"), timeout=60)
    root = cloud_storage(profile)
    deadline = time.monotonic() + 10
    while not root.is_dir():
        assert time.monotonic() < deadline, f"{root} never appeared"
        logs.check()
        time.sleep(0.1)
    return root
