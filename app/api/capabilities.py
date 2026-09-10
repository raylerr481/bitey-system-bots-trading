from __future__ import annotations

import re
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from app.api.backtest import BacktestRequest, crossover_signal
from app.market_sdk.registry import build_provider
from app.services.backtest import run_backtest
from app.services.virtual_validation import run_virtual_validation
from app.strategies.smc import OHLC, SMCSignalRequest, smc_signal
from app.strategies.technical import TechnicalSignalRequest, technical_signal

router = APIRouter(prefix="/api/v1/capabilities", tags=["capabilities"])


class DelegationRequest(BaseModel):
    contract: str = "sbt-v1"
    capability: str = "sbt"
    message: str = Field(min_length=1, max_length=12000)
    conversation_id: str | None = None
    source: str = "bitey-web"
    mode: str = "research-only"


def _fixture_prices() -> list[float]:
    prices: list[float] = []
    price = 100.0
    for i in range(180):
        if i < 45:
            delta = 0.8
        elif i < 85:
            delta = -0.9
        elif i < 125:
            delta = 1.0
        else:
            delta = -0.7
        wiggle = ((i % 5) - 2) * 0.05
        price = round(price + delta + wiggle, 4)
        prices.append(price)
    return prices


def _fixture_ohlc(prices: list[float]) -> list[OHLC]:
    candles: list[OHLC] = []
    previous = prices[0]
    for price in prices:
        open_price = previous
        high = max(open_price, price) + 0.2
        low = min(open_price, price) - 0.2
        candles.append(OHLC(open=open_price, high=high, low=low, close=price))
        previous = price
    return candles


def _is_gold_quote_request(message: str) -> bool:
    text = message.lower()
    return bool(re.search(r"\b(oro|gold|xauusd|xau/usd)\b", text)) and bool(
        re.search(r"(cotiz|precio|valor|quote|price|mercado|hoy|actual|actualmente)", text)
    )


async def _gold_quote_result(message: str, conversation_id: str | None) -> dict:
    provider = build_provider()
    quote = await provider.quote("XAUUSD")
    return {
        "contract": "sbt-market-quote-v1",
        "capability": "sbt",
        "delegated": True,
        "delegation_status": "accepted",
        "specialization": "trading-intelligence",
        "conversation_id": conversation_id,
        "source": "bitey-sbt-market-gateway",
        "execution": {
            "live": False,
            "paper": False,
            "demo": False,
            "real_money": False,
            "broker_orders": 0,
            "risk_gate_authoritative": True,
        },
        "market_data": {
            "mode": "real",
            "instrument": "XAUUSD",
            "asset": "gold",
            "quote": quote.as_dict(),
            "timestamp": quote.timestamp,
        },
        "answer": "Bitey SBT consultó el gateway de mercado autorizado y obtuvo una cotización real de XAUUSD. No se enviaron órdenes.",
        "mode": "market-data-real",
        "message": message,
    }


def _research_result(message: str) -> dict:
    prices = _fixture_prices()
    signal = technical_signal(TechnicalSignalRequest(symbol="SYNTH", prices=prices))
    candles = _fixture_ohlc(prices)
    smc = smc_signal(SMCSignalRequest(symbol="SYNTH", candles=candles, swing_window=2))
    backtest = run_backtest(prices, lambda values, i: crossover_signal(values, i, 10, 30), initial_capital=10_000, fee_pct=0.001)
    validation = run_virtual_validation()
    return {
        "execution_status": "completed",
        "result_type": "research",
        "research": {
            "instrument": "SYNTH",
            "fixture": "synthetic-deterministic-not-market-history",
            "strategy_signal": signal,
            "smc": {"strategy": "smc-v1", "signal": smc, "structure": smc.get("structure", {}), "liquidity": smc.get("liquidity", {}), "fair_value_gaps": smc.get("fair_value_gaps", []), "order_blocks": smc.get("order_blocks", []), "research_only": True, "live": False, "real_money": False},
            "backtest": {"strategy": "sma-crossover-v1", **backtest.__dict__},
            "validation": {"validation": validation["validation"], "strategy": validation["strategy"], "return_pct": validation["return_pct"], "max_drawdown_pct": validation["max_drawdown_pct"], "closed_trades": validation["closed_trades"], "win_rate_pct": validation["win_rate_pct"], "real_money": False, "broker_orders": 0},
        },
        "answer": "SBT ejecutó investigación técnica en modo research-only: generó una señal técnica, analizó Smart Money Concepts (BOS/CHOCH, liquidez, FVG y order blocks), ejecutó un backtest determinista y verificó la estrategia con validación virtual. Los precios son sintéticos y no representan historial de mercado. No se enviaron órdenes.",
        "mode": "research-only",
        "message": message,
    }


@router.post("/delegate")
async def delegate(request: DelegationRequest):
    if request.contract != "sbt-v1" or request.capability != "sbt":
        raise HTTPException(status_code=400, detail="Invalid SBT delegation contract")

    if _is_gold_quote_request(request.message):
        return await _gold_quote_result(request.message, request.conversation_id)

    result = _research_result(request.message)
    return {
        "contract": "sbt-v1",
        "capability": "sbt",
        "delegated": True,
        "delegation_status": "accepted",
        "specialization": "trading-intelligence",
        "conversation_id": request.conversation_id,
        "source": request.source,
        "execution": {"live": False, "paper": False, "demo": False, "real_money": False, "broker_orders": 0, "risk_gate_authoritative": True},
        "next_capabilities": ["strategy", "smart-money-concepts", "backtesting", "validation", "risk-controls", "market-data"],
        "note": "SBT research completed without trading execution. Trading actions remain subject to SBT permissions and Risk Gate.",
        **result,
    }
