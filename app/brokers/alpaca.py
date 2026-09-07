from __future__ import annotations

from alpaca.data.historical import StockHistoricalDataClient
from alpaca.data.requests import StockLatestQuoteRequest

from app.brokers.base import BrokerAccount, BrokerCapabilities, BrokerQuote
from app.core.settings import ALPACA_API_KEY, ALPACA_SECRET_KEY
from app.services.alpaca_paper import account as paper_account
from app.services.alpaca_paper import market_order as paper_market_order


class AlpacaAdapter:
    broker_id = "alpaca"

    def capabilities(self) -> BrokerCapabilities:
        return BrokerCapabilities(
            market_data=True,
            paper=True,
            demo=False,
            live=False,
            order_submission=True,
        )

    def account(self) -> BrokerAccount:
        data = paper_account()
        return BrokerAccount(
            broker=self.broker_id,
            mode="paper",
            status=data["status"],
            equity=data.get("equity"),
            cash=data.get("cash"),
            currency=data.get("currency"),
        )

    def quote(self, symbol: str) -> BrokerQuote:
        if not ALPACA_API_KEY or not ALPACA_SECRET_KEY:
            raise RuntimeError("Alpaca paper credentials are not configured")
        data_client = StockHistoricalDataClient(ALPACA_API_KEY, ALPACA_SECRET_KEY)
        result = data_client.get_stock_latest_quote(
            StockLatestQuoteRequest(symbol_or_symbols=symbol.upper())
        )[symbol.upper()]
        return BrokerQuote(
            broker=self.broker_id,
            symbol=symbol.upper(),
            bid=float(result.bid_price),
            ask=float(result.ask_price),
            last=None,
            timestamp=result.timestamp.isoformat() if result.timestamp else None,
        )

    def submit_order(self, symbol: str, side: str, quantity: float) -> dict:
        # Deliberately delegates only to the existing paper-only implementation.
        return paper_market_order(symbol, side.lower(), quantity)
