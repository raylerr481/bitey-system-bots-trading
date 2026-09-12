from __future__ import annotations


def metrics_from_result(result: dict, complexity: int) -> dict:
    details = [t for t in result.get("trades_detail", []) if t.get("pnl_pct") is not None and t.get("result") != "open"]
    wins = [float(t["pnl_pct"]) for t in details if t.get("pnl_pct", 0) > 0]
    losses = [abs(float(t["pnl_pct"])) for t in details if t.get("pnl_pct", 0) < 0]
    gross_win = sum(wins)
    gross_loss = sum(losses)
    profit_factor = gross_win / gross_loss if gross_loss else (999.0 if gross_win else 0.0)
    avg_win = gross_win / len(wins) if wins else 0.0
    avg_loss = gross_loss / len(losses) if losses else 0.0
    win_probability = len(wins) / len(details) if details else 0.0
    loss_probability = len(losses) / len(details) if details else 0.0
    expectancy = win_probability * avg_win - loss_probability * avg_loss
    return {
        "trades": int(result.get("trades", 0)),
        "closed_trades": len(details),
        "wins": len(wins),
        "losses": len(losses),
        "win_rate_pct": round(win_probability * 100, 4),
        "profit_factor": round(profit_factor, 6),
        "expectancy_pct": round(expectancy, 6),
        "avg_win_pct": round(avg_win, 6),
        "avg_loss_pct": round(avg_loss, 6),
        "return_pct": round(float(result.get("total_return_pct", 0.0)), 6),
        "max_drawdown_pct": round(float(result.get("max_drawdown_pct", 0.0)), 6),
        "complexity": complexity,
    }


def fitness(metrics: dict) -> float:
    trades = metrics["closed_trades"]
    if trades <= 0:
        return -1_000_000.0
    score = (
        metrics["return_pct"]
        + metrics["expectancy_pct"] * 10.0
        + min(metrics["profit_factor"], 5.0) * 4.0
        - metrics["max_drawdown_pct"] * 0.8
        - metrics["complexity"] * 0.35
    )
    if trades < 10:
        score -= (10 - trades) * 2.0
    return round(score, 6)
