(() => {
  const TIMEFRAMES = [
    ['M1', '1m'], ['M5', '5m'], ['M15', '15m'], ['M30', '30m'],
    ['H1', '1h'], ['H4', '4h'], ['D1', '1D'], ['W1', '1W']
  ];

  function installTimeframes() {
    const page = document.getElementById('bot-lab-page');
    const toolbar = page?.querySelector('.mt-toolbar');
    if (!page || !toolbar) return false;
    const anchor = toolbar.querySelector('[data-tf]');
    if (!anchor) return false;

    TIMEFRAMES.forEach(([tf, label]) => {
      let button = toolbar.querySelector(`[data-tf="${tf}"]`);
      if (!button) {
        button = document.createElement('button');
        button.type = 'button';
        button.dataset.tf = tf;
        button.textContent = label;
        button.title = `${label} timeframe`;
        anchor.parentElement.insertBefore(button, anchor);
      }
      if (button.dataset.sbtTimeframeWired !== '1') {
        button.dataset.sbtTimeframeWired = '1';
        button.addEventListener('click', () => selectTimeframe(tf));
      }
    });
    return true;
  }

  function selectTimeframe(tf) {
    const trader = window.BiteyWebTrader;
    const page = document.getElementById('bot-lab-page');
    if (!page) return;
    page.querySelectorAll('.mt-toolbar [data-tf]').forEach(b => b.classList.toggle('active', b.dataset.tf === tf));
    if (!trader?.state) return;
    trader.state.timeframe = tf;
    trader.state.viewEnd = null;
    const pair = trader.state.symbol || 'EURUSD';
    const tfNode = document.getElementById('mtTf');
    const overlay = document.getElementById('mtOverlay');
    if (tfNode) tfNode.textContent = `${tf} · BiQuote`;
    if (overlay) overlay.textContent = `Bitey SBT · ${pair} · ${tf}`;
    if (typeof trader.resetView === 'function') trader.resetView();
    if (typeof trader.drawChart === 'function') trader.drawChart();
    window.dispatchEvent(new CustomEvent('bitey:sbt-timeframe', { detail: { timeframe: tf } }));
    const refresh = document.getElementById('mtRefresh');
    if (refresh) refresh.click();
  }

  function boot() {
    if (installTimeframes()) return;
    setTimeout(boot, 150);
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();
})();


(() => {
  const BOT_CATALOG = [
    {id:'grid',cat:'crypto',icon:'▦',name:'Grid Bot',market:'BTC/USDT',risk:'Medium',desc:'Opera una malla de órdenes dentro de un rango definido.'},
    {id:'dca',cat:'portfolio',icon:'◉',name:'DCA Bot',market:'BTC/USDT',risk:'Low / Medium',desc:'Entradas escalonadas con control de capital y exposición.'},
    {id:'trend',cat:'forex',icon:'↗',name:'Trend Bot',market:'EUR/USD',risk:'Medium',desc:'EMA + RSI + ATR para seguimiento de tendencia.'},
    {id:'breakout',cat:'crypto',icon:'⇧',name:'Breakout Bot',market:'BTC/USDT',risk:'Medium / High',desc:'Rupturas confirmadas mediante filtro de volatilidad.'},
    {id:'mean-reversion',cat:'forex',icon:'↔',name:'Mean Reversion',market:'EUR/USD',risk:'Medium',desc:'Retorno a la media con filtros de régimen.'},
    {id:'rebalance',cat:'portfolio',icon:'⇄',name:'Rebalance Bot',market:'Multi-asset',risk:'Low',desc:'Mantiene pesos objetivo de una cartera.'}
  ];
  function mountBotCenter(){
    const page=document.getElementById('bot-lab-page'); if(!page||page.dataset.botCenterV1)return;
    page.dataset.botCenterV1='1';
    const host=page.querySelector('.bot-type-area'); if(!host)return;
    const box=document.createElement('section'); box.className='card'; box.style.cssText='margin:18px 0;padding:20px';
    box.innerHTML='<div style="display:flex;justify-content:space-between;gap:12px;align-items:flex-start;flex-wrap:wrap"><div><span class="eyebrow">BITEY BOT CENTER</span><h2 style="margin:5px 0">Bots incorporados</h2><p class="sub">Elige un bot listo para configurar. Backtest y Risk Gate siguen siendo obligatorios.</p></div><span class="badge">DEMO / PAPER · LIVE LOCKED</span></div><div class="choice" data-bot-filters><button class="selected" data-bot-filter="all"><strong>Todos</strong><span>Catálogo completo</span></button><button data-bot-filter="crypto"><strong>Crypto</strong><span>BTC · ETH</span></button><button data-bot-filter="forex"><strong>Forex</strong><span>EUR/USD</span></button><button data-bot-filter="portfolio"><strong>Portfolio</strong><span>DCA · Rebalance</span></button></div><div id="biteyBotCatalog" style="display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:12px"></div><div id="biteyBotSpec" class="result" style="display:none"></div>';
    host.parentNode.insertBefore(box,host);
    const grid=box.querySelector('#biteyBotCatalog'),spec=box.querySelector('#biteyBotSpec');
    const render=(filter)=>{grid.innerHTML=BOT_CATALOG.filter(b=>filter==='all'||b.cat===filter).map(b=>'<article class="card" style="padding:15px"><div style="display:flex;justify-content:space-between"><span style="font-size:24px;color:var(--accent)">'+b.icon+'</span><span class="badge">'+b.risk+'</span></div><h3 style="margin:10px 0 5px">'+b.name+'</h3><p class="sub">'+b.desc+'</p><div class="small" style="margin:8px 0">'+b.market+'</div><div class="toolbar"><button class="btn blue" data-bot-view="'+b.id+'">Ver configuración</button><button class="btn" data-bot-test="'+b.id+'">Backtest</button></div></article>').join('');};
    render('all');
    box.querySelectorAll('[data-bot-filter]').forEach(b=>b.addEventListener('click',()=>{box.querySelectorAll('[data-bot-filter]').forEach(x=>x.classList.remove('selected'));b.classList.add('selected');render(b.dataset.botFilter)}));
    box.addEventListener('click',e=>{const btn=e.target.closest('[data-bot-view],[data-bot-test]');if(!btn)return;const b=BOT_CATALOG.find(x=>x.id===(btn.dataset.botView||btn.dataset.botTest));if(!b)return;spec.style.display='block';spec.textContent=(btn.dataset.botTest?'BACKTEST REQUEST':'BOT SPECIFICATION')+'\\n\\nName: '+b.name+'\\nMarket: '+b.market+'\\nRisk: '+b.risk+'\\nMode: DEMO/PAPER\\nLifecycle: DRAFT → SIMULATED → ROBUSTNESS → VALIDATED → DEMO → PAPER\\n\\n'+b.desc+'\\n\\nNo live order is authorized by this action.';spec.scrollIntoView({behavior:'smooth',block:'nearest'});});
  }
  function boot(){mountBotCenter(); const page=document.getElementById('bot-lab-page'); if(!page||!page.dataset.botCenterV1)setTimeout(boot,250)}
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot);else boot();
})();
