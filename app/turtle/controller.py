from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Any

from .spec import CORRECTIONS, TURTLE_V122_BASELINE, baseline_dict


@dataclass(frozen=True)
class Diagnosis:
    contract: str
    status: str
    findings: list[dict[str, Any]]
    automatic_corrections: list[str]
    blocked_changes: list[str]
    validation_gates: list[str]


class TurtleController:
    """Bounded controller for MT4 Turtle v1.22.

    This controller does not invent strategy changes. It compares observed
    implementation evidence with the immutable reference contract.
    """

    def baseline(self) -> dict[str, Any]:
        return baseline_dict()

    def diagnose(self, evidence: dict[str, Any]) -> dict[str, Any]:
        findings: list[dict[str, Any]] = []
        automatic: list[str] = []
        blocked: list[str] = []

        issues = set(str(x) for x in evidence.get("issues", []))
        config = evidence.get("config") or {}

        if "mixed_exit_systems" in issues:
            findings.append(asdict(CORRECTIONS["mixed_exit_systems"]))
            automatic.append("TURTLE-C001")

        if "pyramid_loses_campaign_identity" in issues:
            findings.append(asdict(CORRECTIONS["pyramid_loses_campaign_identity"]))
            automatic.append("TURTLE-C002")

        if "dynamic_n" in issues:
            findings.append(asdict(CORRECTIONS["dynamic_n"]))
            automatic.append("TURTLE-C003")

        if "extra_filter" in issues:
            findings.append(asdict(CORRECTIONS["extra_filter"]))
            automatic.append("TURTLE-C004")

        if "parameter_optimization" in issues:
            findings.append(asdict(CORRECTIONS["parameter_optimization"]))
            automatic.append("TURTLE-C005")

        for key, expected in (
            ("system_1_entry_days", 20),
            ("system_1_exit_days", 10),
            ("system_2_entry_days", 55),
            ("system_2_exit_days", 20),
            ("atr_period", 20),
            ("max_units", 4),
        ):
            if key in config and config[key] != expected:
                blocked.append(f"{key}={config[key]} differs from classic baseline {expected}")

        if any("differs from classic baseline" in x for x in blocked):
            status = "BLOCKED_CLASSIC_BASELINE"
        elif findings:
            status = "CORRECTION_READY"
        else:
            status = "HEALTHY"

        return asdict(Diagnosis(
            contract=TURTLE_V122_BASELINE.contract,
            status=status,
            findings=findings,
            automatic_corrections=automatic,
            blocked_changes=blocked,
            validation_gates=[
                "compile_errors_zero",
                "classic_parameters_unchanged",
                "backtest_completed",
                "risk_gate_passed",
                "no_live_orders",
            ],
        ))

    def correction_plan(self, diagnosis: dict[str, Any]) -> dict[str, Any]:
        if diagnosis.get("status") == "BLOCKED_CLASSIC_BASELINE":
            return {
                "allowed": False,
                "mode": "classic-validation",
                "reason": "Baseline parameters changed; optimization is locked.",
                "actions": [],
            }

        actions = []
        for finding in diagnosis.get("findings", []):
            actions.append({
                "correction_id": finding["id"],
                "action": finding["action"],
                "automatic": bool(finding.get("safe_automatic")),
                "requires_compile": True,
                "requires_backtest": True,
            })

        return {
            "allowed": True,
            "mode": "classic-validation",
            "dry_run": True,
            "actions": actions,
            "next_step": "apply_only_after_compile_and_backtest_gate",
        }

    def validate_result(self, result: dict[str, Any]) -> dict[str, Any]:
        checks = {
            "compile_errors_zero": int(result.get("compile_errors", 1)) == 0,
            "classic_parameters_unchanged": bool(result.get("classic_parameters_unchanged", False)),
            "backtest_completed": bool(result.get("backtest_completed", False)),
            "risk_gate_passed": bool(result.get("risk_gate_passed", False)),
            "no_live_orders": int(result.get("live_orders", 0)) == 0,
        }
        passed = all(checks.values())
        return {
            "contract": TURTLE_V122_BASELINE.contract,
            "status": "APPROVED" if passed else "REJECTED",
            "checks": checks,
            "apply_allowed": passed,
            "live_execution": False,
        }
