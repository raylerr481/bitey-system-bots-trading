"""Built-in SBT bot strategies for deterministic demo/paper backtesting."""
from fastapi import APIRouter
from pydantic import BaseModel, Field

router = APIRouter(prefix="/api/v1/built-in-bots", tags=["built-in-bots"])


class BuiltInBotRequest(BaseModel):
    bot_type: str = Field(min_length=2, max_length=32)
    prices: list[float] = Field(min_length=40)
    initial_capital: float = Field(default=10000, gt=0)
    config: dict = Field(default_factory=dict)
    series: dict[str, list[float]] = Field(default_factory=dict)


class BuiltInRiskRequest(BaseModel):
    bot_type: str = Field(min_length=2, max_length=32)
    initial_capital: float = Field(default=10000, gt=0)
    config: dict = Field(default_factory=dict)


def _sma(x, n):
    return sum(x[-n:]) / n if len(x) >= n else None


def _ema_series(x, n):
    if len(x) < n:
        return []
    a = 2 / (n + 1)
    out = [sum(x[:n]) / n]
    for p in x[n:]:
        out.append(a * p + (1 - a) * out[-1])
    return out


def _rsi(x, n=14):
    if len(x) <= n:
        return 50.0
    gains = [max(0.0, x[i] - x[i-1]) for i in range(1, len(x))]
    losses = [max(0.0, x[i-1] - x[i]) for i in range(1, len(x))]
    ag = sum(gains[-n:]) / n
    al = sum(losses[-n:]) / n
    return 100.0 if al == 0 else 100 - 100 / (1 + ag / al)


def _atr(x, n=14):
    if len(x) <= n:
        return 0.0
    return sum(abs(x[i] - x[i-1]) for i in range(len(x)-n, len(x))) / n


def _run(prices, capital, signal_fn, fee=0.001):
    cash=float(capital); qty=0.0; entry=None; trades=wins=0; peak=capital; max_dd=0.0
    for i, price in enumerate(prices):
        action=signal_fn(prices,i)
        if action=="buy" and qty==0:
            qty=cash/(price*(1+fee)); cash=0.0; entry=price; trades+=1
        elif action=="sell" and qty>0:
            cash=qty*price*(1-fee)
            if entry is not None and price>entry: wins+=1
            qty=0.0; entry=None
        equity=cash+qty*price; peak=max(peak,equity)
        max_dd=max(max_dd,(peak-equity)/peak*100)
    final=cash+qty*prices[-1]
    return {"initial_capital":capital,"final_equity":final,"total_return_pct":(final/capital-1)*100,
            "trades":trades,"wins":wins,"losses":max(0,trades-wins),
            "win_rate_pct":wins/trades*100 if trades else 0,"max_drawdown_pct":max_dd,
            "mode":"DEMO/PAPER","live":False}


def _run_rebalance(series, capital, config, fee=0.001):
    """Multi-asset close-price rebalance simulation using cash as the numeraire."""
    clean={str(k): [float(v) for v in vals] for k, vals in (series or {}).items() if vals}
    if not clean or any(len(v) < 40 for v in clean.values()):
        return {"valid": False, "error": "Each rebalance asset needs at least 40 prices"}
    lengths={len(v) for v in clean.values()}
    if len(lengths) != 1 or any(any(x <= 0 for x in vals) for vals in clean.values()):
        return {"valid": False, "error": "Rebalance series must have equal length and positive prices"}
    assets=[a.strip() for a in str(config.get("assets", ",".join(clean))).split(",") if a.strip()]
    assets=[a for a in assets if a in clean or a.upper() in {"USDT","USD","CASH"}]
    investable=[a for a in assets if a in clean]
    if not investable:
        return {"valid": False, "error": "No investable asset series supplied"}
    weights={}
    for a in investable:
        key="btc" if a.upper().startswith("BTC") else "eth" if a.upper().startswith("ETH") else a.lower().replace("/", "_").replace("-", "_")
        weights[a]=max(0.0, float(config.get(key, 0))) / 100.0
    cash_weight=max(0.0, float(config.get("cash", max(0.0, 100.0-sum(weights.values())*100.0)))) / 100.0
    total=sum(weights.values())+cash_weight
    if total <= 0: return {"valid": False, "error": "Target weights must be greater than zero"}
    weights={a:w/total for a,w in weights.items()}; cash_weight=cash_weight/total
    n=next(iter(lengths)); cash=capital*cash_weight
    qty={a:(capital*weights[a]) / clean[a][0] for a in investable}
    threshold=max(0.0, float(config.get("threshold", 5))) / 100.0
    frequency=max(1, int(config.get("frequency", 20)))
    trades=rebalance_count=0; wins=0; peak=capital; max_dd=0.0; equity_curve=[]; previous_equity=capital
    for i in range(n):
        equity=cash+sum(qty[a]*clean[a][i] for a in investable)
        peak=max(peak,equity); max_dd=max(max_dd,(peak-equity)/peak*100.0); equity_curve.append(round(equity,8))
        drift=max((abs((qty[a]*clean[a][i])/equity-weights[a]) for a in investable), default=0.0)
        if i > 0 and (drift >= threshold or i % frequency == 0) and i < n-1:
            fee_value=equity*fee; cash=max(0.0,cash-fee_value); trades += 1; rebalance_count += 1
            for a in investable:
                target_value=equity*weights[a]
                qty[a]=target_value/clean[a][i]
            cash=equity*cash_weight-fee_value
            if equity > previous_equity: wins += 1
        previous_equity=equity
    final=equity_curve[-1]
    return {"valid": True, "initial_capital": capital, "final_equity": final,
            "total_return_pct": (final/capital-1)*100.0, "trades": trades,
            "rebalance_count": rebalance_count, "wins": wins, "losses": max(0,trades-wins),
            "win_rate_pct": wins/trades*100.0 if trades else 0.0,
            "max_drawdown_pct": max_dd, "equity_curve": equity_curve,
            "target_weights_pct": {a: round(weights[a]*100.0,2) for a in investable} | {"cash": round(cash_weight*100.0,2)},
            "mode": "DEMO/PAPER", "live": False}


def _signal(kind,c):
    def fn(p,i):
        if i<35:return "hold"
        if kind=="grid":
            lo=float(c.get("lower",min(p[-30:]))); hi=float(c.get("upper",max(p[-30:])))
            grids=max(2,int(c.get("grids",20))); step=(hi-lo)/grids
            if step<=0:return "hold"
            a=round((p[i]-lo)/step); b=round((p[i-1]-lo)/step)
            return "buy" if a<b and p[i]<=hi else ("sell" if a>b and p[i]>=lo else "hold")
        if kind=="dca":
            step=float(c.get("step",3))/100; take=float(c.get("take",2))/100
            return "buy" if p[i]<p[i-1]*(1-step) else ("sell" if p[i]>p[i-1]*(1+take) else "hold")
        if kind=="trend":
            fast=int(c.get("emaFast",9)); slow=int(c.get("emaSlow",21)); r=float(c.get("rsi",50))
            ef=_ema_series(p[:i+1],fast); es=_ema_series(p[:i+1],slow)
            if not ef or not es:return "hold"
            return "buy" if ef[-1]>es[-1] and _rsi(p[:i+1])>=r else ("sell" if ef[-1]<es[-1] else "hold")
        if kind=="breakout":
            n=int(c.get("lookback",20)); a=float(c.get("atr",1.5))*_atr(p[:i+1])
            hi=max(p[i-n:i]); lo=min(p[i-n:i])
            return "buy" if p[i]>hi+a else ("sell" if p[i]<lo-a else "hold")
        if kind=="mean-reversion":
            n=20; mid=_sma(p[:i+1],n)
            dev=(sum((v-mid)**2 for v in p[i-n+1:i+1])/n)**0.5
            r=_rsi(p[:i+1]); low=float(c.get("rsiLow",30)); high=float(c.get("rsiHigh",70))
            return "buy" if p[i]<mid-2*dev and r<=low else ("sell" if p[i]>mid+2*dev and r>=high else "hold")
        if kind=="rebalance":
            return "buy" if i==35 else ("sell" if (i-35)%20==0 else "hold")
        return "hold"
    return fn


@router.post("/backtest")
def built_in_backtest(request: BuiltInBotRequest):
    kind=request.bot_type.lower()
    if kind not in {"grid","dca","trend","breakout","mean-reversion","rebalance"}:
        return {"valid":False,"error":"Unsupported built-in bot type","live":False}
    if kind == "rebalance":
        result=_run_rebalance(request.series,request.initial_capital,request.config)
        if not result.get("valid"): return {**result,"live":False}
        return {"valid":True,"contract":"sbt-built-in-bot-v2","bot_type":kind,**result,"note":"Multi-asset close-price rebalance simulation; not a live execution forecast."}
    prices=[float(x) for x in request.prices]
    if any(x<=0 for x in prices):
        return {"valid":False,"error":"Prices must be positive","live":False}
    return {"valid":True,"contract":"sbt-built-in-bot-v1","bot_type":kind,
            **_run(prices,request.initial_capital,_signal(kind,request.config)),
            "note":"Deterministic close-price simulation; not a live execution forecast."}



@router.post("/risk-preview")
def built_in_risk_preview(request: BuiltInRiskRequest):
    kind=request.bot_type.lower()
    limits = {
        "grid": (0.20, 0.02, 0.04),
        "dca": (0.15, 0.02, 0.04),
        "trend": (0.10, 0.015, 0.03),
        "breakout": (0.10, 0.02, 0.04),
        "mean-reversion": (0.10, 0.015, 0.03),
        "rebalance": (0.25, 0.01, 0.02),
    }
    if kind not in limits:
        return {"valid": False, "error": "Unsupported built-in bot type", "live": False}
    position_pct, trade_loss_pct, daily_loss_pct = limits[kind]
    capital = request.initial_capital
    return {
        "valid": True,
        "contract": "sbt-built-in-risk-v1",
        "bot_type": kind,
        "capital": capital,
        "max_position_value": round(capital * position_pct, 8),
        "max_position_pct": position_pct * 100,
        "configured_loss_per_trade": round(capital * trade_loss_pct, 8),
        "configured_loss_per_trade_pct": trade_loss_pct * 100,
        "configured_daily_loss": round(capital * daily_loss_pct, 8),
        "configured_daily_loss_pct": daily_loss_pct * 100,
        "mode": "DEMO/PAPER",
        "live": False,
        "warning": "Configuración preventiva; no protege contra gaps, slippage ni fallos de ejecución."
    }


@router.post("/robustness")
def built_in_robustness(request: BuiltInBotRequest):
    kind=request.bot_type.lower()
    if kind not in {"grid", "dca", "trend", "breakout", "mean-reversion", "rebalance"}:
        return {"valid": False, "error": "Unsupported built-in bot type", "live": False}
    prices=[float(x) for x in request.prices]
    if any(x <= 0 for x in prices):
        return {"valid": False, "error": "Prices must be positive", "live": False}
    split=max(20, int(len(prices) * 0.70))
    if split >= len(prices) - 10:
        return {"valid": False, "error": "Insufficient data for robustness split", "live": False}
    train=prices[:split]
    test=prices[split:]
    base=_run(prices, request.initial_capital, _signal(kind, request.config))
    oos=_run(test, request.initial_capital, _signal(kind, request.config))
    stress=_run(prices, request.initial_capital, _signal(kind, request.config), fee=0.002)
    score=0.0
    score += max(0.0, min(40.0, oos["total_return_pct"] * 4.0 + 20.0))
    score += max(0.0, min(30.0, 30.0 - oos["max_drawdown_pct"] * 2.0))
    score += 15.0 if oos["trades"] >= 3 else 7.5 if oos["trades"] >= 1 else 0.0
    score += 15.0 if stress["total_return_pct"] >= -2.0 else 5.0 if stress["total_return_pct"] >= -5.0 else 0.0
    status="PASS" if score >= 60 and oos["trades"] >= 1 else "REVIEW"
    return {
        "valid": True,
        "contract": "sbt-built-in-robustness-v1",
        "bot_type": kind,
        "score": round(score, 2),
        "status": status,
        "in_sample_points": len(train),
        "out_of_sample_points": len(test),
        "base": base,
        "out_of_sample": oos,
        "fee_stress_0_20pct": stress,
        "mode": "DEMO/PAPER",
        "live": False,
        "note": "Heurística de robustness para screening; no constituye garantía ni optimización estadística."
    }


@router.post("/demo/simulate")
def built_in_demo_simulate(request: BuiltInBotRequest):
    """Run a deterministic virtual session. This endpoint never places live orders."""
    kind = request.bot_type.lower()
    allowed = {"grid", "dca", "trend", "breakout", "mean-reversion", "rebalance"}
    if kind not in allowed:
        return {"valid": False, "error": "Unsupported built-in bot type", "live": False}
    prices = [float(x) for x in request.prices]
    if any(x <= 0 for x in prices):
        return {"valid": False, "error": "Prices must be positive", "live": False}
    signal = _signal(kind, request.config)
    result = _run(prices, request.initial_capital, signal)
    equity = []
    cash = float(request.initial_capital)
    qty = 0.0
    fee = 0.001
    for i, price in enumerate(prices):
        action = signal(prices, i)
        if action == "buy" and qty == 0:
            qty = cash / (price * (1 + fee)); cash = 0.0
        elif action == "sell" and qty > 0:
            cash = qty * price * (1 - fee); qty = 0.0
        equity.append(round(cash + qty * price, 8))
    return {"valid": True, "contract": "sbt-built-in-demo-v1", "bot_type": kind,
            "session_mode": "VIRTUAL", "live": False, "virtual_orders": True,
            "initial_capital": request.initial_capital, "final_equity": result["final_equity"],
            "total_return_pct": result["total_return_pct"], "trades": result["trades"],
            "wins": result["wins"], "losses": result["losses"],
            "win_rate_pct": result["win_rate_pct"], "max_drawdown_pct": result["max_drawdown_pct"],
            "equity_curve": equity,
            "note": "Simulación virtual determinista. No se envían órdenes a ningún broker o exchange."}



class PerformanceSnapshotRequest(BaseModel):
    equity_curve: list[float] = Field(min_length=2)
    trades: int = Field(default=0, ge=0)
    wins: int = Field(default=0, ge=0)
    initial_capital: float = Field(default=10000, gt=0)
    mode: str = Field(default="PAPER", max_length=16)


@router.post("/performance/snapshot")
def built_in_performance_snapshot(request: PerformanceSnapshotRequest):
    """Summarize a deterministic demo/paper equity curve. Never places orders."""
    curve = [float(x) for x in request.equity_curve]
    if any(x <= 0 for x in curve):
        return {"valid": False, "error": "Equity values must be positive", "live": False}
    peak = curve[0]
    max_dd = 0.0
    for equity in curve:
        peak = max(peak, equity)
        if peak > 0:
            max_dd = max(max_dd, (peak - equity) / peak * 100.0)
    final = curve[-1]
    pnl = final - request.initial_capital
    returns = pnl / request.initial_capital * 100.0
    losses = max(0, request.trades - request.wins)
    avg_trade = pnl / request.trades if request.trades else 0.0
    gross_profit = 0.0
    gross_loss = 0.0
    for prev, curr in zip(curve, curve[1:]):
        delta = curr - prev
        if delta > 0:
            gross_profit += delta
        elif delta < 0:
            gross_loss += abs(delta)
    profit_factor = gross_profit / gross_loss if gross_loss > 0 else (999.0 if gross_profit > 0 else 0.0)
    return {
        "valid": True,
        "contract": "sbt-performance-v1",
        "mode": request.mode.upper(),
        "live": False,
        "initial_capital": request.initial_capital,
        "final_equity": final,
        "pnl": pnl,
        "return_pct": returns,
        "peak_equity": peak,
        "max_drawdown_pct": max_dd,
        "trades": request.trades,
        "wins": min(request.wins, request.trades),
        "losses": losses,
        "win_rate_pct": (request.wins / request.trades * 100.0) if request.trades else 0.0,
        "profit_factor": profit_factor,
        "avg_trade": avg_trade,
        "equity_curve": curve,
        "status": "POSITIVE" if pnl > 0 else "FLAT" if pnl == 0 else "NEGATIVE",
        "note": "Resumen de performance de una simulación DEMO/PAPER; no es una previsión de rentabilidad."
    }


@router.post("/paper/simulate")
def built_in_paper_simulate(request: BuiltInBotRequest):
    """Run a broker-free paper session using the deterministic SBT engine."""
    kind = request.bot_type.lower()
    allowed = {"grid", "dca", "trend", "breakout", "mean-reversion", "rebalance"}
    if kind not in allowed:
        return {"valid": False, "error": "Unsupported built-in bot type", "live": False}
    prices = [float(x) for x in request.prices]
    if any(x <= 0 for x in prices):
        return {"valid": False, "error": "Prices must be positive", "live": False}
    signal = _signal(kind, request.config)
    result = _run(prices, request.initial_capital, signal)
    equity = []
    cash = float(request.initial_capital)
    qty = 0.0
    fee = 0.001
    for i, price in enumerate(prices):
        action = signal(prices, i)
        if action == "buy" and qty == 0:
            qty = cash / (price * (1 + fee)); cash = 0.0
        elif action == "sell" and qty > 0:
            cash = qty * price * (1 - fee); qty = 0.0
        equity.append(round(cash + qty * price, 8))
    return {"valid": True, "contract": "sbt-built-in-paper-v1", "bot_type": kind,
            "session_mode": "PAPER", "live": False, "virtual_orders": True,
            "initial_capital": request.initial_capital, "final_equity": result["final_equity"],
            "total_return_pct": result["total_return_pct"], "trades": result["trades"],
            "wins": result["wins"], "losses": result["losses"],
            "win_rate_pct": result["win_rate_pct"], "max_drawdown_pct": result["max_drawdown_pct"],
            "equity_curve": equity,
            "note": "Paper trading broker-free. No orders are sent to any broker or exchange."}
