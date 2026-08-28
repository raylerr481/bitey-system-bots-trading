from __future__ import annotations

from dataclasses import dataclass
from typing import Literal

Language = Literal["es", "pt", "en"]
Direction = Literal["long", "short", "neutral", "watch"]
Horizon = Literal["scalp", "intraday", "swing", "macro"]


@dataclass(frozen=True)
class Evidence:
    source: str
    source_type: str
    title: str
    reliability: float
    impact: float
    direction: Direction


@dataclass(frozen=True)
class MarketNode:
    asset: str
    direction: Direction
    score: float
    rationale: str
    horizon: Horizon


@dataclass(frozen=True)
class Scenario:
    name: str
    probability_score: float
    effects: dict[str, Direction]
    invalidation: str


class MarketIntelligenceEngine:
    """First-layer deterministic SBT intelligence model.

    External collectors will feed normalized evidence later. Scores are opportunity
    scores, never guaranteed win probabilities.
    """

    SUPPORTED_LANGUAGES = ("es", "pt", "en")

    def analyze(self, *, capital: float, language: Language = "es", evidence: list[Evidence] | None = None, event: str = "energy_supply_risk") -> dict:
        if capital <= 0:
            raise ValueError("capital must be greater than zero")
        if language not in self.SUPPORTED_LANGUAGES:
            raise ValueError("unsupported language")
        evidence = evidence or []
        nodes = self._nodes_for_event(event, language)
        scenario = self._dominant_scenario(event, language)
        max_loss = round(capital * 0.01, 2)
        best = max(nodes, key=lambda node: node.score)
        return {
            "language": language,
            "event": event,
            "capital": round(capital, 2),
            "risk": {"risk_pct": 0.01, "max_loss": max_loss, "reward_if_target_hit": round(max_loss * 2, 2), "risk_reward": 2.0},
            "best_opportunity": {"asset": best.asset, "direction": best.direction, "score": best.score, "horizon": best.horizon, "status": "conditional"},
            "nodes": [node.__dict__ for node in nodes],
            "scenario": scenario,
            "evidence": [item.__dict__ for item in evidence],
            "rules": [
                "Social posts are evidence, not verified facts.",
                "High-impact claims require independent confirmation.",
                "Opportunity scores are not win guarantees.",
                "Conflicting news and price action should result in watch/no-trade.",
                "Live execution is disabled; MT5 remains demo/read-only.",
            ],
        }

    def _nodes_for_event(self, event: str, language: Language) -> list[MarketNode]:
        if event == "energy_supply_risk":
            return [
                MarketNode("BRENT", "long", 84, self._text(language, "Riesgo de suministro favorece petróleo si se confirma.", "Risco de oferta favorece petróleo se confirmado.", "Supply risk favors oil if confirmed."), "swing"),
                MarketNode("ENERGY_STOCKS", "long", 80, self._text(language, "Productores pueden beneficiarse de precios altos.", "Produtores podem se beneficiar de preços altos.", "Producers may benefit from higher prices."), "swing"),
                MarketNode("AIRLINES", "short", 77, self._text(language, "Combustible más caro presiona márgenes.", "Combustível mais caro pressiona margens.", "Higher fuel costs pressure margins."), "swing"),
                MarketNode("EURUSD", "short", 72, self._text(language, "Sesgo USD condicionado al riesgo global y tipos.", "Viés de USD condicionado ao risco global e juros.", "USD bias depends on global risk and rates."), "intraday"),
                MarketNode("GOLD", "long", 70, self._text(language, "Demanda defensiva puede apoyar oro; tipos pueden contrarrestar.", "Demanda defensiva pode apoiar ouro; juros podem contrariar.", "Defensive demand may support gold; rates can offset it."), "swing"),
            ]
        return [MarketNode("EURUSD", "watch", 50, "No event model configured.", "intraday")]

    def _dominant_scenario(self, event: str, language: Language) -> dict:
        if event == "energy_supply_risk":
            return Scenario(
                name=self._text(language, "Interrupción energética prolongada", "Interrupção energética prolongada", "Prolonged energy disruption"),
                probability_score=68,
                effects={"BRENT": "long", "ENERGY_STOCKS": "long", "AIRLINES": "short", "EURUSD": "short"},
                invalidation=self._text(language, "Acuerdo verificable y normalización sostenida del tránsito.", "Acordo verificável e normalização sustentada do tráfego.", "Verifiable agreement and sustained normalization of traffic."),
            ).__dict__
        return Scenario("Unknown", 0, {}, "No event model").__dict__

    @staticmethod
    def _text(language: Language, es: str, pt: str, en: str) -> str:
        return {"es": es, "pt": pt, "en": en}[language]


engine = MarketIntelligenceEngine()
