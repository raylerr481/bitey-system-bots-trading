from __future__ import annotations

import math
from app.bot_builder.ar001 import backtest_ar001_ohlc
from app.quant.hmm import _features, _log_gaussian, fit_gaussian_hmm

SAFETY = {"live": False, "real_money": False, "broker_orders": 0}


def _classify(features, model):
    logp = _log_gaussian(features, model["means"], model["stds"])
    return logp.argmax(axis=1).tolist()


def _state_stats(trades, labels, offset=0):
    out = {}
    for t in trades:
        idx = int(t["entry_index"]) + offset
        if not labels:
            continue
        s = int(labels[min(max(int(t["entry_index"]), 0), len(labels) - 1)])
        row = out.setdefault(s, [])
        row.append(float(t["r_multiple"]))
    return {s: {"trades": len(rs), "expectancy_R": sum(rs) / len(rs) if rs else 0.0,
                 "positive": sum(x > 0 for x in rs),
                 "win_rate": sum(x > 0 for x in rs) / len(rs) if rs else None}
            for s, rs in out.items()}


def run_walk_forward_regime_lab(
    bars: list[dict[str, float]], *, strategy_id: str = "AR-001", states: int | str = "auto",
    window: int = 20, seed: int = 7, initial_capital: float = 10000, risk_pct: float = 0.01,
    fee_bps: float = 1.0, slippage_bps: float = 1.0, direction: str = "long",
    train_pct: float = 0.60, test_pct: float = 0.10, min_state_trades: int = 5,
) -> dict:
    if strategy_id != "AR-001":
        raise ValueError("Only AR-001 is enabled in the first walk-forward milestone")
    if len(bars) < 160:
        raise ValueError("Walk-forward Regime Lab requires at least 160 OHLC bars")
    if not 0.5 <= train_pct < 0.8 or not 0.05 <= test_pct <= 0.25:
        raise ValueError("invalid train/test proportions")

    n = len(bars); train_end = max(100, int(n * train_pct)); step = max(20, int(n * test_pct))
    folds = []; all_oos = []; all_baseline = []
    start = train_end
    fold_no = 0
    while start < n:
        test_end = min(n, start + step)
        if test_end - start < 20: break
        train = bars[:start]; test = bars[start:test_end]
        train_features = _features(train, window)
        if states == "auto":
            candidates = [k for k in (2, 3, 4, 5) if len(train_features) >= k * 15]
            chosen = min(candidates, key=lambda k: _bic(train_features, fit_gaussian_hmm(train_features, k, 35, seed + fold_no))) if candidates else 2
        else:
            chosen = int(states)
        model = fit_gaussian_hmm(train_features, chosen, 60, seed + fold_no)
        train_labels = model["labels"].tolist()
        train_run = backtest_ar001_ohlc(train, initial_capital=initial_capital, risk_pct=risk_pct, direction=direction, fee_bps=fee_bps, slippage_bps=slippage_bps)
        train_stats = _state_stats(train_run["trades_detail"], train_labels)
        enabled = [s for s, v in train_stats.items() if v["trades"] >= min_state_trades and v["expectancy_R"] > 0]

        test_features = _features(test, window)
        test_labels = _classify(test_features, model)
        test_run = backtest_ar001_ohlc(test, initial_capital=initial_capital, risk_pct=risk_pct, direction=direction, fee_bps=fee_bps, slippage_bps=slippage_bps)
        baseline_rs = [float(t["r_multiple"]) for t in test_run["trades_detail"]]
        adaptive = [float(t["r_multiple"]) for t in test_run["trades_detail"]
                    if int(test_labels[min(max(int(t["entry_index"]), 0), len(test_labels) - 1)]) in enabled]
        all_oos.extend(adaptive); all_baseline.extend(baseline_rs)
        folds.append({"fold": fold_no, "train_end": start, "test_end": test_end, "states": chosen,
                      "enabled_states": enabled, "train_state_stats": train_stats,
                      "oos_trades": len(adaptive), "baseline_oos_trades": len(baseline_rs),
                      "oos_expectancy_R": sum(adaptive) / len(adaptive) if adaptive else 0.0,
                      "baseline_oos_expectancy_R": sum(baseline_rs) / len(baseline_rs) if baseline_rs else 0.0})
        fold_no += 1; start = test_end

    exp = sum(all_oos) / len(all_oos) if all_oos else 0.0
    base_exp = sum(all_baseline) / len(all_baseline) if all_baseline else 0.0
    return {"contract": "sbt-regime-walk-forward-v1", "strategy_id": strategy_id,
            "folds": folds, "adaptive_oos": {"trades": len(all_oos), "expectancy_R": exp},
            "baseline_oos": {"trades": len(all_baseline), "expectancy_R": base_exp},
            "improvement_R": exp - base_exp if all_oos and all_baseline else 0.0,
            "methodology": {"training": "expanding_window", "hmm_fit": "train_only",
                             "strategy_selection": "train_only_positive_expectancy_by_regime",
                             "oos_untouched": True, "lookahead_safe": True,
                             "note": "Only predefined AR-001 is available; regime adaptation selects activation, not free parameter optimization."},
            "safety": SAFETY}


def _bic(x, model):
    loge = _log_gaussian(x, model["means"], model["stds"])
    ll = float(math.fsum(float(v) for v in loge.max(axis=1)))
    p = model["states"] * x.shape[1] * 2 + model["states"] * (model["states"] - 1)
    return -2 * ll + p * math.log(len(x))
