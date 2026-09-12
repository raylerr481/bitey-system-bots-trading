from __future__ import annotations

from dataclasses import dataclass
from itertools import product
from typing import Iterable


@dataclass(frozen=True)
class ResearchTarget:
    symbol: str
    timeframe: str


def build_matrix(symbols: Iterable[str], timeframes: Iterable[str], max_targets: int = 100) -> list[ResearchTarget]:
    """Build a bounded multi-market/multi-timeframe research matrix."""
    symbols = tuple(dict.fromkeys(s.strip().upper() for s in symbols if s.strip()))
    timeframes = tuple(dict.fromkeys(t.strip().upper() for t in timeframes if t.strip()))
    if max_targets < 1:
        return []
    return [ResearchTarget(symbol, timeframe) for symbol, timeframe in product(symbols, timeframes)][:max_targets]
