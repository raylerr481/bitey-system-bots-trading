from __future__ import annotations

from dataclasses import asdict, dataclass, field
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
    layer: str
    reason: str


@dataclass(frozen=True)
class DominoEffect:
    source: str
    asset: str
    direction: Direction
    layer: int
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
    confirmation_required: bool


@dataclass
class NewsEvent:
    headline: str
    source_quality: int = 70
    importance: int = 50
    tags: set[str] = field(default_factory=set)


class MarketIntelligenceEngine:
    """Deterministic event -> domino -> opportunity analysis.

    Intelligence creates explainable hypotheses only. It never places orders.
    Strategy confirmation and the SBT Risk Engine remain mandatory.
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

    DOMINO_MAP = {
        "USD": {
            "EUR/USD": Direction.BEARISH,
            "USD/JPY": Direction.BULLISH,
            "USD/BRL": Direction.BULLISH,
            "GOLD": Direction.BEARISH,
            "NASDAQ": Direction.BEARISH,
        },
        "US2Y": {
            "USD": Direction.BULLISH,
            "NASDAQ": Direction.BEARISH,
            "GOLD": Direction.BEARISH,
        },
        "OIL": {
            "USD/CAD": Direction.BEARISH,
            "CAD": Direction.BULLISH,
        },
        "NASDAQ": {"BTC": Direction.BEARISH},
    }

    HORIZONS = (Horizon.IMMEDIATE, Horizon.SHORT, Horizon.INTRADAY, Horizon.SWING, Horizon.MACRO)

    def _base_score(self, event: NewsEvent, evidence: int) -> int:
        return min(100, 30 + event.importance // 2 + event.source_quality // 5 + evidence * 8)

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

        results: list[MarketImpact] = []
        for asset, (direction, evidence, tags) in merged.items():
            score = self._base_score(event, evidence)
            horizon = Horizon.IMMEDIATE if event.importance >= 80 else Horizon.INTRADAY
            results.append(MarketImpact(
                asset=asset,
                direction=direction,
                score=score,
                horizon=horizon,
                layer="primary",
                reason=f"tags={','.join(sorted(tags))}; evidence={evidence}",
            ))
        return sorted(results, key=lambda item: item.score, reverse=True)

    def domino_effects(self, event: NewsEvent) -> list[DominoEffect]:
        """Build secondary/tertiary hypotheses from primary affected assets."""
        effects: list[DominoEffect] = []
        seen: set[tuple[str, str]] = set()
        for primary in self.impacts(event):
            for asset, direction in self.DOMINO_MAP.get(primary.asset, {}).items():
                key = (primary.asset, asset)
                if key in seen:
                    continue
                seen.add(key)
                horizon = Horizon.SHORT if primary.horizon is Horizon.IMMEDIATE else Horizon.INTRADAY
                effects.append(DominoEffect(
                    source=primary.asset,
                    asset=asset,
                    direction=direction if primary.direction is Direction.BULLISH else (
                        Direction.BULLISH if direction is Direction.BEARISH else Direction.BEARISH
                    ) if primary.direction is Direction.BEARISH else Direction.NEUTRAL,
                    layer=2,
                    horizon=horizon,
                    reason=f"secondary propagation from {primary.asset}",
                ))
        return effects

    def opportunities(self, event: NewsEvent, confirmed_assets: Iterable[str] = ()) -> list[Opportunity]:
        confirmed = {asset.upper() for asset in confirmed_assets}
        results: list[Opportunity] = []
        primary = self.impacts(event)
        domino = self.domino_effects(event)
        candidates = primary + [MarketImpact(
            asset=item.asset, direction=item.direction, score=max(0, 80 - item.layer * 10),
            horizon=item.horizon, layer="secondary", reason=item.reason,
        ) for item in domino]

        for impact in candidates:
            confirmation = 15 if impact.asset.upper() in confirmed else 0
            score = min(100, impact.score + confirmation)
            if score < 60:
                continue
            if impact.direction is Direction.NEUTRAL:
                action, risk = "wait", "conflicted"
            elif impact.asset.upper() in confirmed:
                action, risk = "watch-confirmed", "elevated" if event.importance >= 80 else "normal"
            else:
                action, risk = "watch", "elevated" if event.importance >= 80 else "normal"
            results.append(Opportunity(
                asset=impact.asset,
                direction=impact.direction,
                score=score,
                horizon=impact.horizon,
                action=action,
                thesis=(f"{event.headline}: {impact.asset} has a {impact.direction.value} bias "
                        f"through the {impact.layer} market-impact chain."),
                risk=risk,
                confirmation_required=impact.asset.upper() not in confirmed,
            ))
        return sorted(results, key=lambda item: item.score, reverse=True)

    def analyze(self, event: NewsEvent, confirmed_assets: Iterable[str] = ()) -> dict:
        impacts = self.impacts(event)
        domino = self.domino_effects(event)
        opportunities = self.opportunities(event, confirmed_assets)
        return {
            "headline": event.headline,
            "event_importance": event.importance,
            "source_quality": event.source_quality,
            "primary_impacts": [asdict(item) for item in impacts],
            "domino_effects": [asdict(item) for item in domino],
            "probable_market_horizons": [h.value for h in self.HORIZONS],
            "opportunities": [asdict(item) for item in opportunities],
            "execution_allowed": False,
            "next_gate": "strategy_confirmation_and_risk_engine",
        }
