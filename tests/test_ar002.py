from app.bot_builder.ar002 import ar002_spec, detect_liquidity_events, liquidity_signal_backtest


def _bars():
    bars = []
    # Deterministic oscillation with a clear high/low and a later rejection sweep.
    closes = [100, 101, 102, 101, 100, 99, 100, 101, 102, 101, 100, 99, 100, 101, 102, 101, 100, 99, 100, 101, 102, 101, 100, 99, 100, 101, 102, 101, 100, 99, 100, 101, 102, 101, 100, 99, 100, 101, 102, 101, 100, 99, 100, 101, 102, 101, 100, 99, 100, 101, 102, 101, 100, 99, 100, 101]
    for i, c in enumerate(closes):
        bars.append({"open": c, "high": c + 0.4, "low": c - 0.4, "close": c, "volume": 1000 + i})
    # Sweep a prior swing high and close back below it.
    bars[30] = {"open": 100.0, "high": 103.0, "low": 99.5, "close": 100.5, "volume": 2500}
    return bars


def test_ar002_contract_is_falsifiable_and_safe():
    spec = ar002_spec()
    assert spec["hypothesis_id"] == "AR-002"
    assert spec["status"] == "UNTESTED"
    assert spec["safety"] == {"live": False, "real_money": False, "broker_orders": 0}
    assert any("out-of-sample" in x for x in spec["falsification"])


def test_ar002_detects_only_observable_proxies():
    events = detect_liquidity_events(_bars())
    assert isinstance(events, list)
    assert any(e["type"] in {"buy_side_liquidity", "sell_side_liquidity"} for e in events)
    assert all("source" in e for e in events)


def test_ar002_event_study_is_not_a_trading_executor():
    result = liquidity_signal_backtest(_bars(), horizon=5)
    assert result["contract"] == "sbt-ar002-event-study-v1"
    assert result["data_mode"] == "OHLCV_proxy"
    assert result["safety"] == {"live": False, "real_money": False, "broker_orders": 0}
