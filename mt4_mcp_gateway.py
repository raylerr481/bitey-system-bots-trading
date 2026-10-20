#!/usr/bin/env python3
"""Local MCP gateway for MetaTrader 4.

Safe-by-default bridge:
- Reads MT4 FILE_COMMON snapshots and Turtle audit CSV files.
- Can compile/deploy EAs and launch Strategy Tester when paths are configured.
- Does not place trades and does not enable live command execution.

Transport: MCP-style JSON-RPC over stdio using Content-Length framing.
"""
from __future__ import annotations
import csv, json, os, shutil, subprocess, sys, time
from pathlib import Path
from typing import Any

APP_DIR = Path(__file__).resolve().parent
CONFIG_PATH = APP_DIR / "mt4_mcp_config.json"
DEFAULT_CONFIG = {
    "mt4_common_files": "",
    "mt4_terminal_exe": "",
    "metaeditor_exe": "",
    "experts_dir": "",
    "tester_reports_dir": "",
    "read_only": True,
}


def load_config() -> dict[str, Any]:
    cfg = DEFAULT_CONFIG.copy()
    if CONFIG_PATH.exists():
        cfg.update(json.loads(CONFIG_PATH.read_text(encoding="utf-8")))
    if not cfg["mt4_common_files"] and os.name == "nt":
        appdata = os.environ.get("APPDATA", "")
        candidate = Path(appdata) / "MetaQuotes" / "Terminal" / "Common" / "Files"
        cfg["mt4_common_files"] = str(candidate)
    return cfg


def common_dir(cfg: dict[str, Any]) -> Path:
    p = Path(cfg["mt4_common_files"])
    p.mkdir(parents=True, exist_ok=True) if p else None
    return p


def read_json_file(cfg: dict[str, Any], name: str) -> dict[str, Any]:
    p = common_dir(cfg) / name
    if not p.exists():
        raise FileNotFoundError(f"MT4 common file not found: {p}")
    return json.loads(p.read_text(encoding="utf-8", errors="replace"))


def find_files(cfg: dict[str, Any], pattern: str) -> list[str]:
    d = common_dir(cfg)
    return sorted(str(p) for p in d.glob(pattern))


def read_csv(path: Path, limit: int = 500) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", errors="replace", newline="") as f:
        rows = list(csv.DictReader(f, delimiter=";"))
    return rows[-limit:]


def find_turtle_audits(cfg: dict[str, Any], symbol: str | None = None) -> list[Path]:
    files = [Path(x) for x in find_files(cfg, "Turtle_v1_23_Audit_*.csv")]
    if symbol:
        files = [p for p in files if f"_{symbol}_" in p.name]
    return files


def compile_ea(cfg: dict[str, Any], source: str) -> dict[str, Any]:
    if cfg.get("read_only", True):
        raise PermissionError("Gateway is read-only. Set read_only=false in config to enable compilation.")
    editor = cfg.get("metaeditor_exe")
    if not editor:
        raise RuntimeError("metaeditor_exe is not configured")
    src = Path(source).expanduser().resolve()
    if not src.exists():
        raise FileNotFoundError(src)
    proc = subprocess.run([editor, "/compile", str(src)], capture_output=True, text=True, timeout=120)
    return {"returncode": proc.returncode, "stdout": proc.stdout[-8000:], "stderr": proc.stderr[-8000:], "source": str(src)}


def deploy_ea(cfg: dict[str, Any], source: str, filename: str | None = None) -> dict[str, Any]:
    if cfg.get("read_only", True):
        raise PermissionError("Gateway is read-only. Set read_only=false in config to enable deployment.")
    dest_dir = cfg.get("experts_dir")
    if not dest_dir:
        raise RuntimeError("experts_dir is not configured")
    src = Path(source).expanduser().resolve()
    if not src.exists():
        raise FileNotFoundError(src)
    dst = Path(dest_dir) / (filename or src.name)
    shutil.copy2(src, dst)
    return {"source": str(src), "destination": str(dst)}


def run_backtest(cfg: dict[str, Any], tester_ini: str) -> dict[str, Any]:
    if cfg.get("read_only", True):
        raise PermissionError("Gateway is read-only. Set read_only=false in config to enable Strategy Tester launch.")
    terminal = cfg.get("mt4_terminal_exe")
    if not terminal:
        raise RuntimeError("mt4_terminal_exe is not configured")
    ini = Path(tester_ini).expanduser().resolve()
    if not ini.exists():
        raise FileNotFoundError(ini)
    proc = subprocess.Popen([terminal, "/config:" + str(ini)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return {"started": True, "pid": proc.pid, "config": str(ini)}


def tool_list() -> list[dict[str, Any]]:
    return [
        {"name": "get_account_status", "description": "Read MT4 account balance/equity/free margin from the local bridge snapshot.", "inputSchema": {"type": "object", "properties": {}}},
        {"name": "get_open_positions", "description": "Read current MT4 open positions from the local bridge snapshot.", "inputSchema": {"type": "object", "properties": {}}},
        {"name": "get_market_data", "description": "Read current market snapshot exported by the bridge EA.", "inputSchema": {"type": "object", "properties": {}}},
        {"name": "get_trade_history", "description": "Read the most recent closed MT4 trades exported by the bridge EA.", "inputSchema": {"type": "object", "properties": {"limit": {"type": "integer", "default": 100}}}},
        {"name": "get_turtle_audit", "description": "Read Turtle v1.23 campaign audit rows from MT4 common files.", "inputSchema": {"type": "object", "properties": {"symbol": {"type": "string"}, "limit": {"type": "integer", "default": 500}}}},
        {"name": "change_ea_parameter", "description": "Create a parameter patch file for review; it does not alter a running EA.", "inputSchema": {"type": "object", "required": ["parameter", "value"], "properties": {"parameter": {"type": "string"}, "value": {}}}},
        {"name": "compile_ea", "description": "Compile an MQ4 file when gateway writes are explicitly enabled.", "inputSchema": {"type": "object", "required": ["source"], "properties": {"source": {"type": "string"}}}},
        {"name": "deploy_ea", "description": "Copy an EA to the configured MT4 Experts directory when writes are explicitly enabled.", "inputSchema": {"type": "object", "required": ["source"], "properties": {"source": {"type": "string"}, "filename": {"type": "string"}}}},
        {"name": "run_backtest", "description": "Launch an MT4 Strategy Tester config when writes are explicitly enabled.", "inputSchema": {"type": "object", "required": ["tester_ini"], "properties": {"tester_ini": {"type": "string"}}}},
    ]


def call_tool(name: str, args: dict[str, Any], cfg: dict[str, Any]) -> Any:
    if name == "get_account_status":
        return read_json_file(cfg, "MT4_MCP_state.json").get("account", {})
    if name == "get_open_positions":
        return read_json_file(cfg, "MT4_MCP_state.json").get("positions", [])
    if name == "get_market_data":
        return read_json_file(cfg, "MT4_MCP_state.json").get("market", {})
    if name == "get_trade_history":
        limit = max(1, min(int(args.get("limit", 100)), 200))
        return read_json_file(cfg, "MT4_MCP_state.json").get("history", [])[:limit]
    if name == "get_turtle_audit":
        rows = []
        for p in find_turtle_audits(cfg, args.get("symbol")):
            rows.extend(read_csv(p, int(args.get("limit", 500))))
        return rows[-int(args.get("limit", 500)):]
    if name == "change_ea_parameter":
        patch = {"time": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "parameter": args["parameter"], "value": args["value"], "status": "review_required"}
        out = common_dir(cfg) / "MT4_MCP_parameter_patch.json"
        out.write_text(json.dumps(patch, indent=2, ensure_ascii=False), encoding="utf-8")
        return {"created": str(out), "status": "review_required", "message": "No running EA was modified."}
    if name == "compile_ea": return compile_ea(cfg, args["source"])
    if name == "deploy_ea": return deploy_ea(cfg, args["source"], args.get("filename"))
    if name == "run_backtest": return run_backtest(cfg, args["tester_ini"])
    raise ValueError(f"Unknown tool: {name}")


def send(obj: dict[str, Any]) -> None:
    data = json.dumps(obj, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    sys.stdout.buffer.write(f"Content-Length: {len(data)}\r\n\r\n".encode("ascii"))
    sys.stdout.buffer.write(data)
    sys.stdout.buffer.flush()


def main() -> None:
    cfg = load_config()
    while True:
        line = sys.stdin.buffer.readline()
        if not line:
            break
        if not line.lower().startswith(b"content-length:"):
            continue
        length = int(line.split(b":", 1)[1].strip())
        while sys.stdin.buffer.readline().strip():
            pass
        body = sys.stdin.buffer.read(length)
        req = json.loads(body.decode("utf-8"))
        method = req.get("method")
        rid = req.get("id")
        try:
            if method == "initialize":
                result = {"protocolVersion": "2024-11-05", "capabilities": {"tools": {}}, "serverInfo": {"name": "mt4-mcp-gateway", "version": "0.1.0"}}
            elif method == "tools/list":
                result = {"tools": tool_list()}
            elif method == "tools/call":
                params = req.get("params", {})
                value = call_tool(params.get("name"), params.get("arguments", {}), cfg)
                result = {"content": [{"type": "text", "text": json.dumps(value, ensure_ascii=False, indent=2)}], "isError": False}
            elif method == "ping":
                result = {}
            else:
                continue
            if rid is not None:
                send({"jsonrpc": "2.0", "id": rid, "result": result})
        except Exception as exc:
            if rid is not None:
                send({"jsonrpc": "2.0", "id": rid, "error": {"code": -32000, "message": str(exc)}})


if __name__ == "__main__":
    main()
