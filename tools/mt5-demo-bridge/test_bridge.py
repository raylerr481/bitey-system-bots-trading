import json
import sys
import urllib.error
import urllib.request

BASE_URL = "http://127.0.0.1:8787"


def get(path: str):
    with urllib.request.urlopen(BASE_URL + path, timeout=5) as response:
        return response.status, json.loads(response.read().decode("utf-8"))


checks = [
    "/health",
    "/quote/BTCUSDT",
    "/candles/BTCUSDT?timeframe=M1&limit=100",
]

for path in checks:
    try:
        status, payload = get(path)
    except (urllib.error.URLError, TimeoutError) as exc:
        print(f"FAIL {path}: bridge unavailable: {exc}")
        sys.exit(1)

    print(f"PASS {path}: HTTP {status}")
    print(json.dumps(payload, indent=2))

health = get("/health")[1]
if not health.get("terminal_connected"):
    print("FAIL: MT5 terminal is not connected")
    sys.exit(2)

candles = get("/candles/BTCUSDT?timeframe=M1&limit=100")[1]
count = int(candles.get("count", 0))
if count < 35:
    print(f"FAIL: only {count} valid candles; SBT requires at least 35")
    sys.exit(3)

print(f"PASS: {count} BTCUSDT M1 candles available")
print("Bridge smoke test complete: read-only Demo market data is ready for SBT verification.")
