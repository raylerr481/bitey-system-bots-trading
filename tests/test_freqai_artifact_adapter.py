from app.services.freqai_artifact_adapter import build_evidence_from_artifacts


def test_derives_passport_evidence_from_real_artifact_shapes():
    evidence = build_evidence_from_artifacts(
        {
            "strategy": {
                "total_trades": 42,
                "max_drawdown_pct": 8.5,
                "profit_total": 12.3,
            }
        },
        prediction_artifact={"eligible_rows": 200, "predicted_rows": 180},
        lookahead_artifact={"lookahead_bias_count": 0},
        dry_run=True,
        identifier="bitey-freqai-v1",
        strategy="BiteyFreqAI_v1",
        model="LightGBMRegressor",
        timerange="20260901-20261001",
    )

    assert evidence["closed_trades"] == 42
    assert evidence["max_drawdown_pct"] == 8.5
    assert evidence["test_samples"] == 200
    assert evidence["prediction_coverage_pct"] == 90.0
    assert evidence["lookahead_bias_count"] == 0
    assert evidence["artifact_source"]["backtest"] == "freqtrade-backtest-export"


def test_missing_predictions_cannot_fake_coverage():
    evidence = build_evidence_from_artifacts(
        {"strategy": {"total_trades": 42, "max_drawdown_pct": 8.5}},
        dry_run=True,
    )

    assert evidence["prediction_coverage_pct"] == 0.0
    assert evidence["test_samples"] == 0
