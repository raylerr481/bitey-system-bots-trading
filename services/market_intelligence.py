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
    """Deterministic first-layer SBT intelligence engine.

    It deliberately separates evidence collection from inference. External news,
    social and market-data adapters can feed normalized Evidence records later.
    Scores are opportunity/confidence scores, not guaranteed win probabilities.
    """

    SUPPORTED_LANGUAGES = ("es", "pt", "en")

    def analyze(
        self,
        *,
        capital: float,
        language: Language = "es",
        evidence: list[Evidence] | None = None,
        event: str = "energy_supply_risk",
    ) -> dict:
        if capital <= 0:
            raise ValueError("capital must be greater than zero")
        if language not in self.SUPPORTED_LANGUAGES:
            raise ValueError("unsupported language")

        evidence = evidence or []
        nodes = self._nodes_for_event(event, language)
        dominant = self._dominant_scenario(event, language)
        risk_pct = 0.01
        max_risk = round(capital * risk_pct, 2)
        best = max(nodes, key=lambda n: n.score)
        reward = round(max_risk * 2.0, 2)

        return {
            "language": language,
            "event": event,
            "capital": round(capital, 2),
            "risk": {
                "risk_pct": risk_pct,
                "max_loss": max_risk,
                "reward_if_target_hit": reward,
                "risk_reward": 2.0,
            },
            "best_opportunity": {
                "asset": best.asset,
                "direction": best.direction,
                "score": best.score,
                "horizon": best.horizon,
                "status": "conditional",
            },
            "nodes": [n.__dict__ for n in nodes],
            "scenario": dominant,
            "evidence": [e.__dict__ for e in evidence],
            "rules": [
                "Do not treat social posts as verified facts.",
                "Require independent source confirmation for high-impact events.",
                "Do not convert an opportunity score into a win guarantee.",
                "Block execution when news and price action materially conflict.",
                "Live execution remains disabled; MT5 integration stays demo/read-only.",
            ],
        }

    def _nodes_for_event(self, event: str, language: Language) -> list[MarketNode]:
        if event == "energy_supply_risk":
            return [
                MarketNode("BRENT", "long", 84, self._text(language, "Riesgo de suministro favorece petróleo si la interrupción se confirma.", "Risco de oferta favorece petróleo se a interrupção for confirmada.", "Supply risk favors oil if disruption is confirmed."), "swing"),
                MarketNode("ENERGY_STOCKS", "long", 80, self._text(language, "Productores pueden beneficiarse de precios energéticos altos.", "Produtores podem se beneficiar de preços de energia altos.", "Producers may benefit from elevated energy prices."), "swing"),
                MarketNode("AIRLINES", "short", 77, self._text(language, "Combustible más caro presiona márgenes.", "Combustível mais caro pressiona margens.", "Higher fuel costs pressure margins."), "swing"),
                MarketNode("EURUSD", "short", 72, self._text(language, "Sesgo USD condicionado a riesgo global y expectativas de tipos.", "Viés de USD condicionado ao risco global e expectativas de juros.", "USD bias depends on global risk and rate expectations."), "intraday"),
                MarketNode("GOLD", "long", 70, self._text(language, "Demanda defensiva puede apoyar oro, pero tipos reales pueden contrarrestar.", "Demanda defensiva pode apoiar ouro, mas juros reais podem contrariar.", "Defensive demand may support gold, but real rates can offset it."), "swing"),
            ]
        return [MarketNode("EURUSD", "watch", 50, "Event requires an adapter-specific model.", "intraday")]

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
