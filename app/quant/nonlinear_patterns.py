from __future__ import annotations

from math import sqrt
from statistics import mean, pstdev
from typing import Any


def _returns(closes: list[float]) -> list[float]:
    return [closes[i] / closes[i-1] - 1.0 for i in range(1, len(closes))]


def _std(xs: list[float]) -> float:
    return pstdev(xs) if len(xs) > 1 else 0.0


def _quantile(xs: list[float], q: float) -> float:
    if not xs: return 0.0
    a=sorted(xs); pos=(len(a)-1)*q; lo=int(pos); hi=min(lo+1,len(a)-1); w=pos-lo
    return a[lo]*(1-w)+a[hi]*w


def _z(v: float, xs: list[float]) -> float:
    s=_std(xs); return (v-mean(xs))/s if s > 1e-12 else 0.0


def _window_signature(closes: list[float], end: int, width: int) -> list[float]:
    w=closes[end-width:end]
    base=w[0]
    return [(x/base-1.0) for x in w]


def _distance(a: list[float], b: list[float]) -> float:
    return sqrt(sum((x-y)**2 for x,y in zip(a,b))/max(1,len(a)))


def mine_nonlinear_patterns(
    bars: list[dict[str, Any]],
    window: int = 16,
    horizon: int = 8,
    neighbors: int = 12,
    min_support: int = 8,
) -> dict[str, Any]:
    if len(bars) < max(120, window+horizon+30):
        raise ValueError("at least 120 bars are required")
    rows=sorted(bars, key=lambda x: float(x.get("timestamp",0)))
    closes=[float(x["close"]) for x in rows]
    highs=[float(x["high"]) for x in rows]
    lows=[float(x["low"]) for x in rows]
    rets=_returns(closes)
    observations=[]
    for end in range(window+20, len(closes)-horizon):
        r=rets[end-window:end]
        sig=_window_signature(closes,end,window)
        vol=_std(r)
        momentum=closes[end]/closes[end-window]-1.0
        rng=(max(highs[end-window:end])-min(lows[end-window:end]))/closes[end]
        location=(closes[end]-min(lows[end-window:end]))/max(1e-12,max(highs[end-window:end])-min(lows[end-window:end]))
        forward=closes[end+horizon]/closes[end]-1.0
        observations.append({"end":end,"signature":sig,"vol":vol,"momentum":momentum,"range":rng,"location":location,"forward":forward})
    vols=[x["vol"] for x in observations]; moms=[x["momentum"] for x in observations]
    patterns=[]
    # Nonlinear interaction regimes: momentum x volatility x price-location.
    thresholds={
        "vol_low":_quantile(vols,.33),"vol_high":_quantile(vols,.67),
        "mom_low":_quantile(moms,.33),"mom_high":_quantile(moms,.67),
    }
    buckets={}
    for o in observations:
        vb="LOW" if o["vol"]<=thresholds["vol_low"] else "HIGH" if o["vol"]>=thresholds["vol_high"] else "MID"
        mb="NEG" if o["momentum"]<=thresholds["mom_low"] else "POS" if o["momentum"]>=thresholds["mom_high"] else "MID"
        lb="LOW" if o["location"]<.33 else "HIGH" if o["location"]>.67 else "MID"
        key=f"MOM_{mb}__VOL_{vb}__LOC_{lb}"
        buckets.setdefault(key,[]).append(o)
    base=mean(x["forward"] for x in observations)
    for key,items in buckets.items():
        if len(items)<min_support: continue
        f=[x["forward"] for x in items]
        patterns.append({
            "pattern":key,"support":len(items),"support_pct":len(items)/len(observations),
            "mean_forward_return":mean(f),"median_forward_return":_quantile(f,.5),
            "hit_rate":sum(1 for x in f if x>0)/len(f),
            "lift_vs_base":mean(f)-base,"volatility":_std(f),
        })
    # Motif mining: nearest historical windows to the most recent window.
    target=_window_signature(closes,len(closes),window)
    candidates=[]
    for o in observations[:-horizon]:
        candidates.append((_distance(target,o["signature"]),o))
    candidates.sort(key=lambda x:x[0])
    chosen=[o for _,o in candidates[:neighbors]]
    f=[x["forward"] for x in chosen]
    motif={
        "window":window,"neighbors":len(chosen),
        "mean_forward_return":mean(f) if f else 0.0,
        "median_forward_return":_quantile(f,.5) if f else 0.0,
        "hit_rate":sum(1 for x in f if x>0)/len(f) if f else 0.0,
        "mean_distance":mean(d for d,_ in candidates[:neighbors]) if chosen else 0.0,
        "support":len(chosen),
    }
    patterns.sort(key=lambda x:x["lift_vs_base"],reverse=True)
    return {
        "contract":"sbt-nonlinear-pattern-mining-v1",
        "method":"quantile interaction mining + nearest-neighbor shape motifs",
        "data_hygiene":{
            "lookahead_free":True,
            "pattern_uses_only_prior_bars":True,
            "forward_horizon_bars":horizon,
            "min_support":min_support,
        },
        "observations":len(observations),
        "base_forward_return":base,
        "thresholds":thresholds,
        "top_positive_patterns":patterns[:8],
        "top_negative_patterns":sorted(patterns,key=lambda x:x["lift_vs_base"])[:8],
        "latest_shape_motif":motif,
        "research_only":True,
        "execution_enabled":False,
        "real_money":False,
    }
