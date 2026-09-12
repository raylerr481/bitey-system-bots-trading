(() => {
  const STORAGE_KEY = 'bitey-sbt-demo-execution-v1';
  const state = { position: null, trades: [], equity: 10000, peak: 10000, maxDrawdown: 0, lastSignal: 'FLAT', lastTime: null };

  function load() { try { const x = JSON.parse(localStorage.getItem(STORAGE_KEY) || '{}'); Object.assign(state, x); } catch (_) {} }
  function save() { localStorage.setItem(STORAGE_KEY, JSON.stringify(state)); }
  function activeBot() { return window.BiteySBTBotBridge?.getActive?.() || null; }
  function market() { return window.BiteySBTMarketState || null; }
  function closes() { const m = market(); return Array.isArray(m?.candles) ? m.candles : []; }
  function ema(values, p) { if (values.length < p) return null; let v = values.slice(0,p).reduce((a,b)=>a+b,0)/p, a=2/(p+1); for(let i=p;i<values.length;i++) v=a*values[i]+(1-a)*v; return v; }
  function rsi(values,p=14) { if(values.length<=p)return null; let g=0,l=0; for(let i=1;i<=p;i++){const d=values[i]-values[i-1];g+=Math.max(d,0);l+=Math.max(-d,0)} let ag=g/p,al=l/p; for(let i=p+1;i<values.length;i++){const d=values[i]-values[i-1];ag=(ag*(p-1)+Math.max(d,0))/p;al=(al*(p-1)+Math.max(-d,0))/p} return al===0?100:100-(100/(1+ag/al)); }
  function signal() {
    const cs=closes(); if(cs.length<22)return 'FLAT'; const v=cs.map(c=>c.close), e9=ema(v,9), e21=ema(v,21), r=rsi(v,14); if(e9==null||e21==null||r==null)return 'FLAT';
    if(e9>e21 && r>=50 && r<=75)return 'BUY';
    if(e9<e21 && r>=25 && r<50)return 'SELL';
    return 'FLAT';
  }
  function price() { const m=market(); const q=Number(m?.quote?.bid); const cs=closes(); return Number.isFinite(q)?q:(cs.length?Number(cs[cs.length-1].close):null); }
  function recordTrade(side, entry, exit, time, reason) {
    const pnl=side==='BUY' ? exit-entry : entry-exit;
    state.equity += pnl; state.peak=Math.max(state.peak,state.equity); state.maxDrawdown=Math.max(state.maxDrawdown,state.peak-state.equity);
    state.trades.push({id:'demo-'+Date.now(),side,entry,exit,pnl,time,reason,symbol:market()?.symbol,timeframe:market()?.timeframe});
    if(state.trades.length>100)state.trades.shift();
  }
  function evaluate() {
    const bot=activeBot(), m=market(); if(!bot||bot.status!=='ACTIVE'||bot.mode!=='DEMO'||!m||!closes().length)return;
    const cs=closes(), last=cs[cs.length-1]; if(state.lastTime===last.time)return; state.lastTime=last.time;
    const sig=signal(), px=price(); state.lastSignal=sig;
    if(!Number.isFinite(px)){save();render();return;}
    if(!state.position && (sig==='BUY'||sig==='SELL')) state.position={side:sig,entry:px,time:last.time,symbol:m.symbol,timeframe:m.timeframe};
    else if(state.position && sig!==state.position.side && sig!=='FLAT') { const p=state.position; recordTrade(p.side,p.entry,px,last.time,'opposite_signal'); state.position=null; state.position={side:sig,entry:px,time:last.time,symbol:m.symbol,timeframe:m.timeframe}; }
    save(); render();
    window.dispatchEvent(new CustomEvent('bitey:sbt-demo-signal',{detail:{signal:sig,price:px,time:last.time,position:state.position}}));
  }
  function style(){if(document.getElementById('sbt-demo-exec-style'))return;const s=document.createElement('style');s.id='sbt-demo-exec-style';s.textContent='#sbt-demo-exec{position:absolute;left:12px;top:10px;z-index:6;min-width:210px;padding:9px 11px;border:1px solid #294052;border-radius:8px;background:rgba(8,13,19,.94);color:#d9e4ee;font:10px ui-monospace,SFMono-Regular,Consolas,monospace;pointer-events:auto;backdrop-filter:blur(6px)}#sbt-demo-exec .sig{font-weight:800;font-size:13px}#sbt-demo-exec button{margin-top:6px;padding:4px 7px;border:1px solid #394754;border-radius:5px;background:#10161d;color:#d9e4ee;cursor:pointer;font-size:10px}';document.head.appendChild(s)}
  function render(){const page=document.getElementById('bot-lab-page');if(!page?.classList.contains('web-trader-only'))return;let h=document.getElementById('sbt-demo-exec');if(!h){h=document.createElement('div');h.id='sbt-demo-exec';const w=page.querySelector('.chart-wrap');if(w)w.appendChild(h)}if(!h)return;const bot=activeBot();if(!bot){h.style.display='none';return}h.style.display='block';const p=state.position;const unreal=p?(p.side==='BUY'?price()-p.entry:p.entry-price()):0;const wins=state.trades.filter(t=>t.pnl>0).length;const dd=state.maxDrawdown.toFixed(5);h.innerHTML='<div>DEMO EXECUTION · SIMULATED</div><div class="sig">SIGNAL: '+state.lastSignal+'</div><div>POSITION: '+(p?(p.side+' @ '+p.entry.toFixed(5)):'FLAT')+'</div><div>UNREALIZED: '+unreal.toFixed(5)+'</div><div>TRADES: '+state.trades.length+' · WINS: '+wins+'</div><div>EQUITY: '+state.equity.toFixed(5)+' · DD: '+dd+'</div><button id="sbtDemoReset">Reset Demo</button>';h.querySelector('#sbtDemoReset')?.addEventListener('click',()=>{state.position=null;state.trades=[];state.equity=10000;state.peak=10000;state.maxDrawdown=0;state.lastSignal='FLAT';save();render()})}
  function init(){load();style();render();setInterval(evaluate,1000);setInterval(render,1000);}
  window.BiteySBTDemoExecution={init,state,evaluate,reset:()=>{localStorage.removeItem(STORAGE_KEY);load();render()}};
  window.addEventListener('bitey:sbt-bot-activated',()=>{load();render();}); window.addEventListener('bitey:sbt-bot-cleared',()=>{state.position=null;save();render();});
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init);else init();
})();