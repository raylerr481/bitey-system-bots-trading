from app.quant.regime_walkforward import run_walk_forward_regime_lab


def bars(n=220):
    out=[]; p=100.0
    for i in range(n):
        drift=0.45 if (i//10)%2==0 else -0.30
        c=p+drift
        out.append({"open":p,"high":max(p,c)+0.8,"low":min(p,c)-0.8,"close":c,"volume":1000+i})
        p=c
    return out


def test_walk_forward_is_lookahead_safe_and_research_only():
    r=run_walk_forward_regime_lab(bars())
    assert r["contract"] == "sbt-regime-walk-forward-v1"
    assert r["folds"]
    assert r["methodology"]["lookahead_safe"] is True
    assert r["methodology"]["oos_untouched"] is True
    assert r["safety"] == {"live":False,"real_money":False,"broker_orders":0}
    assert all("enabled_states" in f for f in r["folds"])


def test_walk_forward_has_no_free_parameter_optimization():
    r=run_walk_forward_regime_lab(bars(), states=3)
    assert r["methodology"]["strategy_selection"] == "train_only_positive_expectancy_by_regime"
    assert all(f["states"] == 3 for f in r["folds"])
