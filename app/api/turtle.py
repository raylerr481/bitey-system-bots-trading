from __future__ import annotations

from typing import Any

from fastapi import APIRouter
from pydantic import BaseModel, Field

from app.turtle import TurtleController

router = APIRouter(prefix="/api/v1/turtle", tags=["turtle-bitey"])
controller = TurtleController()
_latest_diagnosis: dict[str, Any] | None = None


class TurtleEvidence(BaseModel):
    issues: list[str] = Field(default_factory=list, max_length=32)
    config: dict[str, Any] = Field(default_factory=dict)
    metrics: dict[str, Any] = Field(default_factory=dict)
    source: str = "mt4"


class TurtleValidation(BaseModel):
    compile_errors: int = 1
    classic_parameters_unchanged: bool = False
    backtest_completed: bool = False
    risk_gate_passed: bool = False
    live_orders: int = 0


@router.get("/status")
def status() -> dict[str, Any]:
    return {
        "module": "Bitey SBT Turtle Controller",
        "contract": "classic-turtle-mt4-v1.22",
        "state": "READY",
        "automation": "bounded",
        "live_execution": False,
        "optimization_locked": True,
        "baseline": controller.baseline(),
        "latest_diagnosis": _latest_diagnosis,
    }


@router.get("/baseline")
def baseline() -> dict[str, Any]:
    return controller.baseline()


@router.post("/diagnose")
def diagnose(evidence: TurtleEvidence) -> dict[str, Any]:
    global _latest_diagnosis
    _latest_diagnosis = controller.diagnose(evidence.model_dump())
    return _latest_diagnosis


@router.post("/autocorrect/plan")
def autocorrect_plan(evidence: TurtleEvidence) -> dict[str, Any]:
    diagnosis = controller.diagnose(evidence.model_dump())
    return {
        "diagnosis": diagnosis,
        "plan": controller.correction_plan(diagnosis),
    }


@router.post("/autocorrect/validate")
def autocorrect_validate(result: TurtleValidation) -> dict[str, Any]:
    return controller.validate_result(result.model_dump())
