"""Refill assets/seed_configs.json from the live API.

The app ships a small sample of the config pool so that a first launch on a
network that blocks the API is not left with an empty list. That sample is not
kept in the repository -- it is a snapshot of other people's servers, it goes
stale within days, and a git history is a permanent, indexed place to put
either. So the repo carries an empty file and this script fills it before a
release build.

Run it from the project root:

    python tool/fetch_seed_configs.py

It writes assets/seed_configs.json in place. If it cannot reach the API the
file is left alone, because an empty bundle degrades gracefully -- SeedConfigs
treats it as "no floor" and the app falls back to the error it would have shown
anyway -- while a half-written one does not.
"""

from __future__ import annotations

import datetime as _dt
import io
import json
import socket
import ssl
import sys

HOST = "vernaservice.ir"

# Cloudflare edges to try when the address DNS returns is blocked.
#
# The API sits behind Cloudflare, which is anycast: any of these serves the
# same site as long as TLS carries the real hostname. Measured from Iran, the
# address DNS hands out is sometimes the one that times out while others answer
# in about a second -- which is the same problem EdgeRouter solves inside the
# app, for the same reason.
EDGES = ["104.18.0.1", "104.16.0.1", "188.114.96.1", "172.66.0.1", "104.17.0.1"]

# Roughly proportional to what the pool actually holds, with a floor so a
# scarce protocol still appears. A bundle that is all one protocol can be
# emptied by a single filter.
QUOTAS = {"vless": 45, "ss": 25, "vmess": 20, "hysteria": 12, "trojan": 8}


def fetch(path: str, edge: str, timeout: int = 20) -> dict:
    """One request, straight to `edge`, with SNI and Host left intact."""
    raw = socket.create_connection((edge, 443), timeout=timeout)
    context = ssl.create_default_context()
    with context.wrap_socket(raw, server_hostname=HOST) as tls:
        tls.settimeout(timeout * 3)
        tls.sendall(
            f"GET {path} HTTP/1.1\r\nHost: {HOST}\r\n"
            f"User-Agent: verna-seed\r\nAccept: application/json\r\n"
            f"Connection: close\r\n\r\n".encode()
        )
        buffer = b""
        while True:
            chunk = tls.recv(65536)
            if not chunk:
                break
            buffer += chunk

    head, _, body = buffer.partition(b"\r\n\r\n")
    if b"chunked" in head.lower():
        decoded, rest = b"", body
        while rest:
            line, _, rest = rest.partition(b"\r\n")
            size = int(line.split(b";")[0], 16)
            if size == 0:
                break
            decoded, rest = decoded + rest[:size], rest[size + 2 :]
        body = decoded
    return json.loads(body.decode("utf-8"))


def working_edge() -> str | None:
    """The first edge that answers, or None if the API is unreachable."""
    for edge in EDGES:
        try:
            fetch("/api/v1/health", edge, timeout=8)
            return edge
        except Exception:
            continue
    return None


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")

    edge = working_edge()
    if edge is None:
        print("no Cloudflare edge answered; leaving the bundle untouched")
        return 1
    print(f"using edge {edge}")

    servers: list[dict] = []
    for kind, limit in QUOTAS.items():
        try:
            page = fetch(f"/api/v1/configs/verified?type={kind}&limit={limit}", edge)
            rows = page.get("configs", [])
            servers.extend(rows)
            print(f"  {kind:<10} {len(rows):>3}")
        except Exception as error:
            print(f"  {kind:<10} failed: {type(error).__name__}")

    if not servers:
        print("nothing fetched; leaving the bundle untouched")
        return 1

    payload = json.dumps(
        {
            "generated": _dt.datetime.now().isoformat(timespec="seconds"),
            "note": (
                "Last resort only: used when the live API and the on-device "
                "cache are both unavailable. Entries are re-tested before use."
            ),
            "configs": servers,
        },
        ensure_ascii=False,
        separators=(",", ":"),
    )

    # Built in memory and written once. Opening a file for writing truncates it
    # immediately, so a fault between open and write leaves nothing behind --
    # which is how a source file was lost on this project once already.
    io.open("assets/seed_configs.json", "w", encoding="utf-8", newline="\n").write(
        payload
    )
    print(f"\nwrote assets/seed_configs.json  {len(servers)} servers, "
          f"{len(payload) / 1024:.0f} KB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
