#!/usr/bin/env python3
"""receiver.py - minimal self-hosted receiver for the AWACS endpoint contract.

Standard library only. One process, one data directory, any number of device ids.

    python3 receiver.py                          # 0.0.0.0:8080, data in ./data
    python3 receiver.py --port 8199 --data /srv/awacs-data

The device (awacs.sh) posts to  <SITE_URL>/<DEVICE_ID>/<SITE_API> (default receiver.php). This server
answers that path for every device id and keeps each device's files apart:

    POST file=log/log.txt&data=<line>   append <line> + "\\n" to data/<id>/log/log.txt;
                                        the file is kept under 256 KB (oldest lines go)
    POST file=tmp/wifi_scan.tmp&data=<list> overwrite data/<id>/tmp/wifi_scan.tmp (the networks the radio heard)
    POST file=tmp/wifi.tmp&data=<cell>  overwrite data/<id>/tmp/wifi.tmp atomically
    POST file=tmp/wifi_state.tmp&data=<answer> overwrite data/<id>/tmp/wifi_state.tmp (the
                                        device's answer to a site command: scan, switch, join)
    POST file=wifi_key&data=<64 hex>    register the device key that opens a password typed
         [&proof=<hex>]                 on a site: data/<id>/private/wifi.key, mode 0600. The
                                        first key is taken; the same key again answers 200; a
                                        different key needs proof = HMAC-SHA256(old key bytes,
                                        new key hex) or gets 403 "Error: proof required";
                                        anything but 64 lowercase hex is 400 "Error: bad key"
    POST without a `file` field         400 "Error: no operation" - awacs.sh uses this
                                        exact reply as its "site reachable" check and as
                                        the target of its upload-speed probe (a raw body)
    POST file=<anything else>           403 "Error: forbidden file"
    other paths                         404; GET on any path 400

There is NO authentication: anyone who can reach the port can append to the log, overwrite
the WiFi cell of any device id and, before the device does, register a key for it. Run it
behind a firewall, a VPN, or a reverse proxy that adds auth. SECURITY.md in the repository
says what that means in practice.
"""

import argparse
import hmac
import os
import re
import sys
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

LOG_CAP = 256 * 1024        # bytes kept in log/log.txt; trimmed once the file passes 2x
MAX_BODY = 8 * 1024 * 1024  # an upload probe is PROBE_KB kilobytes (200 KB by default)
MAX_DATA = 64 * 1024        # one log line or one WiFi cell
ALLOWED = {
    "log/log.txt": "append",
    "tmp/wifi.tmp": "overwrite",
    "tmp/wifi_scan.tmp": "overwrite",
    "tmp/wifi_state.tmp": "overwrite",
}
KEY_FILE = os.path.join("private", "wifi.key")   # the device key: never a name the device can write as a file
KEY_RE = re.compile(r"^[0-9a-f]{64}$")
DEVICE_PATH = re.compile(r"^/([A-Za-z0-9_-]{1,32})/receiver\.php$")
WRITE_LOCK = threading.Lock()  # one process serves everything, so one lock is enough


def write_overwrite(path: str, data: str) -> None:
    """Write `data` to `path` through a temp file in the same directory, then rename."""
    directory = os.path.dirname(path)
    fd, tmp = tempfile.mkstemp(prefix=".wifi.", dir=directory)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as handle:
            handle.write(data)
        os.replace(tmp, path)
    except OSError:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def register_key(path: str, key: str, proof: str):
    """Store the device key; return (code, text). The first key is taken, the same key again
    is a 200 with no write, a different key needs proof = HMAC-SHA256(old key raw bytes,
    new key hex as ASCII) so an unauthenticated POST cannot swap it."""
    if not KEY_RE.match(key):
        return 400, "Error: bad key\n"
    old = ""
    if os.path.isfile(path):
        with open(path, "r", encoding="ascii", errors="replace") as handle:
            old = handle.read().strip()
    if old:
        if hmac.compare_digest(old, key):
            return 200, "OK\n"
        want = hmac.new(bytes.fromhex(old), key.encode("ascii"), "sha256").hexdigest()
        if not re.match(r"^[0-9a-fA-F]{64}$", proof) or not hmac.compare_digest(want, proof.lower()):
            return 403, "Error: proof required\n"
    os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".key.", dir=os.path.dirname(path))   # mkstemp: 0600
    try:
        with os.fdopen(fd, "w", encoding="ascii", newline="") as handle:
            handle.write(key + "\n")
        os.replace(tmp, path)
    except OSError:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
    return 200, "OK\n"


def write_append(path: str, line: str) -> None:
    """Append one line, then keep the file under the cap (the newest tail survives)."""
    with open(path, "ab") as handle:
        handle.write(line.encode("utf-8"))
    if os.path.getsize(path) <= LOG_CAP * 2:
        return
    with open(path, "rb") as handle:
        handle.seek(-LOG_CAP, os.SEEK_END)
        tail = handle.read()
    newline = tail.find(b"\n")
    if newline != -1:
        tail = tail[newline + 1:]  # drop the partial first line
    with open(path, "r+b") as handle:  # in place: works while a reader has it open
        handle.truncate(0)
        handle.write(tail)


class Handler(BaseHTTPRequestHandler):
    """One request = one whitelisted file operation, or a contract error."""

    server_version = "awacs-receiver/1.0"
    sys_version = ""
    protocol_version = "HTTP/1.1"

    def _reply(self, code: int, text: str) -> None:
        body = text.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "text/plain; charset=UTF-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(body)

    def _read_body(self):
        """Return the request body, or None when it is too large (connection then closes)."""
        try:
            length = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            length = -1
        if length < 0 or length > MAX_BODY:
            self.close_connection = True
            return None
        return self.rfile.read(length) if length else b""

    def do_GET(self) -> None:  # noqa: N802 (http.server naming)
        self._reply(400, "Error: no operation\n")

    def do_POST(self) -> None:  # noqa: N802 (http.server naming)
        body = self._read_body()
        if body is None:
            self._reply(413, "Error: too large\n")
            return
        match = DEVICE_PATH.match(urlsplit(self.path).path)
        if not match:
            self._reply(404, "Error: not found\n")
            return
        device = match.group(1)

        # Only a form body can carry an operation. The upload probe arrives with the same
        # content type but a raw body: it parses to no `file` field and gets the 400.
        form = {}
        ctype = self.headers.get("Content-Type", "").split(";")[0].strip().lower()
        if ctype == "application/x-www-form-urlencoded":
            form = parse_qs(body.decode("utf-8", "replace"), keep_blank_values=True)
        if "file" not in form:
            self._reply(400, "Error: no operation\n")
            return
        rel = form["file"][0]
        data = form.get("data", [""])[0]
        if len(data.encode("utf-8")) > MAX_DATA:
            self._reply(400, "Error: too large\n")
            return
        if rel == "wifi_key":   # a registration, not a file write: before the whitelist
            try:
                with WRITE_LOCK:
                    code, text = register_key(os.path.join(self.server.data_root, device, KEY_FILE),
                                              data, form.get("proof", [""])[0])
            except OSError as exc:
                self.log_error("key write failed for %s: %s", device, exc)
                code, text = 500, "Error: write failed\n"
            if code == 403:
                self.log_error("key registration refused for %s (proof missing or wrong)", device)
            self._reply(code, text)
            return
        mode = ALLOWED.get(rel)
        if mode is None:  # exact-path whitelist: traversal is moot, anything else is 403
            self._reply(403, "Error: forbidden file\n")
            return

        full = os.path.join(self.server.data_root, device, *rel.split("/"))
        try:
            with WRITE_LOCK:
                os.makedirs(os.path.dirname(full), exist_ok=True)
                if mode == "append":
                    write_append(full, data + "\n")
                else:
                    write_overwrite(full, data)
        except OSError as exc:
            self.log_error("write failed %s: %s", full, exc)
            self._reply(500, "Error: write failed\n")
            return
        self._reply(200, "OK\n")

    def log_message(self, fmt, *args) -> None:
        if getattr(self.server, "quiet", False):
            return
        super().log_message(fmt, *args)


def main() -> int:
    here = os.path.dirname(os.path.abspath(__file__))
    parser = argparse.ArgumentParser(description="AWACS receiver (stdlib only)")
    parser.add_argument("--host", default="0.0.0.0", help="bind address (default 0.0.0.0)")
    parser.add_argument("--port", type=int, default=8080, help="TCP port (default 8080)")
    parser.add_argument("--data", default=os.path.join(here, "data"),
                        help="data directory, one sub-directory per device id (default ./data)")
    parser.add_argument("--quiet", action="store_true", help="no per-request log line")
    args = parser.parse_args()

    os.makedirs(args.data, exist_ok=True)
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    server.data_root = os.path.abspath(args.data)
    server.quiet = args.quiet
    print(f"awacs receiver on http://{args.host}:{args.port}/<DEVICE_ID>/receiver.php "
          f"-> {server.data_root}  (no auth; see SECURITY.md)", file=sys.stderr)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
