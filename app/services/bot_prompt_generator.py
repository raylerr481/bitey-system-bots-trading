from __future__ import annotations

from dataclasses import dataclass, asdict
from typing import Any


@dataclass
class BotPromptProposal:
    prompt_id: str
    version: str
    profile: str
    event_basis: dict[str, Any]
    objective: str
    hypothesis: str
    entry_filters: list[str]
    exit_rules: list[str]
    volatility_filter: list[str]
    risk_controls: list[str]
    sizing: str
    event_window: str
    invalidation_conditions: list[str]
    validation_requirements: list[str]

    def model_dump(self) -> dict[str, Any]:
        return asdict(self)


def _common(event: dict[str, Any]) -> tuple[list[str], list[str], list[str], list[str]]:
    impact = event.get("impact", "mixed")
    bias = event.get("bias", "neutral")
    filters = [
        f"Use the event bias ({bias}) only as a hypothesis, never as a trade signal by itself.",
        "Require price/volume confirmation on the selected timeframe.",
        "Reject entries when spread, slippage or liquidity is abnormal.",
    ]
    exits = [
        "Use a predefined stop-loss and take-profit before entry.",
        "Exit when the event thesis is invalidated or market regime changes.",
    ]
    volatility = [
        "Use ATR or equivalent volatility measurement for adaptive stops.",
        f"Treat event impact ({impact}) as a volatility-risk input.",
    ]
    risks = [
        "Maximum position size must pass SBT Risk Gate.",
        "Suspend after the configured daily-loss or drawdown threshold.",
        "Limit consecutive losses and require a cooldown after repeated failures.",
        "Never allow news analysis to place an order directly.",
    ]
    return filters, exits, volatility, risks


def generate_bot_prompts(analysis: dict[str, Any], market: str | None = None, timeframe: str = "1h") -> list[dict[str, Any]]:
    event_id = str(analysis.get("event_id", "event-unknown"))
    event_basis = {
        "event_id": event_id,
        "headline": analysis.get("headline", ""),
        "sector": analysis.get("sector", ""),
        "assets": analysis.get("assets", []),
        "impact": analysis.get("impact", "mixed"),
        "bias": analysis.get("bias", "neutral"),
        "opportunity_score": analysis.get("opportunity_score", 0),
        "risk_score": analysis.get("risk_score", 0),
        "volatility_score": analysis.get("volatility_score", 0),
        "horizon": analysis.get("horizon", "short_term"),
    }
    filters, exits, volatility, risks = _common(analysis)
    target = market or ((analysis.get("assets") or ["selected asset"])[0])

    variants = [
        ("conservative", "Prioritize capital preservation and risk-adjusted robustness.", "Trade only when the event thesis, trend and volatility conditions align.", 0.01),
        ("balanced", "Seek improved expected return per unit of modeled risk.", "Trade confirmed event-driven momentum with strict downside controls.", 0.02),
        ("event-driven", "Capture event-related movement while explicitly bounding event risk.", "Trade only inside a defined event window after confirmation; reduce exposure when uncertainty spikes.", 0.015),
    ]
    proposals: list[dict[str, Any]] = []
    for profile, objective, hypothesis, max_position in variants:
        proposals.append(BotPromptProposal(
            prompt_id=f"news-{event_id}-{profile}",
            version="1.0.0",
            profile=profile,
            event_basis=event_basis,
            objective=objective,
            hypothesis=f"{hypothesis} Market={target}; timeframe={timeframe}.",
            entry_filters=filters + [f"Require minimum modeled risk/reward of 1:{2 if profile == 'conservative' else 1.5} before entry."],
            exit_rules=exits + (["Take partial profit and trail the remainder only after the trade is in profit."] if profile != "event-driven" else ["Close or reduce exposure when the event window expires."]),
            volatility_filter=volatility + ["Avoid entries during unbounded volatility spikes or execution-quality degradation."],
            risk_controls=risks + [f"Suggested starting max position: {max_position:.1%}; final limit is determined by Risk Gate."],
            sizing="Risk-based sizing; never increase size solely because opportunity_score is high.",
            event_window="Use the analyzed event horizon as a research window; validate exact entry/exit timing with historical data.",
            invalidation_conditions=[
                "Backtest loses robustness out of sample.",
                "Performance collapses under realistic spread/slippage stress.",
                "Event interpretation conflicts with price action or volatility regime.",
                "Risk Gate rejects the proposed exposure.",
            ],
            validation_requirements=[
                "Historical backtest with train/test or walk-forward separation.",
                "Stress test for spread, slippage, gaps and volatility shocks.",
                "Evaluate drawdown, expectancy, Profit Factor, Sharpe/Sortino, win rate and losing streaks.",
                "Run Demo/Paper before any consideration of real-money execution.",
            ],
        ).model_dump())
    return proposals
