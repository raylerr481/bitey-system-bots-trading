(() => {
  const state = { timer: null };
  const el = (id) => document.getElementById(id);
  function values() {
    const m = window.BiteySBTMarketState || {};
    const cs = Array.isArray(m.candles) ? m.candles : [];
    if (cs.length < 22) return null;
    const close = cs.map(c => Number(c.close));
    const ema = (v,p) => { if (v.length < p) return null; let x=v.slice(0,p).reduce((a,b)=>a+b,0)/p, a=2/(p+1); for(let i=p;i<v.length;i++) x=a*v[i]+(1-a)*x; return x; };
    const rsi = (v,p=14) => { if(v.length<=p) return null; let g=0,l=0; for(let i=1;i<=p;i++){const d=v[i]-v[i-1];g+=Math.max(d,0);l+=Math.max(-d,0);} let ag=g/p,al=l/p; for(let i=p+1;i<v.length;i++){const d=v[i]-v[i-1];ag=(ag*(p-1)+Math.max(d,0))/p;al=(al*(p-1)+Math.max(-d,0))/p;} return al===0?100:100-(100/(1+ag/al)); };
    const e9=ema(close,9),e21=ema(close,21),r=rsi(close), recent=close.slice(-8), previous=close.slice(-16,-8);
    const avg = a => a.reduce((x,y)=>x+y,0)/Math.max(1,a.length);
    const recentMove=(recent[recent.length-1]-recent[0]), prevMove=(previous[previous.length-1]-previous[0]);
    const momentum = recentMove > 0 ? (prevMove > 0 ? 'STRONG UP' : 'UP') : recentMove < 0 ? (prevMove < 0 ? 'STRONG DOWN' : 'DOWN') : 'FLAT';
    const ranges=cs.slice(-14).map(c=>Number(c.high)-Number(c.low)).filter(Number.isFinite), atr=ranges.length?avg(ranges):null;
    const last=close[close.length-1], change=close.length>1?last-close[close.length-2]:0;
    const direction=e9>e21?'BULLISH':e9<e21?'BEARISH':'NEUTRAL';
    const strength=Math.max(0,Math.min(100,Math.round(Math.abs((e9-e21)/(atr||Math.abs(last)||1))*100)));
    const volume=cs.slice(-20).map(c=>Number(c.volume)||0), volNow=volume[volume.length-1], volAvg=avg(volume.slice(0,-1)), volRatio=volAvg>0?volNow/volAvg:null;
    return {m, last, change, r, atr, direction, strength, momentum, volRatio, feed:m.feedState||'OFFLINE'};
  }
  function style(){ if(el('sbt-market-pulse-style')) return; const s=document.createElement('style'); s.id='sbt-market-pulse-style'; s.textContent=`#sbt-market-pulse{position:absolute;right:12px;top:10px;z-index:7;width:224px;padding:10px 11px;border:1px solid #263746;border-radius:9px;background:rgba(7,12,18,.94);color:#dce7f0;font:10px ui-monospace,SFMono-Regular,Consolas,monospace;box-shadow:0 8px 24px rgba(0,0,0,.22);backdrop-filter:blur(7px);pointer-events:none}#sbt-market-pulse .head{display:flex;justify-content:space-between;gap:8px;font-weight:800;letter-spacing:.04em}#sbt-market-pulse .main{font-size:15px;margin:5px 0 7px}#sbt-market-pulse .grid{display:grid;grid-template-columns:1fr 1fr;gap:5px 10px;color:#91a0ad}#sbt-market-pulse b{color:#e8f0f6}#sbt-market-pulse .bar{height:4px;background:#1c2731;border-radius:3px;margin:4px 0 7px;overflow:hidden}#sbt-market-pulse .fill{height:100%;width:0;background:#72b7ff;transition:width .25s ease}#sbt-market-pulse .foot{margin-top:7px;color:#6f7e8b;font-size:9px}`; document.head.appendChild(s); }
  function render(){ const page=el('bot-lab-page'); if(!page?.classList.contains('web-trader-only')) return; const wrap=page.querySelector('.chart-wrap'); if(!wrap) return; style(); let box=el('sbt-market-pulse'); if(!box){box=document.createElement('div');box.id='sbt-market-pulse';wrap.appendChild(box);} const v=values(); if(!v){box.innerHTML='<div class="head"><span>MARKET PULSE</span><span>WAIT</span></div><div class="foot">Insufficient real candle data</div>';return;} const feed=v.feed==='LIVE'?'LIVE':v.feed==='HISTORICAL'?'HIST':'OFFLINE'; const rsi=v.r==null?'—':v.r.toFixed(1); const vol=v.volRatio==null?'—':v.volRatio.toFixed(2)+'×'; const sign=v.change>0?'+':v.change<0?'−':''; const dir=v.direction==='BULLISH'?'▲ BULLISH':v.direction==='BEARISH'?'▼ BEARISH':'• NEUTRAL'; box.innerHTML='<div class="head"><span>MARKET PULSE</span><span>'+feed+'</span></div><div class="main">'+dir+'</div><div class="bar"><div class="fill" style="width:'+v.strength+'%"></div></div><div class="grid"><span>Strength <b>'+v.strength+'%</b></span><span>RSI <b>'+rsi+'</b></span><span>Momentum <b>'+v.momentum+'</b></span><span>Δ <b>'+sign+Math.abs(v.change).toFixed(5)+'</b></span><span>ATR <b>'+Number(v.atr).toFixed(5)+'</b></span><span>Volume <b>'+vol+'</b></span></div><div class="foot">'+v.m.symbol+' · '+v.m.timeframe+' · real feed only</div>'; }
  function init(){ style(); render(); clearInterval(state.timer); state.timer=setInterval(render,1000); window.addEventListener('resize',render); }
  window.BiteyMarketPulse={init,render,values}; if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',()=>setTimeout(init,250));else setTimeout(init,250);
})();