from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any


@dataclass
class TurtleState:
    """Read/decision state for the Turtle Controller.

    The controller proposes changes; it never bypasses the deterministic
    strategy or Risk Gate and never mutates live parameters by itself.
    """
    status: str = "IDLE"
    mode: str = "DEMO"
    symbol: str = ""
    timeframe: str = ""
    regime: str = "UNKNOWN"
    signal: str = "NONE"
    position_count: int = 0
    risk_pct: float = 0.25
    drawdown_pct: float = 0.0
    last_trade_pnl: float | None = None
    market: dict[str, Any] = field(default_factory=dict)
    last_entry: Any = None
    campaign_n: Any = None
    s1_skip_next: Any = None
    s1_skip_latched: Any = None
    next_action: str = "WAIT"
    learning_status: str = "OBSERVING"
    proposal_pending: bool = False
    proposal_id: str | None = None
    reason: str = ""
    version: int = 1


@dataclass
class TurtleController:
    max_drawdown_pct: float = 10.0
    max_risk_pct: float = 0.25
    min_trades_for_learning: int = 30
    state: TurtleState = field(default_factory=TurtleState)
    _trade_count: int = 0
    _learning_events: list[dict[str, Any]] = field(default_factory=list)
    demo_multiplier: float = 1.0
    demo_multiplier_profile: str = "CONSERVATIVE"
    demo_multiplier_score: float = 0.0

    def observe(self, snapshot: dict[str, Any]) -> dict[str, Any]:
        """Consume an MT4/Gateway snapshot without changing execution settings."""
        s = self.state
        s.status = str(snapshot.get("status") or s.status).upper()
        s.mode = str(snapshot.get("mode") or s.mode).upper()
        s.symbol = str(snapshot.get("symbol") or s.symbol)
        s.timeframe = str(snapshot.get("timeframe") or s.timeframe)
        s.regime = str(snapshot.get("regime") or s.regime).upper()
        s.signal = str(snapshot.get("signal") or s.signal).upper()
        s.position_count = int(snapshot.get("position_count", s.position_count) or 0)
        s.risk_pct = min(float(snapshot.get("risk_pct", s.risk_pct) or 0), self.max_risk_pct)
        s.drawdown_pct = max(0.0, float(snapshot.get("drawdown_pct", s.drawdown_pct) or 0))
        s.last_trade_pnl = snapshot.get("last_trade_pnl", s.last_trade_pnl)
        s.market = dict(snapshot.get("market") or s.market)
        s.last_entry = snapshot.get("last_entry", s.last_entry)
        s.campaign_n = snapshot.get("campaign_n", s.campaign_n)
        s.s1_skip_next = snapshot.get("s1_skip_next", s.s1_skip_next)
        s.s1_skip_latched = snapshot.get("s1_skip_latched", s.s1_skip_latched)
        if s.drawdown_pct >= self.max_drawdown_pct:
            s.next_action = "PAUSE_RISK"
            s.reason = "maximum_drawdown_gate"
        elif s.position_count > 0:
            s.next_action = "MANAGE_POSITION"
            s.reason = "position_active"
        elif s.signal in {"BUY", "SELL"}:
            s.next_action = "CHECK_RISK_GATE"
            s.reason = "turtle_breakout_signal"
        else:
            s.next_action = "WAIT"
            s.reason = "no_actionable_signal"
        return self.status()

    def record_trade(self, pnl: float, metadata: dict[str, Any] | None = None) -> None:
        self._trade_count += 1
        self.state.last_trade_pnl = float(pnl)
        self._learning_events.append({
            "type": "trade_observation",
            "trade_count": self._trade_count,
            "pnl": float(pnl),
            "metadata": metadata or {},
        })
        self.state.learning_status = (
            "READY_FOR_EVALUATION"
            if self._trade_count >= self.min_trades_for_learning
            else "OBSERVING"
        )

    def select_demo_multiplier(self, metrics: dict[str, Any]) -> dict[str, Any]:
        """Select a virtual demo capital-growth multiplier from risk-adjusted evidence.

        This never changes MT4 lot size, leverage, broker orders, or live risk.
        It only controls the virtual DEMO simulation multiplier.
        """
        if self.state.mode != "DEMO":
            return {"status": "DEMO_ONLY", "selected_multiplier": self.demo_multiplier}
        if self._trade_count < self.min_trades_for_learning:
            return {"status": "INSUFFICIENT_DATA", "required_trades": self.min_trades_for_learning,
                    "selected_multiplier": self.demo_multiplier}
        expectancy = float(metrics.get("expectancy", 0) or 0)
        dd = max(0.0, float(metrics.get("drawdown_pct", self.state.drawdown_pct) or 0))
        pf = float(metrics.get("profit_factor", 0) or 0)
        candidates = (1.0, 1.5, 2.0, 3.0)
        best = (1.0, float("-inf"))
        for multiplier in candidates:
            projected_dd = dd * multiplier
            if projected_dd > 8.0:
                continue
            score = (expectancy * multiplier) + (max(0.0, pf - 1.0) * multiplier * 0.25) - (projected_dd ** 1.25 * 0.08)
            if score > best[1]:
                best = (multiplier, score)
        self.demo_multiplier = best[0]
        self.demo_multiplier_score = best[1]
        self.demo_multiplier_profile = {1.0: "CONSERVATIVE", 1.5: "BALANCED", 2.0: "GROWTH", 3.0: "AGGRESSIVE"}[best[0]]
        return self.demo_multiplier_status()

    def demo_multiplier_status(self) -> dict[str, Any]:
        return {
            "mode": self.state.mode,
            "selected_multiplier": self.demo_multiplier,
            "profile": self.demo_multiplier_profile,
            "score": self.demo_multiplier_score,
            "automatic": True,
            "virtual_only": True,
            "changes_mt4_lot_size": False,
            "changes_live_risk": False,
            "allowed_profiles": [
                {"multiplier": 1.0, "profile": "CONSERVATIVE"},
                {"multiplier": 1.5, "profile": "BALANCED"},
                {"multiplier": 2.0, "profile": "GROWTH"},
                {"multiplier": 3.0, "profile": "AGGRESSIVE"},
            ],
            "max_projected_drawdown_pct": 8.0,
        }

    def evaluate_learning(self, metrics: dict[str, Any]) -> dict[str, Any]:
        """Create a bounded proposal; never auto-applies parameter changes."""
        if self._trade_count < self.min_trades_for_learning:
            return {"status": "INSUFFICIENT_DATA", "proposal": None}
        dd = float(metrics.get("drawdown_pct", self.state.drawdown_pct) or 0)
        pf = float(metrics.get("profit_factor", 0) or 0)
        expectancy = float(metrics.get("expectancy", 0) or 0)
        if dd >= self.max_drawdown_pct or (pf < 1.0 and expectancy < 0):
            proposal = {
                "type": "RISK_REVIEW",
                "action": "PAUSE_AND_REVALIDATE",
                "reason": "performance_degradation",
            }
        else:
            proposal = {
                "type": "PARAMETER_RESEARCH",
                "action": "BACKTEST_BEFORE_CHANGE",
                "reason": "seek_robust_improvement",
            }
        proposal_id = f"turtle-proposal-{self._trade_count}"
        self.state.proposal_pending = True
        self.state.proposal_id = proposal_id
        self.state.learning_status = "PROPOSAL_PENDING"
        self._learning_events.append({"type": "learning_proposal", "id": proposal_id, **proposal})
        return {"status": "PROPOSAL_PENDING", "proposal_id": proposal_id, "proposal": proposal}

    def status(self) -> dict[str, Any]:
        s = self.state
        return {
            "controller": "Turtle Controller",
            "status": s.status,
            "mode": s.mode,
            "symbol": s.symbol,
            "timeframe": s.timeframe,
            "regime": s.regime,
            "signal": s.signal,
            "position_count": s.position_count,
            "risk_pct": s.risk_pct,
            "drawdown_pct": s.drawdown_pct,
            "last_trade_pnl": s.last_trade_pnl,
            "market": s.market,
            "last_entry": s.last_entry,
            "campaign_n": s.campaign_n,
            "s1_skip_next": s.s1_skip_next,
            "s1_skip_latched": s.s1_skip_latched,
            "next_action": s.next_action,
            "reason": s.reason,
            "learning_status": s.learning_status,
            "proposal_pending": s.proposal_pending,
            "proposal_id": s.proposal_id,
            "trade_count": self._trade_count,
            "live_parameter_change": False,
            "risk_gate_authoritative": True,
            "version": s.version,
            "demo_multiplier": self.demo_multiplier,
            "demo_multiplier_profile": self.demo_multiplier_profile,
            "demo_multiplier_automatic": True,
            "demo_multiplier_virtual_only": True,
        }


_controller = TurtleController()


def get_turtle_controller() -> TurtleController:
    """Return the process-wide Turtle Controller used by every API surface."""
    return _controller
