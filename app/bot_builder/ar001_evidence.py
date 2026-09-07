from __future__ import annotations

from app.bot_builder.ar001 import backtest_ar001_ohlc, evaluate_ar001_evidence


SAFETY = {"live": False, "real_money": False, "broker_orders": 0}


def _oos_r(trades: list[dict], oos_start: int | None) -> tuple[list[float], int]:
    if not trades:
        return [], 0
    if oos_start is None:
        split_bar = max(1, int(max(t["exit_index"] for t in trades) * 0.7))
    else:
        split_bar = oos_start
    rs = [float(t["r_multiple"]) for t in trades]
    split = sum(1 for t in trades if int(t["entry_index"]) < split_bar)
    if split <= 0:
        split = max(1, len(rs) // 2)
    if split >= len(rs):
        split = len(rs) - 1
    return rs, split


def run_ar001_ohlc_evidence(
    bars: list[dict[str, float]],
    *,
    initial_capital: float = 10000,
    risk_pct: float = 0.01,
    atr_period: int = 14,
    entry_multipliers: list[float] | None = None,
    stop_atr: float = 4.0,
    take_profit_r: float = 3.0,
    direction: str = "long",
    fee_bps: float = 1.0,
    slippage_bps: float = 1.0,
    weights: list[float] | None = None,
    point_value: float = 1.0,
    max_bars_per_trade: int = 250,
    oos_start: int | None = None,
    bootstrap_samples: int = 2000,
) -> dict:
    """Run base OHLC plus deterministic cost stresses and feed OOS R directly to evidence."""
    common = dict(
        bars=bars,
        initial_capital=initial_capital,
        risk_pct=risk_pct,
        atr_period=atr_period,
        entry_multipliers=entry_multipliers,
        stop_atr=stop_atr,
        take_profit_r=take_profit_r,
        direction=direction,
        weights=weights,
        point_value=point_value,
        max_bars_per_trade=max_bars_per_trade,
    )
    base = backtest_ar001_ohlc(**common, fee_bps=fee_bps, slippage_bps=slippage_bps)
    rs, split = _oos_r(base["trades_detail"], oos_start)

    stress_runs = {
        "double_costs": backtest_ar001_ohlc(**common, fee_bps=fee_bps * 2, slippage_bps=slippage_bps * 2),
        "fee_only_2x": backtest_ar001_ohlc(**common, fee_bps=fee_bps * 2, slippage_bps=slippage_bps),
        "slippage_only_2x": backtest_ar001_ohlc(**common, fee_bps=fee_bps, slippage_bps=slippage_bps * 2),
    }
    stress_values: list[float] = []
    stress_metrics: dict[str, dict] = {}
    for name, run in stress_runs.items():
        _, stress_split = _oos_r(run["trades_detail"], oos_start)
        stress_oos = [float(t["r_multiple"]) for t in run["trades_detail"][stress_split:]]
        expectancy = sum(stress_oos) / len(stress_oos) if stress_oos else 0.0
        stress_values.append(expectancy)
        stress_metrics[name] = {"oos_trades": len(stress_oos), "oos_expectancy_R": expectancy}

    evidence = evaluate_ar001_evidence(
        rs,
        oos_start=split,
        stress_results=stress_values,
        risk_sizing_ok=True,
        bootstrap_samples=bootstrap_samples,
    )
    return {
        "contract": "sbt-ar001-ohlc-evidence-v1",
        "hypothesis_id": "AR-001",
        "data_mode": "OHLC",
        "base_backtest": base,
        "oos": {"bar_start": oos_start, "trade_split": split},
        "stress": stress_metrics,
        "evidence": evidence,
        "safety": SAFETY,
    }
