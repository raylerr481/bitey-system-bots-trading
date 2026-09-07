from __future__ import annotations

from app.bot_builder.ar001_evidence import run_ar001_ohlc_evidence
from app.quant.hmm import analyze_regimes

SAFETY = {"live": False, "real_money": False, "broker_orders": 0}

CATALOG = {
    "contract": "sbt-regime-lab-v1",
    "pipeline": ["thesis", "hypothesis", "quant_features", "hmm_regimes", "ohlc_backtest", "oos", "stress", "evidence"],
    "strategies": [
        {"id": "AR-001", "name": "ATR staged entry 25/40/35", "status": "source_inspired_unvalidated", "engine": "ar001_ohlc"},
    ],
    "data": "OHLCV",
    "notes": [
        "HMM identifies statistical regimes; it does not invent alpha.",
        "Regime labels are descriptive in this first integrated milestone.",
        "Adaptive strategy selection requires walk-forward HMM training and is kept separate from full-sample descriptive analysis.",
    ],
    "safety": SAFETY,
}


def catalog() -> dict:
    return CATALOG


def run_regime_lab(
    bars: list[dict[str, float]],
    *,
    strategy_id: str = "AR-001",
    states: int | str = "auto",
    window: int = 20,
    seed: int = 7,
    initial_capital: float = 10000,
    risk_pct: float = 0.01,
    fee_bps: float = 1.0,
    slippage_bps: float = 1.0,
    direction: str = "long",
    oos_start: int | None = None,
    bootstrap_samples: int = 2000,
) -> dict:
    if strategy_id != "AR-001":
        raise ValueError("Only AR-001 is enabled in the first integrated regime-lab milestone")
    if len(bars) < 100:
        raise ValueError("Regime Lab requires at least 100 OHLC bars")

    regimes = analyze_regimes(bars, states=states, window=window, seed=seed)
    evidence = run_ar001_ohlc_evidence(
        bars,
        initial_capital=initial_capital,
        risk_pct=risk_pct,
        direction=direction,
        fee_bps=fee_bps,
        slippage_bps=slippage_bps,
        oos_start=oos_start,
        bootstrap_samples=bootstrap_samples,
    )

    # Attribute already executed research trades to the HMM state at entry.
    # This is intentionally descriptive and does not feed future information back into execution.
    labels = regimes["state_labels"]
    by_state: dict[str, dict] = {}
    for trade in evidence["base_backtest"]["trades_detail"]:
        idx = int(trade["entry_index"])
        state = int(labels[min(max(idx - 1, 0), len(labels) - 1)])
        row = by_state.setdefault(str(state), {"state": state, "trades": 0, "r": []})
        row["trades"] += 1
        row["r"].append(float(trade["r_multiple"]))
    for row in by_state.values():
        rs = row.pop("r")
        row["expectancy_R"] = sum(rs) / len(rs) if rs else 0.0
        row["positive_trades"] = sum(1 for x in rs if x > 0)
        row["win_rate"] = row["positive_trades"] / len(rs) if rs else None

    return {
        "contract": "sbt-regime-lab-v1",
        "strategy": {"id": strategy_id, "status": "source_inspired_unvalidated"},
        "hmm": regimes,
        "regime_trade_attribution": sorted(by_state.values(), key=lambda x: x["state"]),
        "backtest": evidence["base_backtest"],
        "oos": evidence["oos"],
        "stress": evidence["stress"],
        "evidence": evidence["evidence"],
        "methodology": {
            "regime_mode": "descriptive_full_sample",
            "lookahead_safe_adaptive_selection": False,
            "next_milestone": "walk_forward_hmm_strategy_selection",
        },
        "safety": SAFETY,
    }
