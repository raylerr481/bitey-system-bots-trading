"""Quantitative translation of the trading-plan claims supplied from the video.

This module does not assume the claims are true. It turns them into explicit,
measurable hypotheses that can be compared with backtest results.
"""
from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class TradingHypothesis:
    initial_capital: float = 1000.0
    trades_per_month: int = 10
    months: int = 24
    win_rate: float = 0.40
    average_win_pct: float = 0.04
    average_loss_pct: float = 0.015
    risk_per_trade_pct: float = 0.02
    spread_cost_monthly_pct: float = 0.005
    slippage_cost_monthly_pct: float = 0.003
    swap_cost_monthly_pct: float = 0.002
    retain_pct: float = 0.50
    reserve_pct: float = 0.30
    local_spend_pct: float = 0.20

    def validate(self) -> None:
        if self.initial_capital <= 0:
            raise ValueError("initial_capital must be positive")
        if self.trades_per_month <= 0 or self.months <= 0:
            raise ValueError("trades_per_month and months must be positive")
        if not 0 <= self.win_rate <= 1:
            raise ValueError("win_rate must be between 0 and 1")
        if self.average_win_pct < 0 or self.average_loss_pct < 0:
            raise ValueError("average outcomes cannot be negative")
        if not 0 < self.risk_per_trade_pct <= 0.05:
            raise ValueError("risk_per_trade_pct must be in (0, 5%]")
        if abs(self.retain_pct + self.reserve_pct + self.local_spend_pct - 1.0) > 1e-9:
            raise ValueError("capital allocation must sum to 100%")


def expected_value_per_trade(h: TradingHypothesis) -> float:
    h.validate()
    return h.win_rate * h.average_win_pct - (1.0 - h.win_rate) * h.average_loss_pct


def expectancy_r_multiple(h: TradingHypothesis) -> float:
    h.validate()
    return expected_value_per_trade(h) / h.risk_per_trade_pct


def projected_equity(h: TradingHypothesis, include_costs: bool = True) -> list[float]:
    """Compound only the retained trading capital; costs are monthly drag."""
    h.validate()
    gross_monthly = h.trades_per_month * expected_value_per_trade(h)
    cost_drag = (
        h.spread_cost_monthly_pct + h.slippage_cost_monthly_pct + h.swap_cost_monthly_pct
        if include_costs else 0.0
    )
    net_monthly = gross_monthly - cost_drag
    equity = h.initial_capital
    series = [equity]
    for _ in range(h.months):
        equity *= 1.0 + net_monthly * h.retain_pct
        series.append(equity)
    return series


def evaluate_video_hypothesis(h: TradingHypothesis) -> dict:
    h.validate()
    ev = expected_value_per_trade(h)
    r_multiple = expectancy_r_multiple(h)
    gross_monthly = h.trades_per_month * ev
    cost_drag = h.spread_cost_monthly_pct + h.slippage_cost_monthly_pct + h.swap_cost_monthly_pct
    net_monthly = gross_monthly - cost_drag
    series = projected_equity(h, include_costs=True)
    total_trading_gain = series[-1] - h.initial_capital
    reserve = total_trading_gain * h.reserve_pct
    local_spend = total_trading_gain * h.local_spend_pct
    retained_gain = total_trading_gain * h.retain_pct
    return {
        "contract": "sbt-video-hypothesis-v1",
        "hypothesis": "40% win rate, +4% average win, -1.5% average loss, 10 trades/month",
        "assumptions": {
            "initial_capital": h.initial_capital,
            "trades_per_month": h.trades_per_month,
            "months": h.months,
            "win_rate": h.win_rate,
            "average_win_pct": h.average_win_pct,
            "average_loss_pct": h.average_loss_pct,
            "risk_per_trade_pct": h.risk_per_trade_pct,
            "monthly_cost_drag_pct": cost_drag,
            "capital_allocation": {"retain": h.retain_pct, "reserve": h.reserve_pct, "local_spend": h.local_spend_pct},
        },
        "metrics": {
            "expected_value_per_trade_pct": ev,
            "expectancy_r_multiple": r_multiple,
            "gross_expected_monthly_pct": gross_monthly,
            "net_expected_monthly_pct_before_compounding": net_monthly,
            "projected_equity_after_months": series[-1],
            "projected_trading_gain": total_trading_gain,
            "reserve_amount": reserve,
            "local_spend_amount": local_spend,
            "retained_gain": retained_gain,
        },
        "interpretation": {
            "profitable_expectancy": ev > 0,
            "costs_destroy_expectancy": net_monthly <= 0,
            "is_prediction": False,
            "requires_market_backtest": True,
            "requires_out_of_sample_validation": True,
        },
        "safety": {"live": False, "real_money": False, "broker_orders": 0},
    }
