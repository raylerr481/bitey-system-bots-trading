from __future__ import annotations

import os
from datetime import datetime, timezone
from typing import Any

import httpx
from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel, Field

from app.api.turtle import update_from_mt4
from app.storage import backtest_evidence
from app.storage import live_trades

router = APIRouter(prefix="/api/v1/mt4", tags=["mt4-bitey"])

MT4_INGEST_TOKEN = os.getenv("MT4_INGEST_TOKEN", "")
BITEY_TRADING_URL = os.getenv(
    "BITEY_TRADING_URL",
    "https://bitey-ia-suprabrain.onrender.com/api/v2/trading/analyze",
).rstrip("/")
BITEY_Q_LEARNING_URL = os.getenv(
    "BITEY_Q_LEARNING_URL",
    "https://bitey-ia-suprabrain.onrender.com/api/v1/q-learning/sbt-experience",
).rstrip("/")
_latest: dict[str, Any] | None = None
_history: list[dict[str, Any]] = []
_backtests: list[dict[str, Any]] = []


class MT4EntryDiagnostic(BaseModel):
    ticket: int | None = None
    symbol: str = Field(min_length=1, max_length=32)
    timeframe: str = Field(min_length=2, max_length=12)
    side: str = Field(pattern=r"^(BUY|SELL)$")
    timestamp: str | None = None
    entry_price: float | None = None
    exit_price: float | None = None
    pnl: float = 0.0
    r_multiple: float | None = None
    score: float | None = None
    score_gap: float | None = None
    rsi: float | None = None
    adx: float | None = None
    atr: float | None = None
    ema_fast: float | None = None
    ema_slow: float | None = None
    ema_200: float | None = None
    regime: str = "UNKNOWN"
    htf_direction: str = "NEUTRAL"
    exit_reason: str = "UNKNOWN"
    duration_bars: int | None = None
    mae_pct: float | None = None
    mfe_pct: float | None = None


class MT4EntryDiagnosticsReport(BaseModel):
    source: str = "AI_Trading_Bot_v1.34_Bitey"
    symbol: str = Field(min_length=1, max_length=32)
    timeframe: str = Field(min_length=2, max_length=12)
    report_type: str = "entry_diagnostics"
    trades: list[MT4EntryDiagnostic] = Field(default_factory=list, max_length=5000)


class MT4TradingReport(BaseModel):
    source: str = "AI_Trading_Bot_v1.34_Bitey"
    symbol: str = Field(min_length=1, max_length=32)
    timeframe: str = Field(min_length=2, max_length=12)
    chart_timeframe: str | None = None
    experiment_id: str | None = None
    timestamp: str | None = None
    mode: str = "AI_ASSIST"
    execution_enabled: bool = False
    regime: str = "UNKNOWN"
    hurst: float | None = None
    best_strategy: str | None = None
    best_score: float | None = None
    metrics: dict[str, Any] = Field(default_factory=dict)
    strategies: list[dict[str, Any]] = Field(default_factory=list, max_length=16)
    market: dict[str, Any] = Field(default_factory=dict)
    ai: dict[str, Any] = Field(default_factory=dict)
    risk_gate: dict[str, Any] = Field(default_factory=dict)
    account: dict[str, Any] = Field(default_factory=dict)
    turtle: dict[str, Any] = Field(default_factory=dict)
    report_type: str = "live_snapshot"
    bot: dict[str, Any] = Field(default_factory=dict)


def _normalize_evidence_lab(payload: dict[str, Any]) -> dict[str, Any]:
    """Normalize Evidence Lab v1.02 telemetry into the common SBT MT4 contract."""
    state = payload.get("state") or {}
    risk = payload.get("risk") or {}
    counters = payload.get("counters") or {}
    strategy = payload.get("strategy") or "UNKNOWN"
    signal = payload.get("signal") or state.get("current") or (payload.get("metrics") or {}).get("signal") or "NONE"
    previous = state.get("previous") or "NONE"
    change = state.get("change") or "NONE"
    account_in = payload.get("account") or {}
    positions = int(account_in.get("position_count") or state.get("position_count") or payload.get("position_count") or 0)
    operational_cap = min(float(risk.get("operational_capital_usd") or 500.0), 500.0)
    account_mode = payload.get("account_mode") or account_in.get("mode") or payload.get("mode") or "UNKNOWN"
    timeframe = payload.get("timeframe") or payload.get("strategy_timeframe") or "UNKNOWN"
    chart_timeframe = payload.get("chart_timeframe") or timeframe

    payload["signal"] = signal
    payload["direction"] = signal if signal in {"BUY", "SELL"} else "NONE"
    payload["previous_signal"] = previous
    payload["signal_change"] = change
    payload["regime"] = payload.get("regime") or "UNKNOWN"
    payload["strategy_timeframe"] = payload.get("strategy_timeframe") or timeframe
    payload["chart_timeframe"] = chart_timeframe
    payload["account"] = {
        **(payload.get("account") or {}),
        "mode": account_mode,
        "reported_mode": payload.get("mode") or account_mode,
        "operating_environment": "DEMO" if payload.get("research_only") is False and account_mode == "REAL" else account_mode,
        "operational_capital_usd": operational_cap,
        "equity": (payload.get("account") or {}).get("equity"),
        "balance": (payload.get("account") or {}).get("balance"),
        "position_count": positions,
    }
    account_balance = account_in.get("balance")
    account_equity = account_in.get("equity")
    mt4_balance = float(account_balance) if account_balance is not None else None
    mt4_equity = float(account_equity) if account_equity is not None else None
    floating_pnl = (mt4_equity - mt4_balance) if mt4_balance is not None and mt4_equity is not None else None
    mt4_to_sbt_ratio = (operational_cap / mt4_balance) if mt4_balance and mt4_balance > 0 else None
    mt4_to_sbt_multiple = (mt4_balance / operational_cap) if mt4_balance and operational_cap > 0 else None
    mt4_dd_abs = account_in.get("drawdown_abs")
    if mt4_dd_abs is None:
        mt4_dd_abs = account_in.get("absolute_drawdown")
    mt4_dd_abs = float(mt4_dd_abs) if mt4_dd_abs is not None else None
    mt4_dd_pct = account_in.get("drawdown_pct")
    if mt4_dd_pct is None:
        mt4_dd_pct = account_in.get("relative_drawdown_pct")
    mt4_dd_pct = float(mt4_dd_pct) if mt4_dd_pct is not None else None
    sbt_dd_pct = (mt4_dd_abs / operational_cap * 100.0) if mt4_dd_abs is not None and operational_cap > 0 else None
    payload["capital_correspondence"] = {
        "sbt_operational_capital_usd": operational_cap,
        "mt4_balance_usd": mt4_balance,
        "mt4_equity_usd": mt4_equity,
        "mt4_floating_pnl_usd": floating_pnl,
        "sbt_capital_as_pct_of_mt4_balance": mt4_to_sbt_ratio * 100.0 if mt4_to_sbt_ratio is not None else None,
        "mt4_balance_multiple_of_sbt_capital": mt4_to_sbt_multiple,
        "mt4_drawdown_abs_usd": mt4_dd_abs,
        "mt4_drawdown_pct": mt4_dd_pct,
        "sbt_operational_drawdown_pct": sbt_dd_pct,
        "risk_basis": "SBT_OPERATIONAL_CAPITAL",
        "risk_cap_usd": operational_cap,
        "mt4_account_is_execution_telemetry_only": True,
    }

    payload["account"] = {
        **(payload.get("account") or {}),
        "balance": mt4_balance,
        "equity": mt4_equity,
        "floating_pnl": floating_pnl,
        "position_count": positions,
        "operational_capital_usd": operational_cap,
        "capital_correspondence": payload["capital_correspondence"],
    }

    # Promote indicator/account telemetry into stable fields consumed by Turtle/Dashboard.
    market_in = payload.get("market") or {}
    metrics_in = payload.get("metrics") or {}
    market_out = {
        **market_in,
        "bid": market_in.get("bid", market_in.get("Bid", metrics_in.get("bid", metrics_in.get("Bid")))),
        "ask": market_in.get("ask", market_in.get("Ask", metrics_in.get("ask", metrics_in.get("Ask")))),
        "atr": market_in.get("atr", market_in.get("ATR", metrics_in.get("atr", metrics_in.get("ATR")))),
        "rsi": market_in.get("rsi", market_in.get("RSI", metrics_in.get("rsi", metrics_in.get("RSI")))),
        "adx": market_in.get("adx", market_in.get("ADX", metrics_in.get("adx", metrics_in.get("ADX")))),
    }
    payload["market"] = market_out

    payload["metrics"] = {
        **metrics_in,
        "signal": signal,
        "direction": payload["direction"],
        "positions_open": positions,
        "spread_points": state.get("spread_points"),
        "daily_drawdown_pct": state.get("daily_drawdown_pct"),
        "trades_today": state.get("trades_today"),
        "signals": counters.get("signals", 0),
        "buy_signals": counters.get("buy_signals", 0),
        "sell_signals": counters.get("sell_signals", 0),
        "block_session": counters.get("block_session", 0),
        "block_spread": counters.get("block_spread", 0),
        "block_daily_dd": counters.get("block_daily_dd", 0),
        "block_trade_limit": counters.get("block_trade_limit", 0),
        "operational_capital_usd": operational_cap,
        "risk_pct": risk.get("risk_pct"),
        "mt4_balance_usd": mt4_balance,
        "mt4_equity_usd": mt4_equity,
        "mt4_floating_pnl_usd": floating_pnl,
        "sbt_operational_drawdown_pct": sbt_dd_pct,
        "mt4_drawdown_abs_usd": mt4_dd_abs,
        "mt4_drawdown_pct": mt4_dd_pct,
        "risk_budget_usd": risk.get("risk_budget_usd"),
        "daily_loss_usd": risk.get("daily_loss_usd"),
        "max_daily_loss_pct": risk.get("max_daily_loss_pct"),
    }
    # Keep Turtle synchronized with authoritative MT4 telemetry, including the
    # stable market/account contract. Campaign-specific fields remain MT4-owned.
    turtle_in = payload.get("turtle") or payload.get("turtle_controller") or {}
    payload["turtle"] = {
        **turtle_in,
        "position_count": positions,
        "market": payload["market"],
        "last_entry": turtle_in.get("last_entry"),
        "campaign_n": turtle_in.get("campaign_n"),
        "s1_skip_next": turtle_in.get("s1_skip_next"),
        "s1_skip_latched": turtle_in.get("s1_skip_latched"),
    }

    payload["bot"] = {
        **(payload.get("bot") or {}),
        "name": (payload.get("bot") or {}).get("name") or f"Bitey Evidence Lab v{payload.get('lab_version', '1.02')}",
        "id": (payload.get("bot") or {}).get("id") or "bitey-evidence-lab-v1.02",
        "strategy": strategy,
        "version": (payload.get("bot") or {}).get("version") or payload.get("lab_version", "1.02"),
        "magic": (payload.get("bot") or {}).get("magic"),
        "symbol": payload.get("symbol"),
        "timeframe": timeframe,
        "signal": signal,
        "positions": positions,
        "active": True,
    }
    payload["evidence_lab"] = {
        "lab_version": payload.get("lab_version", "1.02"),
        "schema": payload.get("schema"),
        "source": payload.get("source"),
        "execution_enabled": bool(payload.get("execution_enabled", False)),
        "research_only": bool(payload.get("research_only", False)),
        "operational_capital_usd": operational_cap,
        "strategy": strategy,
        "timeframe": timeframe,
        "chart_timeframe": chart_timeframe,
        "signal": signal,
        "direction": payload["direction"],
        "counters": counters,
        "risk": risk,
        "state": state,
    }
    return payload


def _check_token(token: str | None) -> None:
    if MT4_INGEST_TOKEN and token != MT4_INGEST_TOKEN:
        raise HTTPException(status_code=401, detail="Invalid MT4 ingestion token")


@router.post("/bitey-report")
async def ingest_report(
    report: MT4TradingReport,
    x_mt4_token: str | None = Header(default=None),
):
    _check_token(x_mt4_token)
    global _latest
    payload = report.model_dump()
    payload["strategy_timeframe"] = report.timeframe
    payload["chart_timeframe"] = report.chart_timeframe or report.timeframe
    payload["experiment_id"] = report.experiment_id
    payload["timestamp"] = payload["timestamp"] or datetime.now(timezone.utc).isoformat()
    payload["source_module"] = "Bitey System Bots Trading"
    payload = _normalize_evidence_lab(payload)
    turtle_state = None
    if report.report_type == "live_snapshot":
        turtle_state = update_from_mt4(payload)
        payload["turtle_controller"] = turtle_state
    _latest = payload
    _history.append(payload)
    if len(_history) > 100:
        del _history[:-100]

    ai = None
    q_recommendation = None
    if BITEY_Q_LEARNING_URL and report.report_type == "live_snapshot":
        try:
            latest_signal = str(payload.get("signal") or "NONE")
            strategy = str(payload.get("strategy") or "ENSEMBLE")
            allowed_actions = [strategy, "BUY", "SELL", "HOLD"]
            q_context = {
                "current_intent_domain": "trading",
                "conversation_continuity": False,
                "selected_tools": ["sbt_market", "mt4"],
                "evidence_required": True,
                "freshness_required": True,
                "sbt": {
                    "symbol": report.symbol,
                    "timeframe": report.timeframe,
                    "strategy": strategy,
                    "regime": report.regime,
                    "signal": latest_signal,
                    "risk_gate": "authoritative",
                    "operational_capital_usd": 500.0,
                },
            }
            async with httpx.AsyncClient(timeout=8) as client:
                response = await client.post(BITEY_Q_LEARNING_URL.replace("/sbt-experience", "/recommendation"), json={
                    "state_context": q_context,
                    "allowed_actions": allowed_actions,
                    "source": "bitey_sbt_mt4",
                    "symbol": report.symbol,
                    "timeframe": report.timeframe,
                    "risk_gate_allowed": True,
                    "operational_capital_usd": 500.0,
                })
                if response.status_code < 400:
                    body = response.json()
                    q_recommendation = body.get("recommendation") if isinstance(body, dict) else None
        except Exception:
            q_recommendation = None

    if BITEY_TRADING_URL and report.report_type == "live_snapshot":
        try:
            snapshot = {
                **report.market,
                "symbol": report.symbol,
                "timeframe": report.timeframe,
                "mode": report.mode,
                "execution_enabled": report.execution_enabled,
                "regime": report.regime,
                "entry_score": report.metrics.get("entry_score", 0),
                "score_gap": report.metrics.get("score_gap", 0),
                "htf_direction": report.metrics.get("htf_direction", "NEUTRAL"),
                "metadata": {
                    **(report.market.get("metadata") or {}),
                    "mt4_reported_mode": report.mode,
                    "mt4_account_mode": (report.account or {}).get("mode"),
                    "turtle_controller": turtle_state or {},
                    "risk_gate": report.risk_gate,
                    "bot": report.bot,
                },
            }
            async with httpx.AsyncClient(timeout=8) as client:
                response = await client.post(BITEY_TRADING_URL, json=snapshot)
                if response.status_code < 400:
                    ai = response.json()
                    payload["ai"] = {**report.ai, **(ai if isinstance(ai, dict) else {})}
                    _latest = payload
        except (httpx.HTTPError, ValueError):
            ai = {"status": "unavailable", "fallback": "local_risk_gate"}

    return {
        "accepted": True,
        "stored": True,
        "source": report.source,
        "timestamp": payload["timestamp"],
        "bitey_ai": ai,
        "execution": "local_mt4_risk_gate",
        "turtle_controller": turtle_state,
        "q_learning": q_recommendation,
    }


class MT4ClosedTrade(BaseModel):
    source: str = "MT4_DESKTOP"
    account_mode: str = "UNKNOWN"
    ticket: int
    magic: int | None = None
    bot_id: str | None = None
    strategy: str | None = None
    version: str | None = None
    symbol: str = Field(min_length=1, max_length=32)
    timeframe: str = Field(min_length=2, max_length=12)
    side: str = Field(pattern=r"^(BUY|SELL)$")
    lots: float = 0.0
    open_time: str
    close_time: str
    open_price: float
    close_price: float
    stop_loss: float | None = None
    take_profit: float | None = None
    pnl: float = 0.0
    commission: float = 0.0
    swap: float = 0.0
    cost: float = 0.0
    exit_reason: str | None = None
    r_multiple: float | None = None
    metadata: dict[str, Any] = Field(default_factory=dict)


@router.post("/trade-closed")
async def ingest_closed_trade(
    trade: MT4ClosedTrade,
    x_mt4_token: str | None = Header(default=None),
):
    """Register one closed MT4 trade for DEMO/live performance measurement."""
    _check_token(x_mt4_token)
    payload = trade.model_dump()
    payload["source_module"] = "Bitey System Bots Trading"
    persistence = {"persisted": False, "reason": "SUPABASE_NOT_CONFIGURED"}
    try:
        persistence = live_trades.save(payload)
    except Exception as exc:
        persistence = {"persisted": False, "reason": "SUPABASE_WRITE_FAILED", "error": type(exc).__name__}

    # Feed closed-trade outcomes to Bitey's shared Q-learning policy.
    # This is learning-only: SBT Risk Gate and the $500 operational cap remain
    # authoritative and are never modified by Q-learning.
    q_learning = {"sent": False, "reason": "not_attempted"}
    try:
        # Send authoritative closed-trade PnL to Bitey; reward shaping is centralized there.
        latest = _latest or {}
        state_context = {
            "current_intent_domain": "trading",
            "conversation_continuity": False,
            "selected_tools": ["sbt_market", "mt4"],
            "evidence_required": True,
            "freshness_required": True,
            "sbt": {
                "symbol": trade.symbol,
                "timeframe": trade.timeframe,
                "side": trade.side,
                "strategy": trade.strategy,
                "regime": (latest.get("regime") or "UNKNOWN"),
                "signal": (latest.get("signal") or "NONE"),
                "risk_gate": "authoritative",
                "operational_capital_usd": 500.0,
            },
        }
        # Convert the authoritative MT4 outcome into a bounded Q-learning reward.
        # Prefer R-multiple when MT4 supplies it; otherwise use PnL sign. This
        # trains the policy from actual closed-trade outcomes without granting
        # Q-learning any execution or risk-control authority.
        if trade.r_multiple is not None:
            reward = max(-1.0, min(1.0, float(trade.r_multiple)))
        elif trade.pnl > 0:
            reward = 1.0
        elif trade.pnl < 0:
            reward = -1.0
        else:
            reward = 0.0

        async with httpx.AsyncClient(timeout=8) as client:
            response = await client.post(BITEY_Q_LEARNING_URL, json={
                "state_context": state_context,
                "next_context": state_context,
                "action": str(trade.strategy or trade.side),
                "reward": reward,
                "pnl_usd": float(trade.pnl),
                "drawdown_pct": None,
                "risk_used_pct": None,
                "source": "bitey_sbt_mt4",
                "outcome": "SUCCESS" if trade.pnl > 0 else "FAILURE" if trade.pnl < 0 else "UNKNOWN",
                "symbol": trade.symbol,
                "timeframe": trade.timeframe,
                "risk_gate_allowed": True,
                "operational_capital_usd": 500.0,
            })
            body = None
            try:
                body = response.json()
            except ValueError:
                body = None
            q_learning = {
                "sent": response.status_code < 400,
                "status": response.status_code,
                "reward": reward,
                "learning": body.get("learning") if isinstance(body, dict) else None,
            }
    except Exception as exc:
        q_learning = {"sent": False, "reason": type(exc).__name__}

    return {
        "accepted": True,
        "stored": True,
        "trade_key": live_trades.trade_key(payload),
        "account_mode": trade.account_mode,
        "execution": "mt4_local",
        "persistence": persistence,
        "q_learning": q_learning,
    }


@router.get("/trades")
def closed_trade_history(limit: int = 100):
    limit = max(1, min(limit, 5000))
    try:
        items = live_trades.list_recent(limit)
    except Exception:
        items = []
    return {"items": items, "count": len(items), "persistent_store": bool(items), "source": "MT4_DESKTOP"}

@router.get("/active-bot")
def active_bot():
    """Authoritative read-only view of the bot most recently reporting from MT4 Desktop."""
    if not _latest:
        return {
            "connected": False,
            "source": "MT4_DESKTOP",
            "bot": None,
            "account": None,
            "market": None,
            "last_seen": None,
        }
    return {
        "connected": True,
        "source": "MT4_DESKTOP",
        "bot": _latest.get("bot") or {
            "name": _latest.get("source"),
            "magic": (_latest.get("turtle") or {}).get("magic"),
            "strategy": (_latest.get("turtle") or {}).get("system"),
            "version": None,
        },
        "account": _latest.get("account", {}),
        "market": {
            "symbol": _latest.get("symbol"),
            "timeframe": _latest.get("timeframe"),
            "regime": _latest.get("regime"),
        },
        "execution": {
            "enabled": bool(_latest.get("execution_enabled", False)),
            "mode": _latest.get("mode", "UNKNOWN"),
        },
        "last_seen": _latest.get("timestamp"),
    }


@router.get("/bitey-latest")
def latest_report():
    return {
        "available": _latest is not None,
        "report": _latest,
        "history_count": len(_history),
    }


@router.get("/bitey-history")
def report_history(limit: int = 20):
    limit = max(1, min(limit, 100))
    return {"items": list(reversed(_history[-limit:])), "count": len(_history)}


@router.post("/bitey-backtest")
async def ingest_backtest(
    report: MT4TradingReport,
    x_mt4_token: str | None = Header(default=None),
):
    """Store a Strategy Tester/research result without treating it as live trading evidence."""
    _check_token(x_mt4_token)
    if report.report_type not in {"backtest", "strategy_tester", "research"}:
        report.report_type = "backtest"

    payload = report.model_dump()
    payload["timestamp"] = payload["timestamp"] or datetime.now(timezone.utc).isoformat()
    payload["source_module"] = "Bitey System Bots Trading"
    payload["evidence_class"] = "BACKTEST"
    payload["execution"] = "none"
    _backtests.append(payload)
    if len(_backtests) > 100:
        del _backtests[:-100]

    persistence = {"persisted": False, "reason": "SUPABASE_NOT_CONFIGURED"}
    try:
        persistence = backtest_evidence.save(payload)
    except Exception as exc:
        # Persistence failure must never turn a valid MT4 backtest into a live-trading failure.
        persistence = {"persisted": False, "reason": "SUPABASE_WRITE_FAILED", "error": type(exc).__name__}

    return {
        "accepted": True,
        "stored": True,
        "evidence_class": "BACKTEST",
        "source": report.source,
        "timestamp": payload["timestamp"],
        "live_execution": False,
        "persistence": persistence,
    }


def _bucket(value: float | None, edges: list[float]) -> str:
    if value is None:
        return "UNKNOWN"
    for edge in edges:
        if value < edge:
            return f"<{edge:g}"
    return f">={edges[-1]:g}"


def _diagnostic_summary(trades: list[MT4EntryDiagnostic]) -> dict[str, Any]:
    def group(rows: list[MT4EntryDiagnostic]) -> dict[str, Any]:
        wins = sum(1 for t in rows if t.pnl > 0)
        losses = sum(1 for t in rows if t.pnl < 0)
        pnl = sum(t.pnl for t in rows)
        return {
            "trades": len(rows),
            "wins": wins,
            "losses": losses,
            "win_rate": wins / len(rows) if rows else None,
            "net_pnl": pnl,
            "expectancy": pnl / len(rows) if rows else None,
        }

    losses = [t for t in trades if t.pnl < 0]
    score_buckets: dict[str, list[MT4EntryDiagnostic]] = {}
    for t in trades:
        score_buckets.setdefault(_bucket(t.score, [5, 6, 7, 8]), []).append(t)

    side = {s: group([t for t in trades if t.side == s]) for s in ("BUY", "SELL")}
    regime = {}
    for t in trades:
        regime.setdefault(t.regime, []).append(t)
    regime = {k: group(v) for k, v in regime.items()}

    exit_reason = {}
    for t in trades:
        exit_reason.setdefault(t.exit_reason, []).append(t)
    exit_reason = {k: group(v) for k, v in exit_reason.items()}

    loss_patterns = {
        "losses_by_score_bucket": {k: group(v) for k, v in score_buckets.items()},
        "losses_by_side": {k: group([t for t in losses if t.side == k]) for k in ("BUY", "SELL")},
        "losses_by_regime": {k: group([t for t in losses if t.regime == k]) for k in sorted({t.regime for t in losses})},
        "losses_by_exit_reason": {k: group([t for t in losses if t.exit_reason == k]) for k in sorted({t.exit_reason for t in losses})},
        "low_adx_losses": group([t for t in losses if t.adx is not None and t.adx < 20]),
        "high_rsi_buy_losses": group([t for t in losses if t.side == "BUY" and t.rsi is not None and t.rsi > 65]),
        "low_rsi_sell_losses": group([t for t in losses if t.side == "SELL" and t.rsi is not None and t.rsi < 35]),
    }

    return {
        "contract": "bitey-mt4-entry-diagnostics-v1",
        "trades": group(trades),
        "loss_count": len(losses),
        "loss_patterns": loss_patterns,
        "instruction": "DIAGNOSTIC_ONLY: do not change entry thresholds, SL, TP, ATR or risk from this report alone.",
    }


@router.post("/bitey-entry-diagnostics")
def ingest_entry_diagnostics(report: MT4EntryDiagnosticsReport, x_mt4_token: str | None = Header(default=None)):
    """Analyze individual MT4 entries before any strategy optimization."""
    _check_token(x_mt4_token)
    payload = report.model_dump()
    payload["timestamp"] = datetime.now(timezone.utc).isoformat()
    payload["source_module"] = "Bitey System Bots Trading"
    payload["analysis"] = _diagnostic_summary(report.trades)
    return payload


@router.get("/bitey-entry-diagnostics")
def entry_diagnostics_help():
    return {
        "contract": "bitey-mt4-entry-diagnostics-v1",
        "purpose": "Find which combinations produced losing MT4 entries before optimization.",
        "required_fields": ["side", "pnl", "score", "rsi", "adx", "atr", "regime", "exit_reason"],
        "optimization_locked": True,
    }


@router.get("/bitey-backtests")
def backtest_history(limit: int = 20):
    limit = max(1, min(limit, 100))
    persistent = []
    try:
        persistent = backtest_evidence.list_recent(limit)
    except Exception:
        persistent = []
    items = persistent if persistent else list(reversed(_backtests[-limit:]))
    return {"items": items, "count": len(items), "evidence_class": "BACKTEST", "persistent_store": bool(persistent)}
