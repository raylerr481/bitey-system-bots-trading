from __future__ import annotations

from typing import Any

from fastapi import APIRouter
from pydantic import BaseModel

from app.services.freqai_artifact_adapter import build_evidence_from_artifacts
from app.services.freqai_validation_passport import PassportThresholds, build_freqai_validation_passport

router = APIRouter(
    prefix="/api/v1/validation/freqai-artifacts",
    tags=["validation", "freqai"],
)


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


@router.post("/passport")
def create_passport_from_artifacts(evidence: FreqAIArtifactEvidence):
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
