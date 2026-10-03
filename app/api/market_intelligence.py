from __future__ import annotations

from fastapi import APIRouter
from pydantic import BaseModel, Field

from app.services.market_intelligence import analyze_market

router = APIRouter(prefix="/api/v1/sbt/market-intelligence", tags=["market-intelligence"])


class MarketIntelligenceRequest(BaseModel):
    symbol: str = Field(default="EURUSD", min_length=1, max_length=32)
    timeframe: str = Field(default="M5", min_length=2, max_length=8)
    candles: list[dict] = Field(default_factory=list, min_length=0, max_length=500)
    capital: float = Field(default=1000, gt=0)
    language: str = Field(default="es", min_length=2, max_length=5)
    event: str = Field(default="market_structure", min_length=1, max_length=120)
    evidence: list[dict] = Field(default_factory=list, max_length=50)


@router.post("/analyze")
def market_intelligence(request: MarketIntelligenceRequest):
    result = analyze_market(request.candles, request.symbol.upper(), request.timeframe.upper(), request.event)
    result["capital"] = request.capital
    result["language"] = request.language
    result["evidence_count"] = len(request.evidence)
    return result


class MarketScanRequest(BaseModel):
    symbols: list[str] = Field(default_factory=list, max_length=40)
    timeframe: str = Field(default="H1", min_length=2, max_length=4)
    limit: int = Field(default=120, ge=35, le=500)


@router.post("/scan")
async def market_scan(request: MarketScanRequest):
    """Run the same deterministic Market Intelligence contract across a bounded symbol set."""
    from app.market_sdk.registry import build_provider

    provider = build_provider()
    symbols = [symbol.strip().upper() for symbol in request.symbols if symbol.strip()]
    rows = []
    for symbol in symbols[:40]:
        try:
            candles = await provider.candles(symbol, request.timeframe.upper(), request.limit)
            result = analyze_market(
                [c.as_dict() if hasattr(c, "as_dict") else c for c in candles],
                symbol,
                request.timeframe.upper(),
                "market_scan",
            )
            rows.append({
                "symbol": symbol,
                "status": result.get("status"),
                "bias": result.get("bias", "NEUTRAL"),
                "confidence": result.get("confidence"),
                "action": result.get("hypothesis", {}).get("action", "WATCH"),
                "regime": result.get("market_pulse", {}).get("volatility", "UNKNOWN"),
                "trend": result.get("market_pulse", {}).get("trend", "UNKNOWN"),
                "momentum": result.get("market_pulse", {}).get("momentum", "UNKNOWN"),
                "contradictions": result.get("contradiction_detector", {}).get("count", 0),
                "price": result.get("last_price"),
                "research_only": True,
                "real_money": False,
            })
        except Exception as exc:
            rows.append({
                "symbol": symbol,
                "status": "unavailable",
                "bias": "NEUTRAL",
                "confidence": None,
                "action": "WAIT",
                "regime": "UNKNOWN",
                "trend": "UNKNOWN",
                "momentum": "UNKNOWN",
                "contradictions": 0,
                "price": None,
                "research_only": True,
                "real_money": False,
                "error": str(exc),
            })

    def score(row: dict) -> float:
        confidence = row.get("confidence")
        if confidence is None:
            return -1.0
        score = float(confidence) * 100.0
        score -= min(20.0, float(row.get("contradictions", 0)) * 7.0)
        if row.get("action") == "EXPERIMENT":
            score += 5.0
        return round(max(0.0, min(100.0, score)), 1)

    for row in rows:
        row["sbt_score"] = score(row)

    rows.sort(key=lambda row: row["sbt_score"], reverse=True)
    return {
        "contract": "sbt-market-scan-v1",
        "provider": getattr(provider, "name", "unknown"),
        "timeframe": request.timeframe.upper(),
        "count": len(rows),
        "rows": rows,
        "execution_enabled": False,
        "real_money": False,
    }
