from app.quant.regime_lab import catalog, run_regime_lab


def synthetic_bars(n=260):
    bars=[]
    price=100.0
    for i in range(n):
        drift = 0.45 if (i // 10) % 2 == 0 else -0.30
        close = price + drift
        high = max(price, close) + 0.8
        low = min(price, close) - 0.8
        bars.append({"open": price, "high": high, "low": low, "close": close, "volume": 1000 + (i % 17) * 10})
        price = close
    return bars


def test_catalog_exposes_pipeline_and_safety():
    result = catalog()
    assert result["pipeline"] == ["thesis", "hypothesis", "quant_features", "hmm_regimes", "ohlc_backtest", "oos", "stress", "evidence"]
    assert result["safety"] == {"live": False, "real_money": False, "broker_orders": 0}


def test_integrated_pipeline_runs_end_to_end():
    result = run_regime_lab(synthetic_bars(), oos_start=170, fee_bps=1.0, slippage_bps=1.0)
    assert result["contract"] == "sbt-regime-lab-v1"
    assert result["hmm"]["states"] >= 2
    assert result["backtest"]["trades"] > 0
    assert result["stress"]
    assert result["evidence"]["hypothesis_id"] == "AR-001"
    assert result["methodology"]["lookahead_safe_adaptive_selection"] is False
    assert result["safety"] == {"live": False, "real_money": False, "broker_orders": 0}
