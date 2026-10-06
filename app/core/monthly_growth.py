"""Monthly compound-growth engine for Bitey SBT.

This module is pure calculation logic. It never places broker orders and never
changes Risk Gate limits. The $500 value is the initial operational capital;
subsequent monthly capital compounds from realized net results.
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from math import isfinite
from typing import Any, Iterable, Mapping

INITIAL_OPERATIONAL_CAPITAL_USD = 500.0
DEFAULT_RISK_PCT = 0.25
DEFAULT_MAX_DAILY_LOSS_PCT = 2.0
Q_REWARD_SCALE_USD = 50.0


def _finite(value: float) -> float:
    number = float(value)
    if not isfinite(number):
        raise ValueError("Numeric values must be finite")
    return number


def _close_dt(value: Any) -> datetime:
    if isinstance(value, datetime):
        dt = value
    else:
        dt = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def net_trade_pnl(trade: Mapping[str, Any]) -> float:
    """Return realized net P&L using signed MT4 ledger fields."""
    return _finite(
        float(trade.get("pnl", 0.0))
        + float(trade.get("commission", 0.0))
        + float(trade.get("swap", 0.0))
        + float(trade.get("cost", 0.0))
    )


def clamp_reward(value: float) -> float:
    return max(-1.0, min(1.0, _finite(value)))


def monthly_q_reward(net_pnl: float) -> float:
    """Bounded monthly reward compatible with the global Q-learning scale."""
    return clamp_reward(_finite(net_pnl) / Q_REWARD_SCALE_USD)


@dataclass(frozen=True)
class MonthlyGrowthResult:
    scope_key: str
    month_start: str
    month_end: str
    environment: str
    initial_capital_usd: float
    opening_capital_usd: float
    net_pnl_usd: float
    capital_end_usd: float
    growth_pct: float
    gross_profit_usd: float
    gross_loss_usd: float
    trades: int
    wins: int
    losses: int
    win_rate_pct: float
    max_drawdown_usd: float
    max_drawdown_pct: float
    q_learning_reward: float
    risk_gate: dict[str, Any]
    safety: dict[str, Any]
    report: dict[str, Any]

    def to_dict(self) -> dict[str, Any]:
        return self.__dict__.copy()


class MonthlyCompoundGrowthEngine:
    """Build monthly compound-growth state from realized trade outcomes."""

    def __init__(
        self,
        initial_capital_usd: float = INITIAL_OPERATIONAL_CAPITAL_USD,
        risk_pct: float = DEFAULT_RISK_PCT,
        max_daily_loss_pct: float = DEFAULT_MAX_DAILY_LOSS_PCT,
    ) -> None:
        self.initial_capital_usd = _finite(initial_capital_usd)
        self.risk_pct = _finite(risk_pct)
        self.max_daily_loss_pct = _finite(max_daily_loss_pct)
        if self.initial_capital_usd <= 0:
            raise ValueError("Initial capital must be positive")
        if not 0 < self.risk_pct <= 100:
            raise ValueError("risk_pct must be in (0, 100]")
        if not 0 < self.max_daily_loss_pct <= 100:
            raise ValueError("max_daily_loss_pct must be in (0, 100]")

    def build_month(
        self,
        *,
        month_start: datetime,
        trades: Iterable[Mapping[str, Any]],
        opening_capital_usd: float | None = None,
        environment: str = "DEMO",
        scope_key: str = "traderwill-mt4",
        risk_gate: Mapping[str, Any] | None = None,
    ) -> MonthlyGrowthResult:
        start = _close_dt(month_start).replace(day=1, hour=0, minute=0, second=0, microsecond=0)
        next_month = (
            start.replace(year=start.year + 1, month=1)
            if start.month == 12
            else start.replace(month=start.month + 1)
        )
        opening = self.initial_capital_usd if opening_capital_usd is None else _finite(opening_capital_usd)
        if opening <= 0:
            raise ValueError("Opening capital must be positive")

        rows = []
        for trade in trades:
            close_time = _close_dt(trade["close_time"])
            if start <= close_time < next_month:
                rows.append((close_time, trade, net_trade_pnl(trade)))
        rows.sort(key=lambda item: item[0])

        net_pnl = sum(item[2] for item in rows)
        gross_profit = sum(max(0.0, item[2]) for item in rows)
        gross_loss = sum(min(0.0, item[2]) for item in rows)
        wins = sum(1 for _, _, pnl in rows if pnl > 0)
        losses = sum(1 for _, _, pnl in rows if pnl < 0)

        balance = opening
        peak = opening
        max_dd = 0.0
        for _, _, pnl in rows:
            balance = max(0.0, balance + pnl)
            peak = max(peak, balance)
            max_dd = max(max_dd, peak - balance)

        capital_end = max(0.0, opening + net_pnl)
        growth_pct = ((capital_end / opening) - 1.0) * 100.0
        max_dd_pct = (max_dd / peak) * 100.0 if peak > 0 else 0.0
        gate = {
            "status": "AUTHORITATIVE",
            "risk_pct": self.risk_pct,
            "max_daily_loss_pct": self.max_daily_loss_pct,
            "capital_for_next_period_usd": capital_end,
            "q_learning_can_change_risk": False,
            "q_learning_can_execute_orders": False,
            "martingale": False,
            **dict(risk_gate or {}),
        }

        report = {
            "contract": "bitey-monthly-compound-growth-v1",
            "period": {"start": start.isoformat(), "end_exclusive": next_month.isoformat()},
            "capital": {
                "initial_operational_usd": self.initial_capital_usd,
                "opening_usd": opening,
                "closing_usd": capital_end,
                "net_pnl_usd": net_pnl,
                "growth_pct": growth_pct,
            },
            "performance": {
                "gross_profit_usd": gross_profit,
                "gross_loss_usd": gross_loss,
                "trades": len(rows),
                "wins": wins,
                "losses": losses,
                "win_rate_pct": (wins / len(rows) * 100.0) if rows else 0.0,
                "max_drawdown_usd": max_dd,
                "max_drawdown_pct": max_dd_pct,
            },
            "q_learning": {
                "reward": monthly_q_reward(net_pnl),
                "source": "realized_net_pnl",
                "action_authority": "Q-learning selects among authorized actions only",
            },
            "risk_gate": gate,
            "safety": {
                "demo_or_real_agnostic": True,
                "manual_account_switch": True,
                "new_trade_created_by_engine": False,
                "martingale": False,
                "capital_floor_usd": 0.0,
            },
        }

        return MonthlyGrowthResult(
            scope_key=scope_key,
            month_start=start.date().isoformat(),
            month_end=next_month.date().isoformat(),
            environment=str(environment).upper(),
            initial_capital_usd=self.initial_capital_usd,
            opening_capital_usd=opening,
            net_pnl_usd=net_pnl,
            capital_end_usd=capital_end,
            growth_pct=growth_pct,
            gross_profit_usd=gross_profit,
            gross_loss_usd=gross_loss,
            trades=len(rows),
            wins=wins,
            losses=losses,
            win_rate_pct=(wins / len(rows) * 100.0) if rows else 0.0,
            max_drawdown_usd=max_dd,
            max_drawdown_pct=max_dd_pct,
            q_learning_reward=monthly_q_reward(net_pnl),
            risk_gate=gate,
            safety=report["safety"],
            report=report,
        )

    def build_compound_series(
        self,
        *,
        monthly_trades: Mapping[str, Iterable[Mapping[str, Any]]],
        opening_capital_usd: float | None = None,
        environment: str = "DEMO",
        scope_key: str = "traderwill-mt4",
    ) -> list[MonthlyGrowthResult]:
        capital = self.initial_capital_usd if opening_capital_usd is None else _finite(opening_capital_usd)
        results: list[MonthlyGrowthResult] = []
        for month_key in sorted(monthly_trades):
            month_start = datetime.fromisoformat(month_key + "-01").replace(tzinfo=timezone.utc)
            result = self.build_month(
                month_start=month_start,
                trades=monthly_trades[month_key],
                opening_capital_usd=capital,
                environment=environment,
                scope_key=scope_key,
            )
            results.append(result)
            capital = result.capital_end_usd
        return results
