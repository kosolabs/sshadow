import os
import subprocess
import time
from collections.abc import Sequence
from datetime import datetime
from pathlib import Path
from urllib.parse import urlencode

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


class App:
    def __init__(self, path: Path):
        if not path.is_dir():
            raise FileNotFoundError(f"SSHadow.app not found at {path}")
        self.path = path.resolve()
        self.executable = self.path / "Contents" / "MacOS" / "SSHadow"

    def started(self) -> datetime | None:
        env = os.environ | {"LC_ALL": "C"}
        ps = subprocess.run(
            ["ps", "-axo", "pid=,lstart=,comm="],
            capture_output=True,
            text=True,
            check=True,
            env=env,
        ).stdout
        for line in ps.splitlines():
            # e.g. "38730 Fri Oct  9 15:23:45 2026 /path/to/SSHadow"
            fields = line.split(maxsplit=6)
            if fields[6] == str(self.executable):
                # lstart is in local time.
                return datetime.strptime(
                    " ".join(fields[1:6]), "%a %b %d %H:%M:%S %Y"
                ).astimezone()
        return None

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

    def send(self, command: str, **params: str | int | Path) -> None:
        # Named explicitly so the URL can't go to another installed copy.
        url = f"sshadow://{command}"
        if params:
            url += "?" + urlencode({k: str(v) for k, v in params.items()})
        subprocess.run(["open", "-a", self.path, url], check=True)
