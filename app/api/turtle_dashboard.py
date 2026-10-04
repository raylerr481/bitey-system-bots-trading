from __future__ import annotations

import asyncio
from typing import Any

from fastapi import APIRouter
from fastapi.responses import HTMLResponse

from app.integrations.mt4_gateway import MT4GatewayClient
from app.turtle import TurtleController

router = APIRouter(prefix="/api/v1/turtle", tags=["turtle-dashboard"])

_controller = TurtleController()


@router.get("/dashboard")
async def turtle_dashboard() -> dict[str, Any]:
    """Return the read-only MT4 + Turtle dashboard snapshot."""
    client = MT4GatewayClient()

    status, account, market, positions = await asyncio.gather(
        client.status(),
        _safe_get(client.account_status),
        _safe_get(lambda: client.market_data("EURUSD")),
        _safe_get(client.open_positions),
    )

    return {
        "module": "Bitey SBT Turtle/MT4 Dashboard",
        "read_only": True,
        "live_execution": False,
        "trading_enabled": False,
        "mt4": {
            "status": status,
            "account": account,
            "positions": positions,
            "market": market,
        },
        "turtle": {
            "baseline": _controller.baseline(),
            "state": "READY",
            "automation": "bounded",
            "optimization_locked": True,
            "campaign": None,
        },
    }


async def _safe_get(callable_: Any) -> dict[str, Any]:
    try:
        return await callable_()
    except Exception as exc:
        return {
            "ok": False,
            "reachable": False,
            "error": str(exc),
        }


DASHBOARD_HTML = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Bitey SBT — Turtle / MT4</title>
<style>
:root{color-scheme:dark;font-family:Inter,Segoe UI,system-ui,sans-serif}
body{margin:0;background:#0b1020;color:#e8edf7}
main{max-width:1180px;margin:auto;padding:28px}
h1{margin:0 0 6px;font-size:28px}
.sub{color:#93a0b8;margin-bottom:24px}
.grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:14px}
.card{background:#121a2b;border:1px solid #26334d;border-radius:14px;padding:18px}
.label{font-size:12px;text-transform:uppercase;letter-spacing:.08em;color:#8f9db7}
.value{font-size:24px;font-weight:700;margin-top:7px}
.ok{color:#65d391}.off{color:#f2c66d}.bad{color:#ff7d7d}
.section{margin-top:18px}
.kv{display:grid;grid-template-columns:180px 1fr;gap:8px;border-top:1px solid #26334d;padding:9px 0}
.kv:first-child{border-top:0}
pre{white-space:pre-wrap;word-break:break-word;color:#b9c4d8}
@media(max-width:850px){.grid{grid-template-columns:repeat(2,1fr)}}
@media(max-width:520px){.grid{grid-template-columns:1fr}.kv{grid-template-columns:1fr}}
</style>
</head>
<body>
<main>
<h1>Bitey SBT — Turtle / MT4 Control</h1>
<div class="sub">Read-only operational dashboard · refreshes every 2 seconds</div>
<div id="cards" class="grid"></div>
<div class="section card"><div class="label">MT4 snapshot</div><div id="snapshot">Loading…</div></div>
<div class="section card"><div class="label">Turtle baseline</div><pre id="baseline">Loading…</pre></div>
</main>
<script>
const esc=v=>String(v??"—").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;","'":"&#39;"}[c]));
async function refresh(){
  try{
    const r=await fetch("/api/v1/turtle/dashboard",{cache:"no-store"});
    const d=await r.json();
    const s=d.mt4.status||{};
    const a=d.mt4.account||{};
    const m=d.mt4.market||{};
    const p=d.mt4.positions||{};
    const reachable=Boolean(s.reachable&&s.data?.state_file_exists);
    document.getElementById("cards").innerHTML=[
      ["MT4 Gateway",reachable?"CONNECTED":"OFFLINE",reachable?"ok":"bad"],
      ["Trading",d.trading_enabled?"ENABLED":"DISABLED",d.trading_enabled?"bad":"off"],
      ["Balance",a.balance!==undefined?Number(a.balance).toFixed(2)+" "+esc(a.currency):"—",""],
      ["Positions",Array.isArray(p.positions)?p.positions.length:"—",""]
    ].map(x=>'<div class="card"><div class="label">'+x[0]+'</div><div class="value '+x[2]+'">'+x[1]+'</div></div>').join("");
    document.getElementById("snapshot").innerHTML=
      '<div class="kv"><b>Symbol</b><span>'+esc(m.symbol)+'</span></div>'+
      '<div class="kv"><b>Bid / Ask</b><span>'+esc(m.bid)+' / '+esc(m.ask)+'</span></div>'+
      '<div class="kv"><b>Spread</b><span>'+esc(m.spread_points)+' points</span></div>'+
      '<div class="kv"><b>Equity</b><span>'+esc(a.equity)+' '+esc(a.currency)+'</span></div>'+
      '<div class="kv"><b>Free margin</b><span>'+esc(a.free_margin)+' '+esc(a.currency)+'</span></div>'+
      '<div class="kv"><b>Gateway transport</b><span>'+esc(s.data?.transport)+'</span></div>';
    document.getElementById("baseline").textContent=JSON.stringify(d.turtle.baseline,null,2);
  }catch(e){
    document.getElementById("cards").innerHTML='<div class="card bad">Dashboard unavailable: '+esc(e)+'</div>';
  }
}
refresh();setInterval(refresh,2000);
</script>
</body>
</html>"""


@router.get("/dashboard/ui", response_class=HTMLResponse)
def turtle_dashboard_ui() -> str:
    """Serve the minimal built-in SBT Turtle/MT4 dashboard."""
    return DASHBOARD_HTML
