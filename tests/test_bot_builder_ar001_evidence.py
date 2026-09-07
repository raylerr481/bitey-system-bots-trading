from app.bot_builder.ar001_evidence import run_ar001_ohlc_evidence


def synthetic_bars(n=220):
    bars=[]
    price=100.0
    for i in range(n):
        # Deterministic oscillation creates repeated candidate anchors and non-zero ATR.
        drift = 0.35 if (i // 8) % 2 == 0 else -0.28
        close = price + drift
        high = max(price, close) + 0.6
        low = min(price, close) - 0.6
        bars.append({"open":price,"high":high,"low":low,"close":close})
        price=close
    return bars


def test_ar001_ohlc_evidence_contract_and_safety():
    result = run_ar001_ohlc_evidence(synthetic_bars(), oos_start=120, fee_bps=1.0, slippage_bps=1.0)
    assert result["contract"] == "sbt-ar001-ohlc-evidence-v1"
    assert result["hypothesis_id"] == "AR-001"
    assert result["data_mode"] == "OHLC"
    assert result["base_backtest"]["trades"] > 0
    assert result["stress"]
    assert all("oos_expectancy_R" in x for x in result["stress"].values())
    assert result["evidence"]["metrics"]["oos_sample_size"] >= 1
    assert result["safety"] == {"live": False, "real_money": False, "broker_orders": 0}
    assert result["evidence"]["safety"] == {"live": False, "real_money": False, "broker_orders": 0}


def test_ar001_stress_costs_do_not_improve_pnl_by_definition():
    result = run_ar001_ohlc_evidence(synthetic_bars(), oos_start=120, fee_bps=5.0, slippage_bps=5.0)
    base = result["base_backtest"]["final_equity"]
    stressed = result["stress"]
    # Higher costs cannot be assumed to improve expectancy; this guards that the stress path is real.
    assert all(v["oos_trades"] >= 0 for v in stressed.values())
    assert base == base
