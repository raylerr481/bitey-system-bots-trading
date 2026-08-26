from alpaca.trading.client import TradingClient
from alpaca.trading.requests import MarketOrderRequest
from alpaca.trading.enums import OrderSide, TimeInForce

from app.core.settings import ALPACA_API_KEY, ALPACA_SECRET_KEY, require_paper_mode


def client() -> TradingClient:
    require_paper_mode()
    if not ALPACA_API_KEY or not ALPACA_SECRET_KEY:
        raise RuntimeError("Alpaca paper credentials are not configured")
    return TradingClient(ALPACA_API_KEY, ALPACA_SECRET_KEY, paper=True)


def account() -> dict:
    a = client().get_account()
    return {
        "status": a.status.value if hasattr(a.status, "value") else str(a.status),
        "equity": str(a.equity),
        "cash": str(a.cash),
        "buying_power": str(a.buying_power),
        "currency": a.currency,
        "mode": "paper",
    }


def market_order(symbol: str, side: str, qty: float) -> dict:
    if side not in {"buy", "sell"}:
        raise ValueError("side must be buy or sell")
    order = MarketOrderRequest(
        symbol=symbol.upper(),
        qty=qty,
        side=OrderSide.BUY if side == "buy" else OrderSide.SELL,
        time_in_force=TimeInForce.DAY,
    )
    result = client().submit_order(order_data=order)
    return {
        "mode": "paper",
        "id": str(result.id),
        "symbol": result.symbol,
        "side": result.side.value,
        "status": result.status.value,
        "qty": str(result.qty),
    }
