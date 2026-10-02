"""MT4 -> research dataset adapter.

This adapter consumes exported MT4 CSV evidence without modifying the EA.
It produces a versioned, leakage-aware research dataset for downstream
FreqAI experiments.

Contract: mt4_research_v1
- Features are present-time values only.
- Targets are explicitly separated and may reference future candles.
- Rows remain strictly chronological.
- Missing optional evidence fields are represented as null/empty values.
"""

from __future__ import annotations

import csv
import json
from dataclasses import dataclass, asdict
from datetime import datetime
from pathlib import Path
from typing import Any, Iterable


SCHEMA_VERSION = "mt4_research_v1"

ALIASES = {
    "timestamp": ("timestamp", "time", "datetime", "date"),
    "open": ("open", "open_price"),
    "high": ("high", "high_price"),
    "low": ("low", "low_price"),
    "close": ("close", "close_price"),
    "volume": ("volume", "tick_volume", "real_volume"),
    "spread": ("spread", "spread_points"),
    "strategy_score": ("strategy_score", "score", "total_score"),
    "direction": ("direction", "signal_direction"),
    "regime": ("regime", "market_regime"),
    "selected_strategy": ("selected_strategy", "strategy", "strategy_name"),
    "quality_gate": ("quality_gate", "quality_gate_result"),
    "confidence": ("confidence", "confidence_score"),
    "evidence": ("evidence", "evidence_score"),
    "virtual_decision": ("virtual_decision", "virtual_signal"),
    "signal": ("signal", "decision", "trade_signal"),
}

TARGET_COLUMNS = {
    "future_return",
    "future_max_profit",
    "future_max_loss",
    "trade_outcome",
}

REQUIRED_MARKET_COLUMNS = ("timestamp", "open", "high", "low", "close")


@dataclass(frozen=True)
class DatasetBuildConfig:
    horizon_candles: int = 12
    profit_horizon_candles: int = 12
    require_market_ohlc: bool = True


def _find(row: dict[str, Any], aliases: Iterable[str]) -> Any:
    lowered = {str(k).strip().lower(): v for k, v in row.items()}
    for key in aliases:
        if key in lowered:
            return lowered[key]
    return None


def _number(value: Any) -> float | None:
    if value is None or str(value).strip() == "":
        return None
    try:
        return float(str(value).strip().replace(",", "."))
    except (TypeError, ValueError):
        return None


def _timestamp(value: Any) -> str:
    if value is None or str(value).strip() == "":
        raise ValueError("MT4 row is missing timestamp")
    raw = str(value).strip()
    try:
        dt = datetime.fromisoformat(raw.replace("Z", "+00:00"))
        return dt.isoformat()
    except ValueError:
        # Preserve an MT4-export timestamp when it is not ISO formatted.
        return raw


def _market_row(raw: dict[str, Any]) -> dict[str, Any]:
    return {
        "timestamp": _timestamp(_find(raw, ALIASES["timestamp"])),
        "open": _number(_find(raw, ALIASES["open"])),
        "high": _number(_find(raw, ALIASES["high"])),
        "low": _number(_find(raw, ALIASES["low"])),
        "close": _number(_find(raw, ALIASES["close"])),
        "volume": _number(_find(raw, ALIASES["volume"])),
        "spread": _number(_find(raw, ALIASES["spread"])),
        "strategy_score": _number(_find(raw, ALIASES["strategy_score"])),
        "direction": _find(raw, ALIASES["direction"]),
        "regime": _find(raw, ALIASES["regime"]),
        "selected_strategy": _find(raw, ALIASES["selected_strategy"]),
        "quality_gate": _find(raw, ALIASES["quality_gate"]),
        "confidence": _number(_find(raw, ALIASES["confidence"])),
        "evidence": _number(_find(raw, ALIASES["evidence"])),
        "virtual_decision": _find(raw, ALIASES["virtual_decision"]),
        "signal": _find(raw, ALIASES["signal"]),
    }


def build_dataset(rows: list[dict[str, Any]], config: DatasetBuildConfig | None = None) -> dict[str, Any]:
    cfg = config or DatasetBuildConfig()
    normalized = [_market_row(row) for row in rows]

    if cfg.require_market_ohlc:
        for idx, row in enumerate(normalized):
            missing = [key for key in REQUIRED_MARKET_COLUMNS if row.get(key) is None]
            if missing:
                raise ValueError(f"row {idx} missing required market fields: {missing}")

    normalized.sort(key=lambda row: row["timestamp"])

    output_rows: list[dict[str, Any]] = []
    n = len(normalized)
    h = cfg.horizon_candles

    for i, row in enumerate(normalized):
        close = row["close"]
        future_close = normalized[i + h]["close"] if i + h < n else None
        future_window = normalized[i + 1 : min(n, i + 1 + cfg.profit_horizon_candles)]

        targets = {
            "future_return": (
                (future_close / close) - 1.0
                if close not in (None, 0) and future_close is not None
                else None
            ),
            "future_max_profit": (
                max((r["high"] / close) - 1.0 for r in future_window if r["high"] is not None)
                if close not in (None, 0) and future_window
                else None
            ),
            "future_max_loss": (
                min((r["low"] / close) - 1.0 for r in future_window if r["low"] is not None)
                if close not in (None, 0) and future_window
                else None
            ),
            "trade_outcome": None,
        }

        signal = str(row.get("signal") or "").upper()
        if future_close is not None and signal in {"BUY", "SELL", "LONG", "SHORT"}:
            direction = 1.0 if signal in {"BUY", "LONG"} else -1.0
            targets["trade_outcome"] = (
                1 if ((future_close / close) - 1.0) * direction > 0 else 0
            )

        features = {
            key: value
            for key, value in row.items()
            if key not in TARGET_COLUMNS and key != "timestamp"
        }

        output_rows.append({
            "schema_version": SCHEMA_VERSION,
            "timestamp": row["timestamp"],
            "features": features,
            "targets": targets,
            "source": "mt4_export",
        })

    return {
        "schema_version": SCHEMA_VERSION,
        "source": "mt4_export",
        "row_count": len(output_rows),
        "horizon_candles": cfg.horizon_candles,
        "target_columns": sorted(TARGET_COLUMNS),
        "feature_columns": sorted(
            key for key in output_rows[0]["features"]
        ) if output_rows else [],
        "rows": output_rows,
    }


def load_csv(path: str | Path) -> list[dict[str, Any]]:
    with Path(path).open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def build_dataset_from_csv(path: str | Path, config: DatasetBuildConfig | None = None) -> dict[str, Any]:
    return build_dataset(load_csv(path), config)


def write_dataset_json(path: str | Path, dataset: dict[str, Any]) -> None:
    Path(path).write_text(
        json.dumps(dataset, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )


def write_dataset_jsonl(path: str | Path, dataset: dict[str, Any]) -> None:
    with Path(path).open("w", encoding="utf-8") as handle:
        for row in dataset["rows"]:
            handle.write(json.dumps(row, ensure_ascii=False) + "\n")
