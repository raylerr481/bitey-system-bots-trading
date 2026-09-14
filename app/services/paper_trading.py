from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class PaperConfig:
    initial_capital: float = 10000.0
    fee_rate: float = 0.0005
    slippage_bps: float = 2.0
    risk_per_trade: float = 0.005
    max_position_pct: float = 0.02


@dataclass
class PaperPosition:
    side: str
    entry: float
    quantity: float
    stop: float
    target: float
    entry_fee: float


def _fill_price(price: float, side: str, slippage_bps: float, opening: bool) -> float:
    slip = slippage_bps / 10000
    if side == "LONG":
        return price * (1 + slip if opening else 1 - slip)
    return price * (1 - slip if opening else 1 + slip)


def _validate_signal(signal: dict) -> tuple[bool, str]:
    required = ("action", "entry", "stop", "target")
    if any(key not in signal for key in required):
        return False, "signal_missing_required_fields"
    if signal["action"] not in {"LONG", "SHORT"}:
        return False, "signal_action_not_executable"
    entry, stop, target = float(signal["entry"]), float(signal["stop"]), float(signal["target"])
    if min(entry, stop, target) <= 0:
        return False, "signal_prices_must_be_positive"
    if signal["action"] == "LONG" and not (stop < entry < target):
        return False, "invalid_long_levels"
    if signal["action"] == "SHORT" and not (target < entry < stop):
        return False, "invalid_short_levels"
    return True, "ok"


def simulate_signal(signal: dict, config: PaperConfig | None = None) -> dict:
    """Simulate one AI proposal after deterministic paper-only checks.

    This is deliberately not a broker adapter. It never sends an order and has no
    live credentials or external side effects.
    """
    config = config or PaperConfig()
    valid, reason = _validate_signal(signal)
    if not valid:
        return {"status": "REJECTED", "reason": reason, "mode": "paper", "real_money": False}

    entry = float(signal["entry"])
    stop = float(signal["stop"])
    target = float(signal["target"])
    risk_distance = abs(entry - stop)
    reward_distance = abs(target - entry)
    if risk_distance <= 0:
        return {"status": "REJECTED", "reason": "zero_risk_distance", "mode": "paper", "real_money": False}

    risk_budget = config.initial_capital * config.risk_per_trade
    raw_qty = risk_budget / risk_distance
    notional = raw_qty * entry
    max_notional = config.initial_capital * config.max_position_pct
    quantity = min(raw_qty, max_notional / entry)
    if quantity <= 0:
        return {"status": "REJECTED", "reason": "position_size_zero", "mode": "paper", "real_money": False}

    side = signal["action"]
    filled_entry = _fill_price(entry, side, config.slippage_bps, True)
    entry_fee = filled_entry * quantity * config.fee_rate
    gross_profit = reward_distance * quantity
    gross_loss = risk_distance * quantity
    exit_fee_target = target * quantity * config.fee_rate
    exit_fee_stop = stop * quantity * config.fee_rate
    target_pnl = gross_profit - entry_fee - exit_fee_target
    stop_pnl = -gross_loss - entry_fee - exit_fee_stop
    rr = reward_distance / risk_distance

    return {
        "status": "SIMULATED",
        "mode": "paper",
        "real_money": False,
        "side": side,
        "entry": round(filled_entry, 8),
        "stop": round(stop, 8),
        "target": round(target, 8),
        "quantity": round(quantity, 8),
        "notional": round(quantity * filled_entry, 8),
        "risk_budget": round(risk_budget, 8),
        "risk_distance": round(risk_distance, 8),
        "reward_distance": round(reward_distance, 8),
        "risk_reward": round(rr, 4),
        "fees": {"entry": round(entry_fee, 8), "target_exit": round(exit_fee_target, 8), "stop_exit": round(exit_fee_stop, 8)},
        "scenario": {"target_pnl": round(target_pnl, 8), "stop_pnl": round(stop_pnl, 8)},
        "execution_authority": "paper_simulator_only",
        "broker_order_sent": False,
    }
