#!/usr/bin/env python3
"""Local HTTP adapter for the MT4 MCP Gateway.

Binds to localhost only and exposes read-only MT4 snapshot endpoints so a
local Bitey desktop client can relay evidence to Bitey SBT.
"""
from __future__ import annotations

import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

from mt4_mcp_gateway import call_tool, load_config

HOST = "127.0.0.1"
PORT = int(os.getenv("MT4_HTTP_BRIDGE_PORT", "22347"))
CFG = load_config()


class Handler(BaseHTTPRequestHandler):
    def _send(self, code: int, payload: object) -> None:
        raw = json.dumps(payload, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.send_header("Access-Control-Allow-Origin", "http://localhost:5173")
        self.end_headers()
        self.wfile.write(raw)

    def do_OPTIONS(self) -> None:
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "http://localhost:5173")
        self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        path = parsed.path
        qs = parse_qs(parsed.query)

        if path == "/status":
            self._send(200, {
                "ok": True,
                "service": "mt4-http-bridge",
                "read_only": True,
                "gateway": "local-mcp",
            })
            return

        routes = {
            "/account_status": ("get_account_status", {}),
            "/open_positions": ("get_open_positions", {}),
            "/market_data": ("get_market_data", {
                "symbol": qs.get("symbol", [None])[0],
            }),
            "/trade_history": ("get_trade_history", {
                "limit": int(qs.get("limit", [100])[0]),
            }),
            "/turtle_audit": ("get_turtle_audit", {
                "symbol": qs.get("symbol", [None])[0],
                "limit": int(qs.get("limit", [500])[0]),
            }),
        }

        if path not in routes:
            self._send(404, {"error": "not_found"})
            return

        tool, args = routes[path]
        try:
            value = call_tool(tool, {k: v for k, v in args.items() if v is not None}, CFG)
            self._send(200, value)
        except Exception as exc:
            self._send(503, {"error": str(exc), "read_only": True})

    def log_message(self, fmt: str, *args: object) -> None:
        print("[MT4-HTTP]", fmt % args)


if __name__ == "__main__":
    print(f"MT4 HTTP bridge listening on http://{HOST}:{PORT} (read-only)")
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
