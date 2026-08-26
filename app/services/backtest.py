from dataclasses import dataclass
from typing import Callable, Sequence


@dataclass(frozen=True)
class BacktestResult:
    initial_capital: float
    final_equity: float
    total_return_pct: float
    trades: int
    wins: int
    losses: int
    max_drawdown_pct: float


def run_backtest(
    prices: Sequence[float],
    signal_fn: Callable[[Sequence[float], int], str],
    initial_capital: float = 10_000.0,
    fee_pct: float = 0.0,
) -> BacktestResult:
    if initial_capital <= 0:
        raise ValueError("initial_capital must be positive")
    if len(prices) < 2:
        raise ValueError("at least two prices are required")

    cash = float(initial_capital)
    shares = 0.0
    entry_equity = None
    trades = wins = losses = 0
    peak = initial_capital
    max_drawdown = 0.0

    for i, raw_price in enumerate(prices):
        price = float(raw_price)
        if price <= 0:
            raise ValueError("prices must be positive")
        action = signal_fn(prices, i).lower()

        if action == "buy" and shares == 0:
            qty = cash / price
            cost = qty * price * (1 + fee_pct)
            if cost <= cash:
                cash -= cost
                shares = qty
                entry_equity = cash + shares * price
                trades += 1
        elif action == "sell" and shares > 0:
            proceeds = shares * price * (1 - fee_pct)
            cash += proceeds
            exit_equity = cash
            if entry_equity is not None:
                if exit_equity > entry_equity:
                    wins += 1
                else:
                    losses += 1
            shares = 0.0
            entry_equity = None

        equity = cash + shares * price
        peak = max(peak, equity)
        drawdown = ((peak - equity) / peak) * 100
        max_drawdown = max(max_drawdown, drawdown)

    final_equity = cash + shares * float(prices[-1])
    return BacktestResult(
        initial_capital=initial_capital,
        final_equity=final_equity,
        total_return_pct=((final_equity / initial_capital) - 1) * 100,
        trades=trades,
        wins=wins,
        losses=losses,
        max_drawdown_pct=max_drawdown,
    )
