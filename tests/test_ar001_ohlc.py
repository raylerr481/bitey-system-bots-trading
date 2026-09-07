from app.bot_builder.ar001 import ar001_spec, backtest_ar001_ohlc


def make_bars(n=180):
    bars=[]
    price=100.0
    for i in range(n):
        # Repeating pullback/recovery pattern creates deterministic ATR zones.
        phase=i % 6
        if phase in (0, 1, 2): price += 0.8
        else: price -= 0.25
        close=price
        bars.append({"open": close, "high": close + 1.0, "low": close - 1.0, "close": close, "volume": 1000.0})
    return bars


def test_ar001_ohlc_contract_and_safety():
    result=backtest_ar001_ohlc(make_bars(), initial_capital=10000, risk_pct=0.01, atr_period=14, fee_bps=1, slippage_bps=1)
    assert result["contract"] == "sbt-ar001-ohlc-v1"
    assert result["hypothesis_id"] == "AR-001"
    assert result["safety"] == {"live":False,"real_money":False,"broker_orders":0}
    assert result["trades"] >= 1
    assert "mean_mae_pct" in result and "mean_mfe_pct" in result
    assert result["fee_bps"] == 1
    assert result["slippage_bps"] == 1


def test_ar001_spec_exposes_real_backtest_protocol():
    spec=ar001_spec()
    assert spec["backtest_contract"] == "sbt-ar001-ohlc-v1"
    assert spec["parameters"]["allocation"] == [0.25,0.40,0.35]
    assert spec["evidence_protocol"]["minimum_trades"] == 100
