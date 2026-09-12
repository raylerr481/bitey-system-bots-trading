from dataclasses import dataclass
from typing import Callable, Sequence


@dataclass(frozen=True)
class BacktestTrade:
    side: str
    entry_index: int
    entry_price: float
    exit_index: int | None
    exit_price: float | None
    pnl_pct: float | None
    result: str


@dataclass(frozen=True)
class BacktestResult:
    initial_capital: float
    final_equity: float
    total_return_pct: float
    trades: int
    wins: int
    losses: int
    max_drawdown_pct: float
    trades_detail: list[dict]


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
    entry_index = None
    entry_price = None
    trades = wins = losses = 0
    peak = initial_capital
    max_drawdown = 0.0
    trades_detail: list[dict] = []

    for i, raw_price in enumerate(prices):
        price = float(raw_price)
        if price <= 0:
            raise ValueError("prices must be positive")
        action = signal_fn(prices, i).lower()

        if action == "buy" and shares == 0:
            qty = cash / (price * (1 + fee_pct))
            cost = qty * price * (1 + fee_pct)
            if cost <= cash:
                cash -= cost
                shares = qty
                entry_equity = cash + shares * price
                entry_index = i
                entry_price = price
                trades += 1
        elif action == "sell" and shares > 0:
            proceeds = shares * price * (1 - fee_pct)
            cash += proceeds
            exit_equity = cash
            won = entry_equity is not None and exit_equity > entry_equity
            if won:
                wins += 1
            else:
                losses += 1
            pnl_pct = ((exit_equity / entry_equity) - 1) * 100 if entry_equity else None
            trades_detail.append(BacktestTrade(
                side="BUY",
                entry_index=entry_index if entry_index is not None else i,
                entry_price=entry_price if entry_price is not None else price,
                exit_index=i,
                exit_price=price,
                pnl_pct=pnl_pct,
                result="win" if won else "loss",
            ).__dict__)
            shares = 0.0
            entry_equity = None
            entry_index = None
            entry_price = None

        equity = cash + shares * price
        peak = max(peak, equity)
        drawdown = ((peak - equity) / peak) * 100
        max_drawdown = max(max_drawdown, drawdown)

    final_equity = cash + shares * float(prices[-1])
    if shares > 0 and entry_equity is not None:
        unrealized_pct = ((final_equity / entry_equity) - 1) * 100
        trades_detail.append(BacktestTrade(
            side="BUY",
            entry_index=entry_index if entry_index is not None else len(prices) - 1,
            entry_price=entry_price if entry_price is not None else float(prices[-1]),
            exit_index=None,
            exit_price=None,
            pnl_pct=unrealized_pct,
            result="open",
        ).__dict__)

    return BacktestResult(
        initial_capital=initial_capital,
        final_equity=final_equity,
        total_return_pct=((final_equity / initial_capital) - 1) * 100,
        trades=trades,
        wins=wins,
        losses=losses,
        max_drawdown_pct=max_drawdown,
        trades_detail=trades_detail,
    )
