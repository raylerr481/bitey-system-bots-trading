"""Deterministic Turtle baseline specification.

This module contains strategy-contract metadata only. It does not execute
orders and must remain aligned with the approved classic Turtle baseline.
"""

TURTLE_V122_BASELINE = {
    "version": "1.22",
    "systems": {
        "S1": {
            "entry_days": 20,
            "exit_days": 10,
        },
        "S2": {
            "entry_days": 55,
            "exit_days": 20,
        },
    },
    "n_period": 20,
    "stop_n": 2.0,
    "pyramid_n": 0.5,
    "max_units": 4,
    "risk_per_unit_pct": 0.5,
    "s1_skip_rule": True,
    "campaign_stop": False,
    "classic_only": True,
    "execution_enabled": False,
}
