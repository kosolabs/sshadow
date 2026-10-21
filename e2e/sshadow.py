# pyright: reportAttributeAccessIssue=false
import getpass
import json
import os
import re
import signal
import subprocess
import time
from collections.abc import Sequence
from datetime import datetime
from pathlib import Path

from Foundation import (
    NSURL,
    NSData,
    NSDistributedNotificationCenter,
    NSFileManager,
    NSItemReplacementDirectory,
    NSUserDomainMask,
)

from logwatch import APP, LogWatcher, Matcher, msg
from tree import File, Tree, make_tree, wait_for_tree

SF_DATALESS = 0x40000000

REPO = Path(__file__).parent.parent
ENABLE_TEST_COMMANDS = "-enableTestCommands"
COMMAND_NOTIFICATION = "com.kosolabs.SSHadow.command"
PROFILE_NAME = "Test-E2E"
REMOTE_ROOT = Path("/tmp/sshadow")
SERVER_PORT = 2248


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

    def send(self, command: str, **params: str | int | Path | Sequence[str]) -> None:
        if self.started() is None:
            raise RuntimeError(f"{self.path} isn't running")
        post_distributed_notification(
            COMMAND_NOTIFICATION,
            json.dumps({"command": command, **params}, default=str),
        )


def cloud_storage(profile: str) -> Path:
    return Path.home() / "Library" / "CloudStorage" / f"SSHadow-{profile}"


def named(name: str, field: str = "name") -> str:
    """A regex for a `name` field in a logged description, matching it exactly."""
    return rf"\b{field}: {re.escape(name)}(?=[,)])"


def brokered(profile: str) -> Matcher:
    return msg(rf"^XPC brokered: .*{named(profile, 'displayName')}", subsystem=APP)


def wait_for_removal(path: Path, timeout: float = 30) -> None:
    """Wait for File Provider to finish removing a deleted domain's root.

    Until it does, adding a domain with the same name fails.
    """
    deadline = time.monotonic() + timeout
    while path.exists():
        if time.monotonic() >= deadline:
            raise TimeoutError(f"{path} still exists {timeout}s after deletion")
        time.sleep(0.5)


def round_trip(
    app: App, logs: LogWatcher, profile: str, local: Path, remote: Path, tree: Tree
) -> Tree:
    """Sync a new file each way, which only works if the extension can reach the app.

    The files' contents name `profile`, to catch syncing through the wrong domain.
    """
    n = len(tree)
    upload: Tree = {f"upload-{n}.txt": File(f"upload {n} from {profile}\n".encode())}
    make_tree(local, upload)
    tree = tree | upload
    wait_for_tree(remote, tree, on_poll=logs.check)

    download: Tree = {
        f"download-{n}.txt": File(f"download {n} from {profile}\n".encode())
    }
    make_tree(remote, download)
    tree = tree | download
    app.send("poll", name=profile)
    wait_for_tree(local, tree, on_poll=logs.check)
    return tree


def create_profile(
    app: App,
    logs: LogWatcher,
    name: str,
    key: Path,
    *,
    path: Path = REMOTE_ROOT,
    host: str = "localhost",
    port: int = SERVER_PORT,
    ignore_filenames: Sequence[str] | None = None,
) -> None:
    path.mkdir(parents=True, exist_ok=True)
    params: dict[str, str | int | Path | Sequence[str]] = {}
    if ignore_filenames is not None:
        params["ignore_filenames"] = ignore_filenames
    app.send(
        "create",
        name=name,
        host=host,
        port=port,
        user=getpass.getuser(),
        path=path,
        key=key,
        **params,
    )
    logs.expect(msg(rf"Profile created: .*{named(name)}"))


class Profiles:
    """Creates profiles for the test server, and deletes them afterwards."""

    def __init__(self, app: App, logs: LogWatcher, key: Path):
        self.app = app
        self.logs = logs
        self.key = key
        self.names: list[str] = []

    def create(
        self,
        name: str,
        *,
        path: Path = REMOTE_ROOT,
        host: str = "localhost",
        port: int = SERVER_PORT,
        ignore_filenames: Sequence[str] | None = None,
    ) -> str:
        create_profile(
            self.app,
            self.logs,
            name,
            self.key,
            path=path,
            host=host,
            port=port,
            ignore_filenames=ignore_filenames,
        )
        if name not in self.names:
            self.names.append(name)
        return name

    def delete(self, name: str, timeout: float = 30) -> None:
        self.app.send("delete", name=name)
        self.logs.expect(msg(rf"Profile deleted: .*{named(name)}"), timeout=timeout)
        self.names.remove(name)
        wait_for_removal(cloud_storage(name))

    def delete_all(self) -> None:
        for name in list(self.names):
            self.delete(name)


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


def evict(path: Path) -> None:
    """Remove a File Provider item's local contents, so the next read downloads it."""
    ok, error = NSFileManager.defaultManager().evictUbiquitousItemAtURL_error_(
        NSURL.fileURLWithPath_(str(path)), None
    )
    if not ok:
        raise OSError(f"can't evict {path}: {error}")


def dataless(path: Path) -> bool:
    """Whether a File Provider item's contents haven't been downloaded."""
    return bool(os.lstat(path).st_flags & SF_DATALESS)


def trash(path: Path) -> Path:
    """Move `path` to the Trash, as Finder does, and return where it went."""
    ok, url, error = (
        NSFileManager.defaultManager().trashItemAtURL_resultingItemURL_error_(
            NSURL.fileURLWithPath_(str(path)), None, None
        )
    )
    if not ok:
        raise OSError(f"can't trash {path}: {error}")
    return Path(url.path())


def replace_item(path: Path, contents: bytes) -> None:
    """Save `contents` over `path` the way NSDocument does, by swapping in a new file."""
    fm = NSFileManager.defaultManager()
    url = NSURL.fileURLWithPath_(str(path))
    tmp_dir, error = fm.URLForDirectory_inDomain_appropriateForURL_create_error_(
        NSItemReplacementDirectory, NSUserDomainMask, url, True, None
    )
    if tmp_dir is None:
        raise OSError(f"can't make a replacement directory for {path}: {error}")
    tmp = tmp_dir.URLByAppendingPathComponent_(path.name)
    ok, error = NSData.dataWithBytes_length_(
        contents, len(contents)
    ).writeToURL_options_error_(tmp, 0, None)
    if not ok:
        raise OSError(f"can't write {tmp.path()}: {error}")
    ok, _, error = (
        fm.replaceItemAtURL_withItemAtURL_backupItemName_options_resultingItemURL_error_(
            url, tmp, None, 0, None, None
        )
    )
    if not ok:
        raise OSError(f"can't replace {path}: {error}")
    fm.removeItemAtURL_error_(tmp_dir, None)


def disable(app: App, logs: LogWatcher, profile: str, timeout: float = 30) -> None:
    app.send("disable", name=profile)
    logs.expect(msg(rf"Profile disabled: .*{named(profile)}"), timeout=timeout)
    wait_for_removal(cloud_storage(profile))


def pause(app: App, logs: LogWatcher, profile: str, timeout: float = 30) -> None:
    app.send("pause", name=profile)
    logs.expect(
        msg(rf"^Supervisor paused: .*{named(profile, 'displayName')}"),
        timeout=timeout,
    )


def connected(profile: str) -> Matcher:
    return msg(rf"^Supervisor connected: .*{named(profile)}")


def uploading(name: str) -> Matcher:
    return msg(rf'^Upload Ref\(path: "{re.escape(name)}"')
