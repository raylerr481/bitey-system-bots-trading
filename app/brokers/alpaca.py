from __future__ import annotations

from app.brokers.base import BrokerAccount, BrokerCapabilities, BrokerQuote
from app.services.alpaca_paper import account as paper_account
from app.services.alpaca_paper import client as paper_client
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
        client = paper_client()
        quote = client.get_latest_trade(symbol.upper())
        return BrokerQuote(
            broker=self.broker_id,
            symbol=symbol.upper(),
            bid=None,
            ask=None,
            last=float(quote.price),
            timestamp=quote.timestamp.isoformat() if quote.timestamp else None,
        )

    def submit_order(self, symbol: str, side: str, quantity: float) -> dict:
        # Deliberately delegates only to the existing paper-only implementation.
        return paper_market_order(symbol, side.lower(), quantity)
