from __future__ import annotations

from dataclasses import dataclass
import math
import random
import statistics


@dataclass(frozen=True)
class AR001Spec:
    hypothesis_id: str = "AR-001"
    source: str = "Alex Ruiz"
    video_id: str = "QY7Kchg9nEU"
    risk_pct: float = 0.01
    allocation: tuple[float, float, float] = (0.25, 0.40, 0.35)
    atr_period: int = 14
    atr_multipliers: tuple[float, float, float] = (0.0, 2.0, 3.0)
    stop_atr: float = 4.0
    take_profit_r: float = 3.0
    live: bool = False
    real_money: bool = False
    broker_orders: int = 0


def ar001_spec() -> dict:
    s = AR001Spec()
    return {"contract":"sbt-ar001-v2","hypothesis_id":s.hypothesis_id,"source":s.source,"video_id":s.video_id,
            "claim":"A staged 25/40/35 entry in an ATR-defined zone can improve average entry while keeping aggregate stop risk inside a fixed budget and producing positive expectancy after costs.",
            "status":"UNTESTED","parameters":{"risk_pct":s.risk_pct,"allocation":list(s.allocation),"atr_period":s.atr_period,"atr_multipliers":list(s.atr_multipliers),"stop_atr":s.stop_atr,"take_profit_r":s.take_profit_r},
            "falsification":["Reject if aggregate stop loss exceeds the configured risk budget.","Reject if OOS expectancy is not positive after fees/slippage.","Reject if bootstrap 95% lower bound of OOS expectancy is not above zero.","Reject if stress evidence is unstable or the minimum sample is not reached."],
            "evidence_protocol":{"minimum_trades":100,"minimum_oos_trades":30,"minimum_bootstrap_samples":2000,"approval_rule":"OOS expectancy > 0R, profit factor > 1, bootstrap 95% lower bound > 0R, positive stress scenarios, valid sizing."},
            "backtest_contract":"sbt-ar001-ohlc-v1","note":"The OHLC model tests a defined research model; it does not prove future profitability or every claim in the source video.",
            "safety":{"live":False,"real_money":False,"broker_orders":0}}


def _weights(weights: list[float] | None) -> list[float]:
    w=weights or [0.25,0.40,0.35]
    if len(w)!=3 or any(x<=0 for x in w) or abs(sum(w)-1)>1e-9: raise ValueError("weights must contain three positive values summing to 1")
    return w


def size_staged_entries(capital: float, risk_pct: float, entries: list[float], stop: float, weights: list[float] | None=None, point_value: float=1.0) -> dict:
    if capital<=0 or risk_pct<=0 or risk_pct>0.05 or point_value<=0 or stop<=0: raise ValueError("invalid sizing parameters")
    if len(entries)!=3: raise ValueError("AR-001 requires exactly three staged entries")
    w=_weights(weights); budget=capital*risk_pct; rows=[]
    for entry,weight in zip(entries,w):
        d=abs(entry-stop)
        if d==0: raise ValueError("entry cannot equal stop")
        q=(budget*weight)/(d*point_value)
        rows.append({"entry":entry,"weight":weight,"risk_budget":budget*weight,"distance_to_stop":d,"quantity":q,"stop_loss":q*d*point_value})
    total=sum(x["stop_loss"] for x in rows)
    avg=sum(x["entry"]*x["quantity"] for x in rows)/sum(x["quantity"] for x in rows)
    return {"contract":"sbt-ar001-sizing-v1","hypothesis_id":"AR-001","risk_budget":budget,"entries":rows,"total_stop_risk":total,"risk_within_budget":total<=budget*(1+1e-9),"weighted_average_entry":avg,"safety":{"live":False,"real_money":False,"broker_orders":0}}


def _atr(bars: list[dict[str,float]], period: int) -> list[float]:
    out=[0.0]*len(bars); trs=[]; prev=None
    for i,b in enumerate(bars):
        h,l,c=float(b["high"]),float(b["low"]),float(b["close"])
        tr=h-l if prev is None else max(h-l,abs(h-prev),abs(l-prev)); trs.append(tr)
        if i+1>=period: out[i]=sum(trs[-period:])/period
        prev=c
    return out


def _slip(price: float, side: str, bps: float) -> float:
    return price*(1+bps/10000) if side=="buy" else price*(1-bps/10000)


def backtest_ar001_ohlc(bars: list[dict[str,float]], *, initial_capital:float=10000, risk_pct:float=0.01, atr_period:int=14,
                         entry_multipliers:list[float]|None=None, stop_atr:float=4.0, take_profit_r:float=3.0,
                         direction:str="long", fee_bps:float=0.0, slippage_bps:float=0.0,
                         weights:list[float]|None=None, point_value:float=1.0, max_bars_per_trade:int=250) -> dict:
    if len(bars)<atr_period+5 or initial_capital<=0 or not 0<risk_pct<=0.05: raise ValueError("insufficient bars or invalid capital/risk")
    if direction not in {"long","short"}: raise ValueError("direction must be long or short")
    if stop_atr<=0 or take_profit_r<=0 or fee_bps<0 or slippage_bps<0: raise ValueError("invalid execution parameters")
    mult=entry_multipliers or [0.0,2.0,3.0]
    if len(mult)!=3 or any(x<0 for x in mult): raise ValueError("entry_multipliers must contain three non-negative values")
    w=_weights(weights); atr=_atr(bars,atr_period); equity=float(initial_capital); peak=equity; max_dd=0.0; trades=[]; rs=[]; i=atr_period
    while i<len(bars)-1:
        a=atr[i]
        if a<=0: i+=1; continue
        anchor=float(bars[i]["close"]); sign=1 if direction=="long" else -1
        entries=[anchor-sign*m*a for m in mult]; stop=anchor-sign*stop_atr*a
        sizing=size_staged_entries(equity,risk_pct,entries,stop,w,point_value); budget=sizing["risk_budget"]
        fills=[{"price":_slip(entries[0],"buy" if sign==1 else "sell",slippage_bps),"quantity":sizing["entries"][0]["quantity"],"weight":w[0],"index":i}]
        weighted=fills[0]["price"]*w[0]; total_q=fills[0]["quantity"]; last_fill=i; exit_idx=None; exit_price=None; reason=None; target=None
        end=min(len(bars),i+max_bars_per_trade+1)
        for j in range(i+1,end):
            b=bars[j]
            stop_hit=(b["low"]<=stop) if sign==1 else (b["high"]>=stop)
            if stop_hit:
                exit_idx=j; exit_price=_slip(stop,"sell" if sign==1 else "buy",slippage_bps); reason="stop"; break
            for k in (1,2):
                if len(fills)>k: continue
                level=entries[k]; hit=(b["low"]<=level) if sign==1 else (b["high"]>=level)
                if hit:
                    fp=_slip(level,"buy" if sign==1 else "sell",slippage_bps); fills.append({"price":fp,"quantity":sizing["entries"][k]["quantity"],"weight":w[k],"index":j}); weighted+=fp*w[k]; total_q+=sizing["entries"][k]["quantity"]; last_fill=j
            avg=weighted/sum(f["weight"] for f in fills); actual_risk=sum(f["quantity"]*abs(f["price"]-stop)*point_value for f in fills); target=avg+sign*take_profit_r*actual_risk/(total_q*point_value)
            tp_hit=(b["high"]>=target) if sign==1 else (b["low"]<=target)
            if tp_hit:
                exit_idx=j; exit_price=_slip(target,"sell" if sign==1 else "buy",slippage_bps); reason="take_profit"; break
        if exit_idx is None:
            exit_idx=end-1; exit_price=_slip(float(bars[exit_idx]["close"]),"sell" if sign==1 else "buy",slippage_bps); reason="time_exit"
        gross=sum((exit_price-f["price"])*f["quantity"]*point_value*sign for f in fills)
        turnover=sum(f["price"]*f["quantity"]*point_value for f in fills)+exit_price*total_q*point_value; costs=turnover*fee_bps/10000; pnl=gross-costs; r=pnl/budget if budget else 0
        equity+=pnl; peak=max(peak,equity); max_dd=max(max_dd,(peak-equity)/peak*100); avg=weighted/sum(f["weight"] for f in fills); path=bars[i:exit_idx+1]
        if sign==1: mae=min((float(b["low"])-avg)/avg for b in path); mfe=max((float(b["high"])-avg)/avg for b in path)
        else: mae=min((avg-float(b["high"]))/avg for b in path); mfe=max((avg-float(b["low"]))/avg for b in path)
        trades.append({"entry_index":i,"exit_index":exit_idx,"fills":len(fills),"average_entry":avg,"entries":entries,"stop":stop,"target":target,"exit":exit_price,"reason":reason,"pnl":pnl,"r_multiple":r,"costs":costs,"mae_pct":mae*100,"mfe_pct":mfe*100}); rs.append(r); i=max(exit_idx+1,last_fill+1)
    wins=sum(x>0 for x in rs); losses=sum(x<0 for x in rs); gp=sum(x for x in rs if x>0); gl=-sum(x for x in rs if x<0)
    return {"contract":"sbt-ar001-ohlc-v1","hypothesis_id":"AR-001","direction":direction,"initial_capital":initial_capital,"final_equity":equity,"total_return_pct":(equity/initial_capital-1)*100,"trades":len(trades),"wins":wins,"losses":losses,"win_rate":wins/len(trades) if trades else None,"profit_factor":gp/gl if gl else (math.inf if gp else 0.0),"max_drawdown_pct":max_dd,"mean_r":statistics.fmean(rs) if rs else None,"trades_r":rs,"trades_detail":trades,"mean_mae_pct":statistics.fmean(x["mae_pct"] for x in trades) if trades else None,"mean_mfe_pct":statistics.fmean(x["mfe_pct"] for x in trades) if trades else None,"fee_bps":fee_bps,"slippage_bps":slippage_bps,"safety":{"live":False,"real_money":False,"broker_orders":0}}


def _profit_factor(rs:list[float])->float:
    gains=sum(x for x in rs if x>0); losses=-sum(x for x in rs if x<0); return math.inf if losses==0 and gains>0 else (gains/losses if losses else 0.0)


def _max_drawdown(rs:list[float])->float:
    eq=peak=1.0; dd=0.0
    for r in rs:
        eq*=max(0.000001,1+r); peak=max(peak,eq); dd=max(dd,(peak-eq)/peak)
    return dd


def _bootstrap_lower_bound(rs:list[float],samples:int=2000,seed:int=1001)->float:
    if not rs:return 0.0
    rng=random.Random(seed); n=len(rs); means=[sum(rs[rng.randrange(n)] for _ in range(n))/n for _ in range(samples)]; means.sort(); return means[max(0,int(0.025*len(means))-1)]


def evaluate_ar001_evidence(r_multiples:list[float],oos_start:int|None=None,stress_results:list[float]|None=None,risk_sizing_ok:bool=True,bootstrap_samples:int=2000)->dict:
    if not r_multiples:
        return _evidence_result("EVIDENCE_INSUFFICIENT",["No trade outcomes supplied."],{"sample_size":0,"oos_sample_size":0,"oos_expectancy_R":0.0,"oos_profit_factor":0.0,"oos_max_drawdown_pct":0.0,"bootstrap_95_lower_bound_R":0.0,"stress_scenarios":len(stress_results or []),"positive_stress":bool(stress_results) and all(x>0 for x in stress_results),"oos_start":oos_start})
    if any(not math.isfinite(x) for x in r_multiples):raise ValueError("r_multiples must contain finite numbers")
    n=len(r_multiples)
    if n==1:
        oos=r_multiples; split=0
    else:
        split=oos_start if oos_start is not None else max(1,n//2)
        if split<=0 or split>=n:raise ValueError("oos_start must leave both samples")
        oos=r_multiples[split:]
    exp=statistics.fmean(oos); pf=_profit_factor(oos); lower=_bootstrap_lower_bound(oos,max(2000,bootstrap_samples)); stress=stress_results or []; failures=[]
    if not risk_sizing_ok: failures.append("Aggregate stop risk exceeds the configured risk budget.")
    if n<100: failures.append("Minimum sample of 100 trades not reached.")
    if len(oos)<30: failures.append("Minimum out-of-sample sample of 30 trades not reached.")
    if exp<=0: failures.append("Out-of-sample expectancy is not positive.")
    if pf<=1: failures.append("Out-of-sample profit factor is not above 1.")
    if lower<=0: failures.append("Bootstrap 95% lower bound of expectancy is not above zero.")
    if not stress or not all(x>0 for x in stress): failures.append("Stress evidence is missing or not positive in every supplied scenario.")
    status="APPROVED" if not failures else ("REJECTED" if n>=100 and len(oos)>=30 and (exp<=0 or pf<=1 or lower<=0 or not risk_sizing_ok) else "EVIDENCE_INSUFFICIENT")
    return _evidence_result(status,failures,{"sample_size":n,"oos_sample_size":len(oos),"oos_expectancy_R":exp,"oos_profit_factor":pf,"oos_max_drawdown_pct":_max_drawdown(oos)*100,"bootstrap_95_lower_bound_R":lower,"stress_scenarios":len(stress),"positive_stress":bool(stress) and all(x>0 for x in stress),"oos_start":split})


def _evidence_result(status:str,reasons:list[str],metrics:dict)->dict:
    return {"contract":"sbt-ar001-evidence-v1","hypothesis_id":"AR-001","status":status,"reasons":reasons,"metrics":metrics,"interpretation":"APPROVED means the supplied dataset passed the default evidence protocol; it does not prove future profitability.","safety":{"live":False,"real_money":False,"broker_orders":0}}
