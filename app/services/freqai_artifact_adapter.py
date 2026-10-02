"""Normalize real Freqtrade/FreqAI artifacts into Validation Passport evidence.

The adapter intentionally reads exported research artifacts. It does not accept
manually-entered performance metrics as its primary input.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any
import json
import zipfile


def _number(value: Any, default: float = 0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _first(mapping: dict[str, Any], *keys: str, default: Any = None) -> Any:
    for key in keys:
        if key in mapping and mapping[key] is not None:
            return mapping[key]
    return default


def _extract_report_metrics(report: dict[str, Any]) -> tuple[int, float, dict[str, Any]]:
    """Extract trades/drawdown/metrics from common Freqtrade report shapes."""
    strategy = report.get("strategy") if isinstance(report.get("strategy"), dict) else {}
    total = report.get("total") if isinstance(report.get("total"), dict) else {}

    trades = int(
        _number(
            _first(
                strategy,
                "total_trades",
                "trade_count",
                "trades",
                default=_first(total, "total_trades", "trade_count", default=0),
            )
        )
    )
    drawdown = _number(
        _first(
            strategy,
            "max_drawdown",
            "max_drawdown_abs",
            "max_drawdown_pct",
            default=_first(total, "max_drawdown", "max_drawdown_abs", "max_drawdown_pct", default=100.0),
        ),
        100.0,
    )
    # Freqtrade can expose drawdown as a ratio/percentage depending on the
    # artifact/version. Prefer explicit percentage keys when available.
    if "max_drawdown" in strategy and "max_drawdown_pct" not in strategy:
        raw = _number(strategy["max_drawdown"])
        drawdown = raw * 100.0 if 0 <= raw <= 1 else raw

    metrics = dict(strategy or total)
    return trades, max(0.0, drawdown), metrics


def load_json_artifact(path: str | Path) -> dict[str, Any]:
    """Load a JSON artifact produced by Freqtrade/FreqAI.

    Freqtrade may package modern backtest exports as ZIP files. In that case
    the first JSON report inside the archive is used.
    """
    source = Path(path)
    if source.suffix.lower() == ".zip":
        with zipfile.ZipFile(source) as archive:
            candidates = [name for name in archive.namelist() if name.lower().endswith(".json")]
            if not candidates:
                raise ValueError(f"No JSON report found in {source}")
            with archive.open(candidates[0]) as handle:
                return json.loads(handle.read().decode("utf-8"))
    return json.loads(source.read_text(encoding="utf-8"))


def build_evidence_from_artifacts(
    backtest_report: dict[str, Any],
    *,
    prediction_artifact: dict[str, Any] | None = None,
    lookahead_artifact: dict[str, Any] | None = None,
    data_present: bool = True,
    dry_run: bool = True,
    identifier: str | None = None,
    strategy: str | None = None,
    model: str | None = None,
    timerange: str | None = None,
) -> dict[str, Any]:
    """Derive Passport evidence from actual exported artifacts.

    Prediction coverage is calculated from prediction artifact counts:
    predicted_rows / eligible_rows * 100. Lookahead is read from the
    lookahead-analysis artifact. No performance metric is supplied manually.
    """
    trades, drawdown, metrics = _extract_report_metrics(backtest_report)

    predictions = prediction_artifact or {}
    eligible = int(_number(_first(predictions, "eligible_rows", "test_samples", "rows", default=0)))
    predicted = int(_number(_first(predictions, "predicted_rows", "prediction_rows", default=0)))
    coverage = (predicted / eligible * 100.0) if eligible > 0 else 0.0

    lookahead = lookahead_artifact or {}
    bias_count = int(
        _number(
            _first(
                lookahead,
                "lookahead_bias_count",
                "biased_rows",
                "bias_count",
                default=0,
            )
        )
    )

    return {
        "data_present": data_present,
        "backtest_present": bool(backtest_report),
        "metrics_present": bool(metrics),
        "closed_trades": trades,
        "test_samples": eligible,
        "prediction_coverage_pct": round(coverage, 4),
        "max_drawdown_pct": round(drawdown, 4),
        "lookahead_bias_count": bias_count,
        "dry_run": dry_run,
        "identifier": identifier,
        "strategy": strategy,
        "model": model,
        "timerange": timerange,
        "metrics": metrics,
        "artifact_source": {
            "backtest": "freqtrade-backtest-export",
            "predictions": "freqai-prediction-export" if prediction_artifact else None,
            "lookahead": "freqtrade-lookahead-analysis" if lookahead_artifact else None,
        },
    }
