import shutil
import socket
import subprocess
import tempfile
import time
from pathlib import Path

SERVER_DIR = Path(__file__).resolve().parent.parent / "ci_scripts" / "test_server"
SSHD = "/usr/sbin/sshd"
START_TIMEOUT = 5


def fingerprint(public_key: Path) -> str:
    """The SHA256 fingerprint of `public_key`, as ssh-keygen prints it."""
    output = subprocess.run(
        ["ssh-keygen", "-lf", public_key],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    return output.split()[1]


class Impostor:
    """A second SSH server for the same account and files, with its own host key.

    To SSHadow it looks like the test server, except for its host key.
    """

    def __init__(self, port: int):
        self.port = port
        if _listening(port):
            raise RuntimeError(
                f"Port {port} is already in use, probably by an impostor sshd "
                f"left over from an earlier run. Find it with: lsof -nP -iTCP:{port}"
            )
        self._dir = Path(tempfile.mkdtemp(prefix="sshadow-impostor-"))
        self.host_key = self._dir / "host_key_ed25519"
        self.log = self._dir / "sshd.log"
        subprocess.run(
            ["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-C", "impostor"]
            + ["-f", self.host_key],
            check=True,
        )
        self._process = subprocess.Popen(
            [SSHD, "-D", "-p", str(port), "-f", SERVER_DIR / "sshd_config"]
            + ["-E", self.log, "-h", self.host_key, "-o", "PidFile none"]
            + ["-o", f"AuthorizedKeysFile {SERVER_DIR / 'authorized_keys'}"],
        )
        self._wait_until_listening()

    @property
    def fingerprint(self) -> str:
        return fingerprint(self.host_key.with_suffix(".pub"))

    def connections(self) -> int:
        return self._log_lines().count("Connection from ")

    def authenticated(self) -> bool:
        return "Accepted " in self._log_lines()

    def _log_lines(self) -> str:
        return self.log.read_text() if self.log.exists() else ""

    def _wait_until_listening(self) -> None:
        deadline = time.monotonic() + START_TIMEOUT
        while time.monotonic() < deadline:
            if self._process.poll() is not None:
                raise RuntimeError(f"sshd exited: {self._log_lines()}")
            if _listening(self.port):
                return
            time.sleep(0.05)
        raise TimeoutError(f"sshd isn't listening on port {self.port}")

    def close(self) -> None:
        self._process.terminate()
        self._process.wait(timeout=10)
        shutil.rmtree(self._dir, ignore_errors=True)


def _listening(port: int) -> bool:
    try:
        socket.create_connection(("127.0.0.1", port), timeout=1).close()
        return True
    except OSError:
        return False
