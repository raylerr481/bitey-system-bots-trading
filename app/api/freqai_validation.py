from __future__ import annotations

from typing import Any

from fastapi import APIRouter
from pydantic import BaseModel, Field

from app.services.freqai_validation_passport import (
    PassportThresholds,
    build_freqai_validation_passport,
)

router = APIRouter(prefix="/api/v1/validation/freqai", tags=["validation", "freqai"])


class FreqAIValidationEvidence(BaseModel):
    data_present: bool = False
    backtest_present: bool = False
    metrics_present: bool = False
    closed_trades: int = Field(default=0, ge=0)
    test_samples: int = Field(default=0, ge=0)
    prediction_coverage_pct: float = Field(default=0.0, ge=0, le=100)
    max_drawdown_pct: float = Field(default=100.0, ge=0)
    lookahead_bias_count: int = Field(default=0, ge=0)
    dry_run: bool = False
    identifier: str | None = None
    strategy: str | None = None
    model: str | None = None
    timerange: str | None = None
    metrics: dict[str, Any] = {}


@router.post("/passport")
def create_passport(evidence: FreqAIValidationEvidence):
    return build_freqai_validation_passport(evidence.model_dump(), PassportThresholds())


@router.get("/contract")
def passport_contract():
    return {
        "passport_version": "1.0",
        "pipeline": ["data", "backtest", "freqai_predictions", "metrics", "validation", "risk_gate"],
        "real_money": False,
        "live_trading_enabled": False,
        "broker_orders": 0,
        "thresholds": {
            "min_trades": 30,
            "min_test_samples": 100,
            "min_prediction_coverage_pct": 70.0,
            "max_drawdown_pct": 20.0,
            "max_lookahead_bias_count": 0,
            "require_dry_run": True,
        },
    }


class FreqAIArtifactEvidence(BaseModel):
    backtest_report: dict[str, Any]
    prediction_artifact: dict[str, Any] | None = None
    lookahead_artifact: dict[str, Any] | None = None
    data_present: bool = True
    dry_run: bool = True
    identifier: str | None = None
    strategy: str | None = None
    model: str | None = None
    timerange: str | None = None


@router.post("/passport/from-artifacts")
def create_passport_from_artifacts(evidence: FreqAIArtifactEvidence):
    from app.services.freqai_artifact_adapter import build_evidence_from_artifacts
    derived = build_evidence_from_artifacts(
        evidence.backtest_report,
        prediction_artifact=evidence.prediction_artifact,
        lookahead_artifact=evidence.lookahead_artifact,
        data_present=evidence.data_present,
        dry_run=evidence.dry_run,
        identifier=evidence.identifier,
        strategy=evidence.strategy,
        model=evidence.model,
        timerange=evidence.timerange,
    )
    passport = build_freqai_validation_passport(derived, PassportThresholds())
    passport["evidence"]["artifact_source"] = derived["artifact_source"]
    return passport
