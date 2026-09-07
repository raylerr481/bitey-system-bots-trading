from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class VideoHypothesis:
    """Quantitative hypothesis extracted from educational trading material.

    This is a test specification, not a claim that the source strategy is profitable.
    """

    contract: str = "sbt-video-hypothesis-v1"
    source: str = "Alex Ruiiz educational trading material"
    capital: float = 1000.0
    risk_pct: float = 0.02
    trades_per_month: int = 10
    win_rate: float = 0.40
    avg_win_pct: float = 0.04
    avg_loss_pct: float = 0.015
    partial_take_profit_pct: float = 0.50
    trailing_indicator: str = "ema"
    trailing_period: int = 21
    fee_pct: float = 0.001
    slippage_pct: float = 0.001
    monthly_swap_pct: float = 0.002

    def validate(self) -> None:
        if self.capital <= 0 or not 0 < self.risk_pct <= 0.05:
            raise ValueError("capital/risk parameters outside safety bounds")
        if not 0 < self.win_rate < 1 or self.avg_win_pct <= 0 or self.avg_loss_pct <= 0:
            raise ValueError("invalid expectancy parameters")
        if self.trades_per_month <= 0:
            raise ValueError("trades_per_month must be positive")
        if not 0 <= self.partial_take_profit_pct <= 1:
            raise ValueError("partial_take_profit_pct must be between 0 and 1")

    @property
    def expectancy_pct(self) -> float:
        return self.win_rate * self.avg_win_pct - (1 - self.win_rate) * self.avg_loss_pct

    @property
    def expectancy_r(self) -> float:
        return self.expectancy_pct / self.risk_pct

    @property
    def break_even_win_rate(self) -> float:
        return self.avg_loss_pct / (self.avg_win_pct + self.avg_loss_pct)

    @property
    def net_monthly_expectancy_pct(self) -> float:
        trading = self.expectancy_pct * self.trades_per_month
        costs = self.fee_pct * self.trades_per_month * 2 + self.slippage_pct * self.trades_per_month + self.monthly_swap_pct
        return trading - costs

    def compound(self, months: int = 24) -> list[dict[str, float]]:
        if months < 1 or months > 120:
            raise ValueError("months must be between 1 and 120")
        equity = self.capital
        rows = []
        for month in range(1, months + 1):
            gross = equity * self.expectancy_pct * self.trades_per_month
            costs = equity * (self.fee_pct * self.trades_per_month * 2 + self.slippage_pct * self.trades_per_month + self.monthly_swap_pct)
            net = gross - costs
            equity += net
            rows.append({"month": float(month), "equity": round(equity, 6), "net_return_pct": round((net / (equity - net)) * 100, 6)})
        return rows


def alex_ruiz_hypothesis() -> dict:
    hypothesis = VideoHypothesis()
    hypothesis.validate()
    return {
        "contract": hypothesis.contract,
        "source": hypothesis.source,
        "status": "hypothesis",
        "parameters": hypothesis.__dict__,
        "metrics": {
            "expectancy_pct_per_trade": hypothesis.expectancy_pct,
            "expectancy_r": hypothesis.expectancy_r,
            "break_even_win_rate": hypothesis.break_even_win_rate,
            "net_monthly_expectancy_pct_after_configured_costs": hypothesis.net_monthly_expectancy_pct,
        },
        "strategy_mapping": {
            "entry": "explicit Bot Builder rules; never inferred from marketing claims",
            "stop_loss": "risk engine position sizing from stop distance",
            "take_profit": "target based on configured reward:risk",
            "partial_exit": hypothesis.partial_take_profit_pct,
            "trailing": {"indicator": hypothesis.trailing_indicator, "period": hypothesis.trailing_period},
            "position_sizing": "risk_pct / stop_distance",
        },
        "required_validation": ["historical_backtest", "cost_model", "stress_test", "out_of_sample", "walk_forward", "virtual_validation"],
        "safety": {"live": False, "real_money": False, "broker_orders": 0},
    }
