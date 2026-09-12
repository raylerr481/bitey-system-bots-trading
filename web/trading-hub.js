(() => {
  const state = {
    mode: 'RESEARCH',
    market: 'OFFLINE',
    algorithm: 'WAIT',
    bot: 'NONE',
    execution: 'DEMO_ONLY',
    riskGate: 'LOCKED',
    lastSignal: null
  };

  function market(){ return window.BiteySBTMarketState || null; }
  function algo(){ return window.BiteySBTAlgorithmic?.state || null; }
  function bot(){ return window.BiteySBTBotBridge?.getActive?.() || null; }
  function demo(){ return window.BiteySBTDemoExecution?.state || null; }

  function sync(){
    const m=market(), a=algo(), b=bot();
    state.market=m?.feedState || 'OFFLINE';
    state.algorithm=a?.signal || 'WAIT';
    state.bot=b?.status === 'ACTIVE' ? 'ACTIVE_DEMO' : 'NONE';
    state.execution='DEMO_ONLY';
    state.riskGate=(window.SBT_LIVE_TRADING_ENABLED===true && window.SBT_SAFETY?.real_money===true) ? 'EVALUATE' : 'LOCKED';
    state.lastSignal=a ? {signal:a.signal,score:a.score,confidence:a.confidence,regime:a.regime,risk:a.risk,symbol:m?.symbol,timeframe:m?.timeframe} : null;
    window.dispatchEvent(new CustomEvent('bitey:sbt-trading-hub',{detail:{...state,market:m?.symbol,timeframe:m?.timeframe,demo:demo()}}));
    render();
  }

  function render(){
    const page=document.getElementById('bot-lab-page');
    if(!page?.classList.contains('web-trader-only')) return;
    let h=document.getElementById('sbt-trading-hub');
    if(!h){ h=document.createElement('div'); h.id='sbt-trading-hub'; const w=page.querySelector('.chart-wrap'); if(w) w.appendChild(h); }
    if(!h)return;
    h.innerHTML='<div class="hub-title">BITEY TRADING HUB</div>'+
      '<div class="hub-row"><span>MARKET</span><b>'+state.market+'</b></div>'+
      '<div class="hub-row"><span>ALGORITHM</span><b>'+state.algorithm+'</b></div>'+
      '<div class="hub-row"><span>BOT</span><b>'+state.bot+'</b></div>'+
      '<div class="hub-row"><span>EXECUTION</span><b>'+state.execution+'</b></div>'+
      '<div class="hub-row"><span>RISK GATE</span><b>'+state.riskGate+'</b></div>'+
      '<div class="hub-note">Gateway → Regime → Signal → Risk Gate → Demo → Web Trader</div>';
  }

  function style(){
    if(document.getElementById('sbt-trading-hub-style'))return;
    const s=document.createElement('style'); s.id='sbt-trading-hub-style';
    s.textContent='#sbt-trading-hub{position:absolute;left:12px;bottom:12px;z-index:8;min-width:235px;padding:9px 11px;border:1px solid #294052;border-radius:8px;background:rgba(8,13,19,.95);color:#d9e4ee;font:10px ui-monospace,SFMono-Regular,Consolas,monospace;pointer-events:none;backdrop-filter:blur(6px)}#sbt-trading-hub .hub-title{font-size:9px;letter-spacing:.1em;color:#8fa2b5;margin-bottom:5px}#sbt-trading-hub .hub-row{display:flex;justify-content:space-between;gap:18px;margin:2px 0}#sbt-trading-hub .hub-row span{color:#748596}#sbt-trading-hub .hub-note{margin-top:6px;color:#718394;font-size:8px;line-height:1.3}';
    document.head.appendChild(s);
  }

  function init(){ style(); sync(); setInterval(sync,1000); }
  window.BiteyTradingHub={state,sync,init};
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init);else init();
})();