from app.bot_builder.ar001 import ar001_spec, size_staged_entries


def test_ar001_catalog_is_explicit_and_unproven():
    result = ar001_spec()
    assert result["hypothesis_id"] == "AR-001"
    assert result["status"] == "UNTESTED"
    assert result["parameters"]["allocation"] == [0.25, 0.40, 0.35]
    assert result["safety"] == {"live": False, "real_money": False, "broker_orders": 0}


def test_ar001_risk_sizing_never_exceeds_budget():
    result = size_staged_entries(10_000, 0.01, [100, 95, 90], 80)
    assert result["risk_budget"] == 100
    assert result["risk_within_budget"] is True
    assert abs(result["total_stop_risk"] - 100) < 1e-8
    assert result["weighted_average_entry"] > 80
    assert result["safety"] == {"live": False, "real_money": False, "broker_orders": 0}
