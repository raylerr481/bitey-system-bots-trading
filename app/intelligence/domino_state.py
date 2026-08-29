from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

from app.intelligence.models import DominoState


@dataclass(frozen=True)
class DominoTransition:
    previous: DominoState
    current: DominoState
    timestamp: datetime
    reason: str


class DominoStateMachine:
    """Deterministic state machine for market-event propagation."""

    _allowed = {
        DominoState.NEW: {DominoState.SHOCK, DominoState.REJECTED, DominoState.EXPIRED},
        DominoState.SHOCK: {DominoState.CONFIRMING, DominoState.REJECTED, DominoState.EXPIRED},
        DominoState.CONFIRMING: {DominoState.CONFIRMED, DominoState.REJECTED, DominoState.EXPIRED},
        DominoState.CONFIRMED: {DominoState.EXTENDED, DominoState.EXPIRED, DominoState.REJECTED},
        DominoState.EXTENDED: {DominoState.EXPIRED, DominoState.REJECTED},
        DominoState.EXPIRED: set(),
        DominoState.REJECTED: set(),
    }

    def __init__(self, state: DominoState = DominoState.NEW, ttl_minutes: int = 240):
        if ttl_minutes <= 0:
            raise ValueError("ttl_minutes must be positive")
        self.state = state
        self.ttl = timedelta(minutes=ttl_minutes)
        self.updated_at = datetime.now(timezone.utc)
        self.history: list[DominoTransition] = []

    def transition(self, target: DominoState, reason: str, now: datetime | None = None) -> DominoTransition:
        now = now or datetime.now(timezone.utc)
        if target not in self._allowed[self.state]:
            raise ValueError(f"Invalid domino transition: {self.state.value} -> {target.value}")
        transition = DominoTransition(self.state, target, now, reason)
        self.history.append(transition)
        self.state = target
        self.updated_at = now
        return transition

    def expire_if_needed(self, now: datetime | None = None) -> bool:
        now = now or datetime.now(timezone.utc)
        if self.state in {DominoState.EXPIRED, DominoState.REJECTED}:
            return self.state is DominoState.EXPIRED
        if now - self.updated_at >= self.ttl:
            self.transition(DominoState.EXPIRED, "event_ttl_expired", now)
            return True
        return False
