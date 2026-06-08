#!/usr/bin/env python3
"""Smoke-test Serena MCP stdio server (initialize → tools/list → find_symbol)."""

from __future__ import annotations

import json
import select
import subprocess
import sys


def read_msg(stdout, timeout_s: float = 120.0) -> dict:
    if not select.select([stdout], [], [], timeout_s)[0]:
        raise TimeoutError(f"no MCP response within {timeout_s}s")
    line = stdout.readline()
    if not line:
        raise TimeoutError("stdout closed before MCP message")
    return json.loads(line.decode())


def send_msg(stdin, msg: dict) -> None:
    stdin.write((json.dumps(msg) + "\n").encode())
    stdin.flush()


def main() -> int:
    cmd = [
        "/home/vader/.local/bin/serena",
        "start-mcp-server",
        "--context",
        "ide",
        "--project",
        "/home/vader/MY_SRC/tentura",
        "--open-web-dashboard",
        "false",
        "--enable-web-dashboard",
        "false",
    ]
    proc = subprocess.Popen(
        cmd,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        cwd="/home/vader/MY_SRC/tentura",
        bufsize=0,
    )
    assert proc.stdin and proc.stdout

    try:
        send_msg(
            proc.stdin,
            {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "protocolVersion": "2024-11-05",
                    "capabilities": {},
                    "clientInfo": {"name": "serena-smoke-test", "version": "1.0"},
                },
            },
        )
        init_resp = read_msg(proc.stdout, timeout_s=60.0)
        print("initialize:", init_resp.get("result", {}).get("serverInfo", init_resp))

        send_msg(proc.stdin, {"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}})

        send_msg(proc.stdin, {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
        tools_resp = read_msg(proc.stdout, timeout_s=30.0)
        tools = tools_resp.get("result", {}).get("tools", [])
        names = [t["name"] for t in tools]
        print(f"tools/list: {len(tools)} tools")
        print("sample:", names[:12])

        if "find_symbol" not in names:
            print("FAIL: find_symbol not exposed", file=sys.stderr)
            return 1

        send_msg(
            proc.stdin,
            {
                "jsonrpc": "2.0",
                "id": 3,
                "method": "tools/call",
                "params": {
                    "name": "find_symbol",
                    "arguments": {
                        "name_path_pattern": "RoomReadWatermarkStore",
                        "relative_path": "packages/client/lib",
                    },
                },
            },
        )
        call_resp = read_msg(proc.stdout, timeout_s=120.0)
        content = call_resp.get("result", {}).get("content", [])
        text = content[0].get("text", "") if content else ""
        print("find_symbol RoomReadWatermarkStore:")
        print(text[:1200] or call_resp)

        if call_resp.get("result", {}).get("isError"):
            print("FAIL: find_symbol returned error", file=sys.stderr)
            return 1

        print("OK: Serena MCP smoke test passed")
        return 0
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
        stderr = proc.stderr.read() if proc.stderr else ""
        if stderr:
            tail = stderr[-2000:]
            print("--- stderr tail ---", file=sys.stderr)
            print(tail, file=sys.stderr)


if __name__ == "__main__":
    raise SystemExit(main())
