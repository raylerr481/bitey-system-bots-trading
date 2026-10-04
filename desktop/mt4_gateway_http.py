#!/usr/bin/env python3
"""Local read-only HTTP adapter for the MT4 desktop integration.

The HTTP layer is intentionally independent from any missing/optional MCP
Python package. A native MT4 provider can be attached later through
MT4_NATIVE_BRIDGE_URL. Until then, health/status remains available and all
data routes fail closed with a structured 503 response.

Binds to localhost only. No trading or broker credentials are handled here.
"""
from __future__ import annotations

import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import URLError
from urllib.parse import urlencode, urljoin, urlparse
from urllib.request import Request, urlopen

HOST = "127.0.0.1"
PORT = int(os.getenv("MT4_HTTP_BRIDGE_PORT", "22347"))
NATIVE_BRIDGE_URL = os.getenv("MT4_NATIVE_BRIDGE_URL", "").rstrip("/")
CORS_ORIGIN = os.getenv("MT4_HTTP_CORS_ORIGIN", "http://localhost:5173")


def _native_get(path: str, params: dict[str, object] | None = None) -> object:
    if not NATIVE_BRIDGE_URL:
        raise RuntimeError(
            "MT4 native bridge is not configured. Set MT4_NATIVE_BRIDGE_URL "
            "to the existing local MT4 read-only provider."
        )
    url = urljoin(NATIVE_BRIDGE_URL + "/", path.lstrip("/"))
    if params:
        clean = {k: v for k, v in params.items() if v is not None}
        if clean:
            url = f"{url}?{urlencode(clean)}"
    request = Request(url, method="GET")
    with urlopen(request, timeout=8) as response:
        return json.loads(response.read().decode("utf-8"))


class Handler(BaseHTTPRequestHandler):
    def _send(self, code: int, payload: object) -> None:
        raw = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.send_header("Access-Control-Allow-Origin", CORS_ORIGIN)
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(raw)

    def do_OPTIONS(self) -> None:
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", CORS_ORIGIN)
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
                "trading_enabled": False,
                "native_bridge_configured": bool(NATIVE_BRIDGE_URL),
                "native_bridge_url": NATIVE_BRIDGE_URL or None,
            })
            return

        routes = {
            "/account_status": ("/account_status", {}),
            "/open_positions": ("/open_positions", {}),
            "/market_data": ("/market_data", {
                "symbol": qs.get("symbol", [None])[0],
            }),
            "/trade_history": ("/trade_history", {
                "limit": int(qs.get("limit", [100])[0]),
            }),
            "/turtle_audit": ("/turtle_audit", {
                "symbol": qs.get("symbol", [None])[0],
                "limit": int(qs.get("limit", [500])[0]),
            }),
        }

        if path not in routes:
            self._send(404, {"error": "not_found"})
            return

        native_path, params = routes[path]
        try:
            self._send(200, _native_get(native_path, params))
        except (RuntimeError, URLError, TimeoutError, ValueError, OSError) as exc:
            self._send(503, {
                "ok": False,
                "error": str(exc),
                "read_only": True,
                "trading_enabled": False,
            })

    def log_message(self, fmt: str, *args: object) -> None:
        print("[MT4-HTTP]", fmt % args)


if __name__ == "__main__":
    print(
        f"MT4 HTTP bridge listening on http://{HOST}:{PORT} "
        "(read-only; trading disabled)"
    )
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
