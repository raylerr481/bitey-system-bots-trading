import pytest

from app.services.mt5_market_data import MT5MarketData, MT5MarketDataError


@pytest.mark.asyncio
async def test_empty_bridge_is_rejected():
    service = MT5MarketData("")
    with pytest.raises(MT5MarketDataError, match="not configured"):
        await service.quote("EURUSD")


@pytest.mark.asyncio
async def test_candles_validate_count():
    service = MT5MarketData("http://localhost:9999")
    with pytest.raises(MT5MarketDataError, match="count"):
        await service.candles("EURUSD", count=0)
