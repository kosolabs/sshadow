import select
import socket
import struct
import subprocess
import threading
import time

RESET_TIMEOUT = 5


class Proxy:
    """A TCP proxy in front of the test server, for simulating network failures."""

    def __init__(
        self, upstream: tuple[str, int], host: str = "127.0.0.1", port: int = 0
    ):
        self.host = host
        self.upstream = upstream
        # Bytes per second in each direction, or None for unlimited.
        self.rate: float | None = None
        self._lock = threading.Lock()
        # Each connection's pump thread, and the event that tells it to reset.
        self._relays: dict[threading.Thread, threading.Event] = {}
        self._closed = False
        self._listener = self._listen(port)
        self.port: int = self._listener.getsockname()[1]
        threading.Thread(target=self._accept_loop, daemon=True).start()

    def _listen(self, port: int) -> socket.socket:
        if ":" in self.host:
            s = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
            # Accept IPv4 too, for hosts like localhost that resolve to both.
            s.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
        else:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind((self.host, port))
        s.listen(64)
        return s

    def _accept_loop(self) -> None:
        while not self._closed:
            with self._lock:
                listener = self._listener
            if listener is None:
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
            client.setblocking(False)
            server.setblocking(False)
            reset = threading.Event()
            pump = threading.Thread(
                target=self._pump, args=(client, server, reset), daemon=True
            )
            with self._lock:
                self._relays[pump] = reset
            pump.start()

    def _pump(self, a: socket.socket, b: socket.socket, reset: threading.Event) -> None:
        """Relay between `a` and `b` until either closes or `reset` is set.

        Only this thread closes `a` and `b`, so neither is closed while in use.
        """
        peers = {a: b, b: a}
        try:
            while not self._closed and not reset.is_set():
                readable, _, _ = select.select([a, b], [], [], 0.05)
                for src in readable:
                    rate = self.rate
                    data = src.recv(65536 if rate is None else max(1, int(rate / 20)))
                    if not data or not self._send(peers[src], data, reset):
                        return
                    if rate is not None:
                        time.sleep(len(data) / rate)
        except (OSError, ValueError):
            pass
        finally:
            if reset.is_set():
                _reset(a)
                _reset(b)
            else:
                a.close()
                b.close()
            with self._lock:
                self._relays.pop(threading.current_thread(), None)

    def _send(self, dst: socket.socket, data: bytes, reset: threading.Event) -> bool:
        """Send all of `data`, unless `reset` is set first while waiting to send."""
        view = memoryview(data)
        while view:
            if self._closed or reset.is_set():
                return False
            _, writable, _ = select.select([], [dst], [], 0.05)
            if writable:
                view = view[dst.send(view) :]
        return True

    def drop(self) -> None:
        """Reset every open connection, as if the network dropped.

        Returns once every reset has been sent.
        """
        with self._lock:
            relays = dict(self._relays)
        for reset in relays.values():
            reset.set()
        deadline = time.monotonic() + RESET_TIMEOUT
        stuck = []
        for pump in relays:
            pump.join(timeout=max(0, deadline - time.monotonic()))
            if pump.is_alive():
                stuck.append(pump)
        _log(f"Proxy reset {len(relays) - len(stuck)} connection(s)")
        if stuck:
            _log(
                f"Proxy couldn't reset {len(stuck)} connection(s) within {RESET_TIMEOUT}s"
            )

    def refuse(self) -> None:
        """Drop every connection and refuse new ones."""
        with self._lock:
            listener, self._listener = self._listener, None
        if listener is not None:
            listener.close()
        self.drop()

    def restore(self) -> None:
        with self._lock:
            if self._listener is None:
                self._listener = self._listen(self.port)

    def close(self) -> None:
        self._closed = True
        self.refuse()


def _reset(s: socket.socket) -> None:
    """Close `s` with a reset instead of a FIN."""
    try:
        s.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack("ii", 1, 0))
    except OSError as e:
        _log(f"Proxy couldn't set SO_LINGER, closing with a FIN: {e}")
    s.close()


def _log(message: str) -> None:
    subprocess.run(["logger", message], check=True)
