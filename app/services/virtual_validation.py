from dataclasses import dataclass

from app.core.models import DemoPortfolio, OrderIntent, Side
from app.risk.engine import RiskEngine
from app.services.demo_engine import DemoEngine
from app.strategies.technical import EmaRsiAtrRequest, ema_rsi_atr_signal


@dataclass(frozen=True)
class ValidationConfig:
    symbol: str = "EURUSD"
    initial_capital: float = 10_000.0
    quantity: float = 150.0
    window: int = 60


def _fixture_prices() -> list[float]:
    """Deterministic close-only fixture; deliberately not presented as market history."""
    prices: list[float] = []
    price = 1.1000
    for i in range(180):
        if i < 45:
            delta = 0.0008
        elif i < 85:
            delta = -0.0009
        elif i < 125:
            delta = 0.0010
        else:
            delta = -0.0007
        # Fixed, repeatable micro-variation prevents a perfectly linear series.
        wiggle = ((i % 5) - 2) * 0.00005
        price = round(price + delta + wiggle, 6)
        prices.append(price)
    return prices


def run_virtual_validation(config: ValidationConfig | None = None) -> dict:
    config = config or ValidationConfig()
    prices = _fixture_prices()
    portfolio = DemoPortfolio(initial_capital=config.initial_capital, cash=config.initial_capital)
    risk = RiskEngine(
        max_position_pct=0.02,
        max_daily_loss_pct=0.01,
        allowed_symbols={config.symbol},
    )
    engine = DemoEngine(portfolio, risk)

    accepted: list[dict] = []
    rejected: list[dict] = []
    equity_curve = [portfolio.initial_capital]
    previous_action = "hold"

    for index in range(config.window, len(prices)):
        signal = ema_rsi_atr_signal(
            EmaRsiAtrRequest(symbol=config.symbol, prices=prices[: index + 1])
        )
        action = signal["action"]
        if action == previous_action or action == "hold":
            previous_action = action
            equity_curve.append(portfolio.cash + sum(p.quantity * prices[index] for p in portfolio.positions))
            continue

        side = Side.BUY if action == "buy" else Side.SELL
        result = engine.simulate_order(
            OrderIntent(symbol=config.symbol, side=side, quantity=config.quantity),
            prices[index],
        )
        event = {
            "index": index,
            "price": prices[index],
            "side": side.value,
            "signal": signal,
            "executed": result.get("executed", False),
            "reason": result.get("reason"),
        }
        if result.get("executed"):
            accepted.append(event)
        else:
            rejected.append(event)
        previous_action = action
        equity_curve.append(portfolio.cash + sum(p.quantity * prices[index] for p in portfolio.positions))

    # Close any remaining virtual position so realized P/L is complete.
    if portfolio.positions:
        position = portfolio.positions[0]
        result = engine.simulate_order(
            OrderIntent(symbol=config.symbol, side=Side.SELL, quantity=position.quantity),
            prices[-1],
        )
        event = {
            "index": len(prices) - 1,
            "price": prices[-1],
            "side": "sell",
            "signal": {"strategy": "forced-validation-close"},
            "executed": result.get("executed", False),
            "reason": result.get("reason"),
        }
        if result.get("executed"):
            accepted.append(event)
        else:
            rejected.append(event)
        equity_curve.append(portfolio.cash)

    peak = config.initial_capital
    max_drawdown = 0.0
    for equity in equity_curve:
        peak = max(peak, equity)
        if peak:
            max_drawdown = max(max_drawdown, (peak - equity) / peak)

    pnl = portfolio.realized_pnl
    wins = 0
    losses = 0
    for i in range(0, len(accepted) - 1, 2):
        if accepted[i]["side"] == "buy" and accepted[i + 1]["side"] == "sell":
            trade_pnl = (accepted[i + 1]["price"] - accepted[i]["price"]) * accepted[i]["signal"].get("quantity", config.quantity)
            if trade_pnl > 0:
                wins += 1
            elif trade_pnl < 0:
                losses += 1

    closed_trades = wins + losses
    return {
        "validation": "deterministic-virtual-v1",
        "fixture": "synthetic-deterministic-not-market-history",
        "strategy": "ema-rsi-atr-v1",
        "symbol": config.symbol,
        "timeframe": "H1-compatible signal window",
        "initial_capital": config.initial_capital,
        "final_virtual_cash": round(portfolio.cash, 6),
        "realized_pnl": round(pnl, 6),
        "return_pct": round((pnl / config.initial_capital) * 100, 6),
        "max_drawdown_pct": round(max_drawdown * 100, 6),
        "accepted_operations": len(accepted),
        "rejected_operations": len(rejected),
        "closed_trades": closed_trades,
        "wins": wins,
        "losses": losses,
        "win_rate_pct": round((wins / closed_trades) * 100, 4) if closed_trades else 0.0,
        "risk_limits": {"max_position_pct": 2.0, "max_daily_loss_pct": 1.0},
        "real_money": False,
        "broker_orders": 0,
        "live_trading_enabled": False,
        "operations": accepted,
        "rejections": rejected,
    }
