from __future__ import annotations

from app.brokers.alpaca import AlpacaAdapter
from app.brokers.mt5 import MT5Adapter


ADAPTERS = {
    "alpaca": AlpacaAdapter,
    "mt5": MT5Adapter,
}


def get_adapter(broker: str):
    key = broker.strip().lower()
    try:
        return ADAPTERS[key]()
    except KeyError as exc:
        raise ValueError(f"Unsupported broker adapter: {broker}") from exc


def catalog() -> list[dict]:
    result = []
    for broker_id, adapter_cls in ADAPTERS.items():
        adapter = adapter_cls()
        capabilities = adapter.capabilities()
        result.append({
            "id": broker_id,
            "capabilities": {
                "market_data": capabilities.market_data,
                "paper": capabilities.paper,
                "demo": capabilities.demo,
                "live": capabilities.live,
                "order_submission": capabilities.order_submission,
            },
            "safe_default": "paper" if capabilities.paper else "demo" if capabilities.demo else "research",
        })
    return result
