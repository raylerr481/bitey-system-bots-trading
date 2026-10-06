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

def _snapshot_fresh(snapshot: dict[str, Any] | None, max_age_seconds: int = 180) -> bool:
    if not snapshot:
        return False
    raw = snapshot.get("timestamp")
    if not raw:
        return False
    try:
        timestamp = datetime.fromisoformat(str(raw).replace("Z", "+00:00"))
        if timestamp.tzinfo is None:
            timestamp = timestamp.replace(tzinfo=timezone.utc)
        age = (datetime.now(timezone.utc) - timestamp).total_seconds()
        return 0 <= age <= max_age_seconds
    except (TypeError, ValueError):
        return False


def _bot(snapshot: dict[str, Any] | None) -> dict[str, Any]:
    if not snapshot:
        return {"connected": False, "name": None, "symbol": None, "timeframe": None, "mode": None, "regime": None, "fresh": False}
    account = snapshot.get("account") or {}
    bot = snapshot.get("bot") or {}
    turtle = snapshot.get("turtle") or {}
    fresh = _snapshot_fresh(snapshot)
    return {
        "connected": fresh,
        "fresh": fresh,
        "name": bot.get("name") or snapshot.get("source", "MT4 EA"),
        "strategy": bot.get("strategy") or turtle.get("system"),
        "version": bot.get("version"),
        "magic": bot.get("magic") or turtle.get("magic"),
        "symbol": snapshot.get("symbol"),
        "timeframe": snapshot.get("timeframe"),
        "mode": account.get("operating_environment") or account.get("mode", snapshot.get("mode")),
        "broker": account.get("broker"),
        "server": account.get("server"),
        "regime": snapshot.get("regime"),
        "execution_enabled": bool(snapshot.get("execution_enabled", False)),
        "last_seen": snapshot.get("timestamp"),
    }

def _analysis(snapshot: dict[str, Any] | None) -> dict[str, Any]:
    if not snapshot:
        return {"state": "WAITING_FOR_MT4", "summary": "Esperando el bot conectado a MT4. No se inventan datos.", "evidence": "NO_EVIDENCE"}
    if not _snapshot_fresh(snapshot):
        return {"state": "STALE_MT4_SNAPSHOT", "summary": "Existe un snapshot anterior de MT4, pero no hay telemetría reciente. No se considera el bot conectado.", "evidence": "STALE_EVIDENCE", "last_seen": snapshot.get("timestamp")}
    turtle = snapshot.get("turtle") or {}
    messages = [
        "Snapshot de MT4 recibido y validado.",
        f"Bot observado: {snapshot.get('source', 'MT4 EA')}.",
        f"Mercado: {snapshot.get('symbol', '—')} {snapshot.get('timeframe', '—')}.",
        f"Régimen: {snapshot.get('regime', 'UNKNOWN')}."
    ]
    if turtle:
        messages.append("Telemetría Turtle disponible para análisis especializado.")
    messages.append("Bitey IA puede decidir mejoras; SBT debe validar cada cambio antes de aplicar una modificación permitida.")
    return {"state": "ANALYZING", "summary": "Bitey está analizando el bot que realmente está conectado a MT4.", "evidence": "MT4_LIVE_SNAPSHOT", "messages": messages, "turtle_parameters": turtle}

@router.get('/context')
def context():
    """Stable read-only context contract for Bitey IA and other SBT clients."""
    bot = _bot(_latest)
    analysis = _analysis(_latest)
    optimization = {
        "state": "READY_TO_ANALYZE" if _snapshot_fresh(_latest) else "WAITING_FOR_MT4",
        "automatic": True,
        "automatic_parameter_application": False,
        "evidence_required": ["MT4 telemetry", "trade outcomes", "backtest", "walk-forward", "robustness"],
    }
    fresh = _snapshot_fresh(_latest)
    evidence_count = len(_history) + len(_backtests)
    phase = "OBSERVATION" if not fresh else ("VALIDATION" if evidence_count >= 30 or len(_backtests) > 0 else "LEARNING")
    next_action = (
        "Esperar telemetría MT4"
        if not fresh
        else "Recolectar más operaciones y resultados verificables"
        if phase == "LEARNING"
        else "Ejecutar backtest + walk-forward + robustness antes de considerar producción"
    )
    account = (_latest or {}).get("account") or {}
    raw_mode = str(account.get("operating_environment") or account.get("mode") or (_latest or {}).get("mode") or "UNKNOWN").upper()
    if any(token in raw_mode for token in ("REAL", "LIVE")):
        environment = "REAL"
    elif "PAPER" in raw_mode:
        environment = "PAPER"
    elif "DEMO" in raw_mode or "TEST" in raw_mode:
        environment = "DEMO"
    else:
        environment = "UNKNOWN"

    # Performance target is a measurable objective, not a promise of return.
    initial_capital = account.get("initial_balance", account.get("initial_capital"))
    current_equity = account.get("equity", account.get("balance"))
    try:
        initial_capital = float(initial_capital) if initial_capital is not None else None
        current_equity = float(current_equity) if current_equity is not None else None
    except (TypeError, ValueError):
        initial_capital = None
        current_equity = None
    target_return = 0.10
    observed_return = None
    target_amount = None
    if initial_capital and initial_capital > 0:
        target_amount = initial_capital * (1.0 + target_return)
        if current_equity is not None:
            observed_return = (current_equity - initial_capital) / initial_capital

    if environment == "REAL":
        production_status = "REAL_MONITORING"
    elif phase == "VALIDATION" and evidence_count >= 30:
        production_status = "WAITING_FOR_MANUAL_MT4_SWITCH"
    elif environment in {"DEMO", "PAPER"}:
        production_status = "BUILDING_EVIDENCE"
    else:
        production_status = "WAITING_FOR_MT4"

    decision = {
        "phase": phase,
        "objective": "maximizar beneficio neto mensual del bot seleccionado, sujeto a control estricto de riesgo, costes y robustez; no prometer beneficios",
        "evidence_count": evidence_count,
        "next_action": next_action,
        "environment": environment,
        "manual_transition_required": environment != "REAL",
        "transition_authority": "TRADER_IN_MT4",
        "automatic_mode_switch": False,
        "production_status": production_status,
        "parameter_changes": "VALIDATION_GATED",
        "target": {
            "minimum_reference_return": 0.10,
            "label": "+10% del capital de referencia",
            "initial_capital": initial_capital,
            "target_amount": target_amount,
            "observed_return": observed_return,
            "note": "Meta de validación; no garantiza rentabilidad mensual ni futura.",
        },
    }
    return {
        "contract": "bitey-sbt-ai-context-v2",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "mt4": {
            "connected": _snapshot_fresh(_latest),
            "fresh": _snapshot_fresh(_latest),
            "last_seen": (_latest or {}).get("timestamp"),
            "max_age_seconds": 180,
        },
        "bot": bot,
        "analysis": analysis,
        "optimization": optimization,
        "decision": decision,
        "activity": list(reversed(_activity[-20:])),
    }

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
    if not _snapshot_fresh(_latest):
        return {"state": "WAITING_FOR_MT4", "optimized": False, "reason": "No existe un snapshot reciente de MT4.", "activity": _log("Optimización pendiente: MT4 no está conectado.", "WARN", "optimization")}
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
