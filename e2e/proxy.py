import select
import socket
import struct
import threading
import time
from enum import Enum


class Mode(Enum):
    FORWARD = "forward"
    BLACKHOLE = "blackhole"
    REFUSE = "refuse"


class Proxy:
    """A TCP proxy in front of the test server, for simulating network failures."""

    def __init__(self, upstream: tuple[str, int], host: str = "127.0.0.1"):
        self.host = host
        self.upstream = upstream
        self.mode = Mode.FORWARD
        # Bytes per second in each direction, or None for unlimited.
        self.rate: float | None = None
        self._lock = threading.Lock()
        self._conns: set[socket.socket] = set()
        self._closed = False
        self._listener = self._listen(0)
        self.port: int = self._listener.getsockname()[1]
        threading.Thread(target=self._accept_loop, daemon=True).start()

    def _listen(self, port: int) -> socket.socket:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind((self.host, port))
        s.listen(64)
        return s

    def _accept_loop(self) -> None:
        while not self._closed:
            with self._lock:
                listener = self._listener
                mode = self.mode
            if listener is None or mode is Mode.BLACKHOLE:
                time.sleep(0.05)
                continue
            try:
                readable, _, _ = select.select([listener], [], [], 0.05)
                if not readable:
                    continue
                client, _ = listener.accept()
            except (OSError, ValueError):
                continue
            try:
                server = socket.create_connection(self.upstream, timeout=5)
            except OSError:
                client.close()
                continue
            server.settimeout(None)
            with self._lock:
                self._conns |= {client, server}
            threading.Thread(
                target=self._pump, args=(client, server), daemon=True
            ).start()

    def _pump(self, a: socket.socket, b: socket.socket) -> None:
        peers = {a: b, b: a}
        try:
            while not self._closed:
                if self.mode is Mode.BLACKHOLE:
                    time.sleep(0.05)
                    continue
                readable, _, _ = select.select([a, b], [], [], 0.05)
                for src in readable:
                    rate = self.rate
                    data = src.recv(65536 if rate is None else max(1, int(rate / 20)))
                    if not data:
                        return
                    peers[src].sendall(data)
                    if rate is not None:
                        time.sleep(len(data) / rate)
        except (OSError, ValueError):
            pass
        finally:
            self._close(a)
            self._close(b)

    def _close(self, s: socket.socket) -> None:
        with self._lock:
            self._conns.discard(s)
        try:
            s.close()
        except OSError:
            pass

    def drop(self) -> None:
        """Reset every open connection, as if the network dropped."""
        with self._lock:
            conns = list(self._conns)
        for s in conns:
            try:
                # Close with a reset instead of a FIN.
                s.setsockopt(
                    socket.SOL_SOCKET, socket.SO_LINGER, struct.pack("ii", 1, 0)
                )
            except OSError:
                pass
            self._close(s)

    def refuse(self) -> None:
        """Drop every connection and refuse new ones."""
        with self._lock:
            self.mode = Mode.REFUSE
            listener, self._listener = self._listener, None
        if listener is not None:
            listener.close()
        self.drop()

    def blackhole(self) -> None:
        """Stop relaying, on open connections and new ones, without closing them."""
        with self._lock:
            self.mode = Mode.BLACKHOLE

    def restore(self) -> None:
        with self._lock:
            if self._listener is None:
                self._listener = self._listen(self.port)
            self.mode = Mode.FORWARD

    def close(self) -> None:
        self._closed = True
        self.refuse()
