from __future__ import annotations

from dataclasses import dataclass
from typing import Any


@dataclass
class TurtleReadinessEngine:
    """Evidence-based Turtle performance and DEMO->LIVE readiness evaluator.

    The probability is an evidence score, not a guarantee or a statistical
    promise of future profit. LIVE readiness requires every hard gate.
    """

    min_trades: int = 30
    preferred_trades: int = 100
    max_dd_pct: float = 10.0
    target_pf: float = 1.20
    target_expectancy: float = 0.0
    target_walk_forward: float = 0.55
    target_robustness: float = 0.60

    def evaluate(self, metrics: dict[str, Any], mode: str = "DEMO") -> dict[str, Any]:
        trades = int(metrics.get("trades", metrics.get("trade_count", 0)) or 0)
        pf = float(metrics.get("profit_factor", 0) or 0)
        expectancy = float(metrics.get("expectancy", 0) or 0)
        dd = max(0.0, float(metrics.get("drawdown_pct", 0) or 0))
        recovery = float(metrics.get("recovery_factor", 0) or 0)
        wf = float(metrics.get("walk_forward_score", metrics.get("walk_forward", 0)) or 0)
        robustness = float(metrics.get("robustness_score", metrics.get("robustness", 0)) or 0)
        oos = float(metrics.get("out_of_sample_score", metrics.get("oos_score", 0)) or 0)
        stability = float(metrics.get("stability_score", metrics.get("stability", 0)) or 0)
        win_rate = float(metrics.get("win_rate_pct", metrics.get("win_rate", 0)) or 0)
        avg_win = float(metrics.get("avg_win", 0) or 0)
        avg_loss = abs(float(metrics.get("avg_loss", 0) or 0))
        return_pct = float(metrics.get("return_pct", metrics.get("net_return_pct", 0)) or 0)
        monthly_return = float(metrics.get("monthly_return_pct", 0) or 0)
        sharpe = float(metrics.get("sharpe_ratio", metrics.get("sharpe", 0)) or 0)
        calmar = float(metrics.get("calmar_ratio", metrics.get("calmar", 0)) or 0)

        sample_score = min(1.0, trades / self.preferred_trades)
        pf_score = min(1.0, max(0.0, (pf - 1.0) / 0.75))
        exp_score = 1.0 if expectancy > self.target_expectancy else max(0.0, expectancy / max(abs(self.target_expectancy) + 1.0, 1.0))
        dd_score = max(0.0, 1.0 - dd / self.max_dd_pct)
        wf_score = min(1.0, max(0.0, wf))
        robust_score = min(1.0, max(0.0, robustness))
        oos_score = min(1.0, max(0.0, oos))
        stability_score = min(1.0, max(0.0, stability))

        probability = round(100 * (
            0.15 * sample_score +
            0.15 * pf_score +
            0.10 * exp_score +
            0.15 * dd_score +
            0.15 * wf_score +
            0.10 * robust_score +
            0.10 * oos_score +
            0.10 * stability_score
        ), 1)

        payoff_ratio = (avg_win / avg_loss) if avg_loss > 0 else 0.0
        breakeven_win_rate = (1.0 / (1.0 + payoff_ratio) * 100.0) if payoff_ratio > 0 else 100.0
        expectancy_per_trade = ((win_rate / 100.0) * avg_win - (1.0 - win_rate / 100.0) * avg_loss) if (avg_win > 0 or avg_loss > 0) else expectancy
        hard_gates = {
            "minimum_sample": trades >= self.min_trades,
            "positive_expectancy": expectancy > self.target_expectancy,
            "profit_factor": pf >= self.target_pf,
            "drawdown": dd < self.max_dd_pct,
            "walk_forward": wf >= self.target_walk_forward,
            "robustness": robustness >= self.target_robustness,
            "out_of_sample": oos >= self.target_walk_forward,
            "stability": stability >= self.target_robustness,
            "demo_mode": str(mode).upper() == "DEMO",
        }
        passed = sum(hard_gates.values())
        live_ready = passed == len(hard_gates) and probability >= 70.0

        if live_ready:
            flag = "LIVE_READY"
        elif probability >= 70 and passed >= 6:
            flag = "POSITIVE_NEEDS_VALIDATION"
        elif probability >= 50:
            flag = "OPTIMIZING"
        elif trades < self.min_trades:
            flag = "INSUFFICIENT_DATA"
        else:
            flag = "DEGRADING"

        failed = [k for k, v in hard_gates.items() if not v]
        return {
            "engine": "Turtle Performance & Readiness Engine",
            "mode": str(mode).upper(),
            "performance_probability_pct": probability,
            "probability_note": "Evidence score only; not a guarantee of future returns.",
            "performance_flag": flag,
            "live_ready": live_ready,
            "hard_gates": hard_gates,
            "gates_passed": passed,
            "gates_total": len(hard_gates),
            "failed_gates": failed,
            "probability_analysis": {
                "estimated_positive_performance_score_pct": probability,
                "win_rate_pct": win_rate,
                "payoff_ratio": round(payoff_ratio, 3),
                "breakeven_win_rate_pct": round(breakeven_win_rate, 1),
                "expectancy_per_trade": round(expectancy_per_trade, 6),
                "return_pct": return_pct,
                "monthly_return_pct": monthly_return,
                "sharpe_ratio": sharpe,
                "calmar_ratio": calmar,
                "note": "This is a risk-adjusted evidence score, not a guaranteed probability of profit."
            },
            "metrics": {
                "trades": trades,
                "profit_factor": pf,
                "expectancy": expectancy,
                "drawdown_pct": dd,
                "recovery_factor": recovery,
                "walk_forward_score": wf,
                "robustness_score": robustness,
                "out_of_sample_score": oos,
                "stability_score": stability,
                "win_rate_pct": win_rate,
                "avg_win": avg_win,
                "avg_loss": avg_loss,
            },
            "recommendation": (
                "Turtle passed the DEMO optimization/readiness gates. "
                "Request explicit LIVE authorization review."
                if live_ready else
                "Continue DEMO, collect evidence, and re-evaluate before LIVE."
            ),
        }
