from app.quant.hmm import analyze_regimes


def synthetic_bars(n=180):
    bars=[]
    price=100.0
    for i in range(n):
        drift = 0.55 if (i // 30) % 2 == 0 else -0.45
        close = price + drift + (0.15 if i % 7 == 0 else 0.0)
        high = max(price, close) + 0.8
        low = min(price, close) - 0.8
        volume = 1000 + (i % 11) * 50
        bars.append({"open": price, "high": high, "low": low, "close": close, "volume": volume})
        price = close
    return bars


def test_hmm_contract_and_safety():
    result = analyze_regimes(synthetic_bars(), states=3, window=20, seed=7)
    assert result["contract"] == "sbt-hmm-regime-v1"
    assert result["states"] == 3
    assert len(result["regime_summary"]) == 3
    assert len(result["transition_matrix"]) == 3
    assert result["safety"] == {"live": False, "real_money": False, "broker_orders": 0}


def test_hmm_auto_selects_valid_state_count():
    result = analyze_regimes(synthetic_bars(), states="auto", window=20, seed=7)
    assert 2 <= result["states"] <= 5
    assert sum(x["observations"] for x in result["regime_summary"]) == len(result["state_labels"])
