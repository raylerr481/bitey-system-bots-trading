from abc import ABC, abstractmethod
from dataclasses import dataclass

@dataclass(frozen=True)
class MarketSnapshot:
    symbol: str
    price: float

@dataclass(frozen=True)
class Signal:
    symbol: str
    action: str
    confidence: float

class Strategy(ABC):
    name = "base"

    @abstractmethod
    def evaluate(self, snapshot: MarketSnapshot) -> Signal:
        raise NotImplementedError
