"""Bounded batch evaluation for generated Bitey SBT strategies."""

from __future__ import annotations

from app.bot_builder.backtest import run_spec_backtest
from app.bot_builder.spec import BotSpecification


def rank_candidates(
    candidates: list[BotSpecification],
    prices: list[float],
    fee_pct: float = 0.001,
    top_n: int = 20,
) -> list[dict]:
    if not prices or len(prices) < 30:
        raise ValueError("at least 30 market prices are required")
    if not 1 <= top_n <= 100:
        raise ValueError("top_n must be between 1 and 100")
    if len(candidates) > 5000:
        raise ValueError("candidate batch exceeds safety limit")

    ranked: list[dict] = []
    for candidate in candidates:
        try:
            result = run_spec_backtest(candidate, prices, fee_pct)
            trades = int(result.get("trades", 0))
            wins = int(result.get("wins", 0))
            losses = int(result.get("losses", 0))
            win_rate = (wins / trades * 100) if trades else 0.0
            score = (
                float(result.get("total_return_pct", 0.0))
                - float(result.get("max_drawdown_pct", 0.0)) * 0.75
                + min(trades, 100) * 0.02
            )
            ranked.append({
                "strategy_name": candidate.name,
                "symbol": candidate.symbol,
                "timeframe": candidate.timeframe,
                "trades": trades,
                "wins": wins,
                "losses": losses,
                "win_rate_pct": round(win_rate, 4),
                "return_pct": round(float(result.get("total_return_pct", 0.0)), 4),
                "max_drawdown_pct": round(float(result.get("max_drawdown_pct", 0.0)), 4),
                "score": round(score, 4),
                "specification": candidate.model_dump(),
            })
        except (ValueError, TypeError, ZeroDivisionError) as exc:
            ranked.append({
                "strategy_name": candidate.name,
                "symbol": candidate.symbol,
                "timeframe": candidate.timeframe,
                "status": "rejected",
                "reason": str(exc),
                "score": float("-inf"),
                "specification": candidate.model_dump(),
            })

    ranked.sort(key=lambda item: item.get("score", float("-inf")), reverse=True)
    return ranked[:top_n]
