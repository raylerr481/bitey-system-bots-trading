"""Preventive Bot Guardian: read-only risk assessment and safe change proposals.

Never places orders, changes MT4 mode, disables stops, raises risk, or bypasses Risk Gate.
"""
from __future__ import annotations
from datetime import datetime, timezone
from typing import Any
from fastapi import APIRouter
from pydantic import BaseModel, Field

router=APIRouter(prefix="/api/v1/guardian",tags=["preventive-guardian"])
_ORDER={"NORMAL":0,"WARNING":1,"DEFENSIVE":2,"REDUCE_RISK":3,"PAUSE":4,"EMERGENCY_STOP":5}

class GuardianSnapshot(BaseModel):
    mode:str="UNKNOWN"
    balance:float|None=None
    equity:float|None=None
    drawdown_pct:float=Field(default=0,ge=0)
    daily_loss_pct:float=Field(default=0,ge=0)
    monthly_loss_pct:float=Field(default=0,ge=0)
    risk_pct:float=Field(default=0,ge=0)
    margin_level_pct:float|None=Field(default=None,ge=0)
    spread_points:float|None=Field(default=None,ge=0)
    consecutive_losses:int=Field(default=0,ge=0)
    volatility_pct:float|None=Field(default=None,ge=0)

def _raise_state(state:str,candidate:str)->str:
    return candidate if _ORDER[candidate]>_ORDER[state] else state

def assess_guardian(s:GuardianSnapshot)->dict[str,Any]:
    mode=s.mode.upper(); state="NORMAL"; reasons=[]
    if s.drawdown_pct>=5 or s.daily_loss_pct>=2:
        state="REDUCE_RISK"; reasons.append("loss/drawdown threshold reached")
    if s.drawdown_pct>=8 or s.daily_loss_pct>=3:
        state=_raise_state(state,"PAUSE"); reasons.append("severe loss/drawdown threshold reached")
    if s.drawdown_pct>=10 or s.daily_loss_pct>=4:
        state=_raise_state(state,"EMERGENCY_STOP"); reasons.append("emergency protection threshold reached")
    if s.margin_level_pct is not None and s.margin_level_pct<300:
        state=_raise_state(state,"DEFENSIVE"); reasons.append("low margin level")
    if s.consecutive_losses>=5:
        state=_raise_state(state,"WARNING"); reasons.append("loss streak detected")
    if s.spread_points is not None and s.spread_points>50:
        state=_raise_state(state,"DEFENSIVE"); reasons.append("elevated spread")
    if s.volatility_pct is not None and s.volatility_pct>3:
        state=_raise_state(state,"DEFENSIVE"); reasons.append("elevated volatility")
    proposals=[]
    if state in {"WARNING","DEFENSIVE"}: proposals+=["tighten_entry_filter","reduce_new_entry_frequency"]
    if state=="REDUCE_RISK": proposals+=["reduce_position_size","block_new_entries"]
    if state in {"PAUSE","EMERGENCY_STOP"}: proposals+=["pause_new_entries","preserve_existing_stops"]
    return {
      "contract":"sbt-preventive-guardian-v1","timestamp":datetime.now(timezone.utc).isoformat(),
      "state":state,"reasons":reasons,"environment":mode,
      "automatic_mode_switch":False,"trader_controls_mode":True,
      "risk_increase_allowed":False,"risk_gate_mutable":False,"unsafe_changes_blocked":True,
      "proposals":proposals,
      "note":"Read-only assessment. Applying a proposal requires a separate validated MT4 change path."
    }

@router.post("/assess")
def assess(snapshot:GuardianSnapshot): return assess_guardian(snapshot)

@router.get("/policy")
def policy():
    return {"contract":"sbt-preventive-guardian-policy-v1","mode_authority":"TRADER_IN_MT4",
      "automatic_mode_switch":False,"risk_increase_allowed":False,
      "allow":["reduce_position_size","tighten_entry_filter","reduce_new_entry_frequency","block_new_entries","pause_new_entries","preserve_existing_stops"],
      "deny":["increase_lot_size","increase_max_risk","disable_stop","increase_max_drawdown","change_mt4_mode","place_broker_order","bypass_risk_gate"],
      "protective_thresholds":{"drawdown_pct":10,"daily_loss_pct":4},
      "note":"Thresholds are protective controls, not guarantees against gaps or slippage."}
