from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Any


@dataclass(frozen=True)
class TurtleBaseline:
    contract: str = "classic-turtle-mt4-v1.22"
    system_1_entry_days: int = 20
    system_1_exit_days: int = 10
    system_2_entry_days: int = 55
    system_2_exit_days: int = 20
    atr_period: int = 20
    stop_n: float = 2.0
    pyramid_n: float = 0.5
    max_units: int = 4
    timeframe: str = "D1"
    one_campaign_at_a_time: bool = True
    ai_filters_allowed: bool = False
    optimization_allowed: bool = False


TURTLE_V122_BASELINE = TurtleBaseline()


@dataclass(frozen=True)
class TurtleCorrection:
    id: str
    severity: str
    title: str
    reason: str
    action: str
    safe_automatic: bool


CORRECTIONS = {
    "mixed_exit_systems": TurtleCorrection(
        "TURTLE-C001", "high",
        "Separate S1 and S2 exits",
        "A campaign must exit using the exit channel belonging to its entry system.",
        "Track campaign_system and use S1 10D or S2 20D exclusively.",
        True,
    ),
    "pyramid_loses_campaign_identity": TurtleCorrection(
        "TURTLE-C002", "high",
        "Preserve campaign identity during pyramiding",
        "Pyramid orders must inherit the active campaign system and direction.",
        "Pass campaign_system/campaign_direction into every pyramid order.",
        True,
    ),
    "dynamic_n": TurtleCorrection(
        "TURTLE-C003", "medium",
        "Freeze N at campaign start",
        "Initial N is the campaign risk unit for stops and 0.5N additions.",
        "Capture N when the campaign starts and reuse it for all units.",
        True,
    ),
    "extra_filter": TurtleCorrection(
        "TURTLE-C004", "high",
        "Remove non-classic entry filter",
        "Extra RSI/EMA/ADX or synthetic breakout filters alter the reference system.",
        "Return to the closed-bar Donchian breakout contract.",
        True,
    ),
    "parameter_optimization": TurtleCorrection(
        "TURTLE-C005", "high",
        "Block optimization before validation",
        "Changing 20/10, 55/20, 2N or 0.5N before baseline validation risks overfitting.",
        "Keep v1.22 parameters immutable in the classic-validation stage.",
        True,
    ),
}


def baseline_dict() -> dict[str, Any]:
    return asdict(TURTLE_V122_BASELINE)


def correction_dict(key: str) -> dict[str, Any] | None:
    item = CORRECTIONS.get(key)
    return asdict(item) if item else None
