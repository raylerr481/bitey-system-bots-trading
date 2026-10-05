from datetime import datetime, timezone
from typing import Any

from fastapi import APIRouter

from app.api.mt4 import _latest, _history, _backtests

router = APIRouter(prefix='/api/v1/ai-bot-lab', tags=['ai-bot-lab'])

_activity: list[dict[str, Any]] = []

def _log(message: str, level: str = "INFO", kind: str = "analysis") -> dict[str, Any]:
    item = {"timestamp": datetime.now(timezone.utc).isoformat(), "level": level, "kind": kind, "message": message}
    _activity.append(item)
    if len(_activity) > 200:
        del _activity[:-200]
    return item

def _bot(snapshot: dict[str, Any] | None) -> dict[str, Any]:
    if not snapshot:
        return {"connected": False, "name": None, "symbol": None, "timeframe": None, "mode": None, "regime": None}
    account = snapshot.get("account") or {}
    bot = snapshot.get("bot") or {}
    turtle = snapshot.get("turtle") or {}
    return {
        "connected": True,
        "name": bot.get("name") or snapshot.get("source", "MT4 EA"),
        "strategy": bot.get("strategy") or turtle.get("system"),
        "version": bot.get("version"),
        "magic": bot.get("magic") or turtle.get("magic"),
        "symbol": snapshot.get("symbol"),
        "timeframe": snapshot.get("timeframe"),
        "mode": account.get("mode", snapshot.get("mode")),
        "broker": account.get("broker"),
        "server": account.get("server"),
        "regime": snapshot.get("regime"),
        "execution_enabled": bool(snapshot.get("execution_enabled", False)),
        "last_seen": snapshot.get("timestamp"),
    }

def _analysis(snapshot: dict[str, Any] | None) -> dict[str, Any]:
    if not snapshot:
        return {"state": "WAITING_FOR_MT4", "summary": "Esperando el bot conectado a MT4. No se inventan datos.", "evidence": "NO_EVIDENCE"}
    turtle = snapshot.get("turtle") or {}
    messages = [
        "Snapshot de MT4 recibido y validado.",
        f"Bot observado: {snapshot.get('source', 'MT4 EA')}.",
        f"Mercado: {snapshot.get('symbol', '—')} {snapshot.get('timeframe', '—')}.",
        f"Régimen: {snapshot.get('regime', 'UNKNOWN')}."
    ]
    if turtle:
        messages.append("Telemetría Turtle disponible para análisis especializado.")
    messages.append("La optimización no modifica automáticamente el EA activo.")
    return {"state": "ANALYZING", "summary": "Bitey está analizando el bot que realmente está conectado a MT4.", "evidence": "MT4_LIVE_SNAPSHOT", "messages": messages, "turtle_parameters": turtle}

@router.get('/status')
def status():
    return {
        "source": "Bitey SBT AI Bot Lab",
        "bot": _bot(_latest),
        "analysis": _analysis(_latest),
        "activity": list(reversed(_activity[-50:])),
        "optimization": {"automatic": True, "state": "READY_TO_ANALYZE" if _latest else "WAITING_FOR_MT4", "automatic_parameter_application": False, "evidence_required": ["MT4 telemetry", "trade outcomes", "backtest", "walk-forward", "robustness"]}
    }

@router.post('/analyze')
def analyze():
    result = _analysis(_latest)
    _log("Bitey inició el análisis del bot seleccionado en MT4.")
    for message in result.get("messages", [])[-4:]:
        _log(message)
    return {"accepted": True, "bot": _bot(_latest), "analysis": result}

@router.post('/optimize')
def optimize():
    if not _latest:
        return {"state": "WAITING_FOR_MT4", "optimized": False, "reason": "No existe snapshot de MT4.", "activity": _log("Optimización pendiente: MT4 no está conectado.", "WARN", "optimization")}
    _log("Optimización iniciada; separando observación de cambios de parámetros.", kind="optimization")
    evidence = len(_history) >= 30 or len(_backtests) > 0
    state = "READY_FOR_VALIDATION" if evidence else "INSUFFICIENT_EVIDENCE"
    reason = "Existe evidencia para preparar candidatos y validarlos." if evidence else "Hay telemetría, pero falta evidencia suficiente de resultados para declarar un óptimo."
    _log(reason, "INFO" if evidence else "WARN", "optimization")
    return {"state": state, "optimized": False, "reason": reason, "bot": _bot(_latest), "next_steps": ["backtest", "walk_forward", "robustness", "demo_validation"], "automatic_parameter_application": False}

@router.get('/activity')
def activity(limit: int = 50):
    limit = max(1, min(limit, 200))
    return {"items": list(reversed(_activity[-limit:])), "count": len(_activity)}
