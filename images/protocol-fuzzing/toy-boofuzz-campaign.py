#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import socket
from pathlib import Path


def send_case(host: str, port: int, payload: bytes) -> tuple[bool, str]:
    try:
        with socket.create_connection((host, port), timeout=1.0) as sock:
            sock.sendall(payload)
            reply = sock.recv(64)
            if not reply:
                return False, "connection closed without response"
            return True, reply.decode("utf-8", errors="replace")
    except Exception as exc:  # noqa: BLE001 - protocol failure evidence.
        return False, str(exc)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", required=True)
    parser.add_argument("--port", required=True, type=int)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    cases = [
        ("case-0001", b"PING\n"),
        ("case-0002", b"HELLO\n"),
        ("case-0003", b"CRASH\n"),
    ]
    failures = []
    for case_id, payload in cases:
        case_path = out / f"{case_id}.bin"
        case_path.write_bytes(payload)
        ok, detail = send_case(args.host, args.port, payload)
        if not ok:
            failures.append({"case_id": case_id, "path": str(case_path), "detail": detail})

    (out / "results.json").write_text(
        json.dumps({"case_count": len(cases), "failures": failures}, indent=2) + "\n",
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
