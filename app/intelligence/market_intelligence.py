from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Iterable


class Direction(str, Enum):
    BULLISH = "bullish"
    BEARISH = "bearish"
    NEUTRAL = "neutral"


class Horizon(str, Enum):
    IMMEDIATE = "0-5m"
    SHORT = "5-30m"
    INTRADAY = "30m-4h"
    SWING = "1-3d"
    MACRO = "1-4w"


@dataclass(frozen=True)
class MarketImpact:
    asset: str
    direction: Direction
    score: int
    horizon: Horizon
    reason: str


@dataclass(frozen=True)
class Opportunity:
    asset: str
    direction: Direction
    score: int
    horizon: Horizon
    action: str
    thesis: str
    risk: str


@dataclass
class NewsEvent:
    headline: str
    source_quality: int = 70
    importance: int = 50
    tags: set[str] = field(default_factory=set)


class MarketIntelligenceEngine:
    """Deterministic foundation for event -> domino -> opportunity analysis.

    This engine does not place orders. It creates explainable hypotheses that
    must still pass strategy confirmation and the SBT risk engine.
    """

    TAG_MAP = {
        "fed": {"USD": Direction.BULLISH, "EUR/USD": Direction.BEARISH,
                "NASDAQ": Direction.BEARISH, "GOLD": Direction.BEARISH},
        "hawkish": {"USD": Direction.BULLISH, "EUR/USD": Direction.BEARISH,
                    "NASDAQ": Direction.BEARISH, "GOLD": Direction.BEARISH},
        "dovish": {"USD": Direction.BEARISH, "EUR/USD": Direction.BULLISH,
                   "NASDAQ": Direction.BULLISH, "GOLD": Direction.BULLISH},
        "inflation": {"USD": Direction.BULLISH, "US2Y": Direction.BULLISH,
                      "NASDAQ": Direction.BEARISH, "GOLD": Direction.BEARISH},
        "oil": {"USD/CAD": Direction.BEARISH, "CAD": Direction.BULLISH,
                "OIL": Direction.BULLISH},
        "risk_off": {"USD": Direction.BULLISH, "JPY": Direction.BULLISH,
                     "GOLD": Direction.BULLISH, "NASDAQ": Direction.BEARISH,
                     "BTC": Direction.BEARISH},
        "risk_on": {"USD": Direction.BEARISH, "JPY": Direction.BEARISH,
                    "NASDAQ": Direction.BULLISH, "BTC": Direction.BULLISH},
    }

    HORIZON_SCORE = {
        Horizon.IMMEDIATE: 100,
        Horizon.SHORT: 90,
        Horizon.INTRADAY: 80,
        Horizon.SWING: 65,
        Horizon.MACRO: 50,
    }

    def impacts(self, event: NewsEvent) -> list[MarketImpact]:
        merged: dict[str, tuple[Direction, int, set[str]]] = {}
        for tag in event.tags:
            for asset, direction in self.TAG_MAP.get(tag.lower(), {}).items():
                current = merged.get(asset)
                if current is None:
                    merged[asset] = (direction, 1, {tag})
                elif current[0] == direction:
                    merged[asset] = (direction, current[1] + 1, current[2] | {tag})
                else:
                    merged[asset] = (Direction.NEUTRAL, current[1] + 1, current[2] | {tag})

        impacts: list[MarketImpact] = []
        for asset, (direction, evidence, tags) in merged.items():
            score = min(100, 30 + event.importance // 2 + event.source_quality // 5 + evidence * 8)
            horizon = Horizon.IMMEDIATE if event.importance >= 80 else Horizon.INTRADAY
            reason = f"tags={','.join(sorted(tags))}; evidence={evidence}"
            impacts.append(MarketImpact(asset, direction, score, horizon, reason))
        return sorted(impacts, key=lambda item: item.score, reverse=True)

    def opportunities(self, event: NewsEvent, confirmed_assets: Iterable[str] = ()) -> list[Opportunity]:
        confirmed = {asset.upper() for asset in confirmed_assets}
        results: list[Opportunity] = []
        for impact in self.impacts(event):
            confirmation = 15 if impact.asset.upper() in confirmed else 0
            score = min(100, impact.score + confirmation)
            if score < 60:
                continue
            action = "watch"
            risk = "elevated" if event.importance >= 80 else "normal"
            if impact.direction is Direction.NEUTRAL:
                action = "wait"
                risk = "conflicted"
            thesis = (
                f"{event.headline}: {impact.asset} has a {impact.direction.value} "
                f"bias through the detected event chain."
            )
            results.append(Opportunity(
                impact.asset, impact.direction, score, impact.horizon,
                action, thesis, risk,
            ))
        return results

    def analyze(self, event: NewsEvent, confirmed_assets: Iterable[str] = ()) -> dict:
        impacts = self.impacts(event)
        opportunities = self.opportunities(event, confirmed_assets)
        return {
            "headline": event.headline,
            "event_importance": event.importance,
            "source_quality": event.source_quality,
            "primary_and_domino_impacts": [impact.__dict__ for impact in impacts],
            "opportunities": [opportunity.__dict__ for opportunity in opportunities],
            "execution_allowed": False,
            "next_gate": "strategy_confirmation_and_risk_engine",
        }
