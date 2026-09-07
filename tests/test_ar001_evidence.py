from app.bot_builder.ar001 import evaluate_ar001_evidence, size_staged_entries


def test_ar001_sizing_respects_total_risk_budget():
    result = size_staged_entries(10000, 0.01, [100.0, 95.0, 90.0], 80.0)
    assert result["risk_budget"] == 100.0
    assert result["risk_within_budget"] is True
    assert abs(result["total_stop_risk"] - 100.0) < 1e-8


def test_ar001_insufficient_without_minimum_oos_sample():
    result = evaluate_ar001_evidence([0.1] * 20, oos_start=10, stress_results=[0.1])
    assert result["status"] == "EVIDENCE_INSUFFICIENT"


def test_ar001_rejects_negative_oos_expectancy_with_enough_data():
    # 100 trades, 60 in-sample and 40 OOS; costs are assumed already included.
    results = [0.05] * 60 + [-0.02] * 40
    result = evaluate_ar001_evidence(results, oos_start=60, stress_results=[-0.01, 0.01])
    assert result["status"] == "REJECTED"
    assert result["metrics"]["oos_expectancy_R"] < 0


def test_ar001_can_approve_strong_supplied_evidence():
    results = [0.02] * 70 + [0.04] * 30
    result = evaluate_ar001_evidence(results, oos_start=70, stress_results=[0.01, 0.02, 0.03])
    assert result["status"] == "APPROVED"
    assert result["metrics"]["oos_expectancy_R"] > 0
    assert result["metrics"]["bootstrap_95_lower_bound_R"] > 0
