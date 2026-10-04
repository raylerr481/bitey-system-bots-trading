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

(() => {
  const SPECS = {
    grid:{title:'Grid Bot',fields:[['symbol','Símbolo','BTC/USDT','text'],['capital','Capital','10000','number'],['lower','Rango inferior','90000','number'],['upper','Rango superior','120000','number'],['grids','Número de grids','20','number'],['stop','Stop loss %','5','number'],['take','Take profit %','2','number']]},
    dca:{title:'DCA Bot',fields:[['symbol','Símbolo','BTC/USDT','text'],['capital','Capital','10000','number'],['initial','Orden inicial','500','number'],['safety','Órdenes de seguridad','5','number'],['step','Paso %','3','number'],['multiplier','Multiplicador','1.25','number'],['take','Take profit %','2','number']]},
    trend:{title:'Trend Bot',fields:[['symbol','Símbolo','EURUSD','text'],['timeframe','Timeframe','H1','select','M5,H1,H4,D1'],['capital','Capital','10000','number'],['emaFast','EMA rápida','9','number'],['emaSlow','EMA lenta','21','number'],['rsi','RSI mínimo','50','number'],['atr','ATR SL multiplier','1.5','number'],['risk','Riesgo %','0.25','number']]},
    breakout:{title:'Breakout Bot',fields:[['symbol','Símbolo','BTC/USDT','text'],['timeframe','Timeframe','H1','select','M15,H1,H4,D1'],['capital','Capital','10000','number'],['lookback','Lookback','20','number'],['atr','ATR multiplier','1.5','number'],['risk','Riesgo %','0.5','number']]},
    'mean-reversion':{title:'Mean Reversion',fields:[['symbol','Símbolo','EURUSD','text'],['timeframe','Timeframe','H1','select','M15,H1,H4,D1'],['capital','Capital','10000','number'],['rsiLow','RSI sobreventa','30','number'],['rsiHigh','RSI sobrecompra','70','number'],['deviation','Desviación','2','number'],['take','Take profit %','1','number'],['stop','Stop loss %','2','number']]},
    rebalance:{title:'Rebalance Bot',fields:[['assets','Activos','BTC/USDT,ETH/USDT,USDT','text'],['capital','Capital','10000','number'],['btc','BTC %','50','number'],['eth','ETH %','30','number'],['cash','Cash %','20','number'],['threshold','Umbral rebalance %','5','number'],['frequency','Frecuencia rebalance','20','number']]}
  };
  function mount(){
    const page=document.getElementById('bot-lab-page'); const center=page?.querySelector('[data-bot-filters]')?.closest('section');
    if(!page||!center||page.dataset.botConfigV1)return;
    page.dataset.botConfigV1='1';
    const p=document.createElement('section');p.className='card';p.style.cssText='margin:18px 0;padding:20px';
    p.innerHTML='<span class="eyebrow">BOT CONFIGURATION</span><div style="display:flex;justify-content:space-between;gap:12px;align-items:flex-start"><div><h2 id="sbtBotConfigTitle" style="margin:5px 0">Selecciona un bot</h2><p class="sub">Parámetros por estrategia. Configurar no ejecuta órdenes.</p></div><span class="badge">DEMO / PAPER · LIVE LOCKED</span></div><div id="sbtBotForm" class="form"></div><div class="toolbar" style="margin-top:14px"><button class="btn primary" id="sbtBotBacktest">Preparar backtest</button><button class="btn" id="sbtBotRisk">Previsualizar Risk Gate</button><button class="btn" id="sbtBotSave">Guardar configuración</button></div><div id="sbtBotConfigResult" class="result"></div>';
    center.insertAdjacentElement('afterend',p);
    const form=p.querySelector('#sbtBotForm'),title=p.querySelector('#sbtBotConfigTitle'),out=p.querySelector('#sbtBotConfigResult');let selected=null;
    function render(id){selected=SPECS[id]?id:null;if(!selected){title.textContent='Selecciona un bot';form.innerHTML='<div class="small">Usa “Ver configuración” en el catálogo.</div>';return;}const s=SPECS[id];title.textContent=s.title;form.innerHTML=s.fields.map(([k,l,v,t,o])=>t==='select'?'<label>'+l+'<select data-bot-field="'+k+'">'+o.split(',').map(x=>'<option>'+x+'</option>').join('')+'</select></label>':'<label>'+l+'<input data-bot-field="'+k+'" type="'+t+'" value="'+v+'" step="any"></label>').join('');const saved=JSON.parse(sessionStorage.getItem('sbt.bot.'+id)||'null');if(saved)Object.entries(saved).forEach(([k,v])=>{const e=form.querySelector('[data-bot-field="'+k+'"]');if(e)e.value=v;});}
    const read=()=>{const o={bot_type:selected};form.querySelectorAll('[data-bot-field]').forEach(e=>o[e.dataset.botField]=e.value);return o;};
    p.querySelector('#sbtBotSave').onclick=()=>{if(!selected)return;sessionStorage.setItem('sbt.bot.'+selected,JSON.stringify(read()));out.style.display='block';out.textContent='Configuración guardada en esta sesión · '+SPECS[selected].title+'.';};
    p.querySelector('#sbtBotRisk').onclick=async()=>{if(!selected){out.style.display='block';out.textContent='Selecciona un bot primero.';return;}out.style.display='block';out.textContent='Consultando Risk Gate…';try{const base=((window.SBT_API_URL||localStorage.getItem('sbt_api_base')||'').replace(/\/$/,''));const cfg=read();const r=await fetch(base+'/api/v1/built-in-bots/risk-preview',{method:'POST',headers:{'Content-Type':'application/json','Accept':'application/json'},body:JSON.stringify({bot_type:selected,initial_capital:Number(cfg.capital||10000),config:cfg})});if(!r.ok)throw new Error('API HTTP '+r.status);const d=await r.json();if(d.valid===false)throw new Error(d.error||'Risk preview rejected');window.__sbtLastRisk=d;window.dispatchEvent(new CustomEvent('sbt:risk-preview',{detail:{risk:d,config:cfg}}));out.textContent='RISK GATE · posición máxima '+Number(d.max_position_value||0).toFixed(2)+' · pérdida/trade '+Number(d.configured_loss_per_trade||0).toFixed(2)+' · pérdida diaria '+Number(d.configured_daily_loss||0).toFixed(2)+'. DEMO/PAPER · LIVE LOCKED.';}catch(e){out.textContent='Risk Gate unavailable: '+e.message+'. No se muestran límites inventados.';}};
    p.querySelector('#sbtBotBacktest').onclick=()=>{if(!selected){out.style.display='block';out.textContent='Selecciona un bot primero.';return;}const c=read();window.__sbtSelectedBotConfig=c;window.dispatchEvent(new CustomEvent('sbt:bot-config',{detail:c}));out.style.display='block';out.textContent='BACKTEST PREPARADO · '+SPECS[selected].title+' · '+(c.symbol||c.assets)+' · DEMO/PAPER. No se autoriza live.';};
    page.addEventListener('click',e=>{const b=e.target.closest('[data-bot-view]');if(b)setTimeout(()=>render(b.dataset.botView),0);});
    render(null);
  }
  function boot(){mount();if(!document.querySelector('#bot-lab-page[data-bot-config-v1]'))setTimeout(boot,250);}
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot);else boot();
})();

(() => {
  window.addEventListener('sbt:bot-config', async (event) => {
    const c=event.detail||{}, out=document.getElementById('sbtBotConfigResult'); if(!c.bot_type||!out)return;
    const base=((window.SBT_API_URL||localStorage.getItem('sbt_api_base')||'').replace(/\/$/,''));
    const symbol=c.symbol||'EURUSD', tf=c.timeframe||'M5';
    out.style.display='block'; out.textContent='Consultando market data para preparar el backtest…';
    try{
      const r=await fetch(base+'/api/v1/market/candles/'+encodeURIComponent(symbol)+'?timeframe='+encodeURIComponent(tf)+'&limit=200');
      if(!r.ok)throw new Error('Market data HTTP '+r.status);
      const d=await r.json(), candles=Array.isArray(d)?d:(Array.isArray(d.candles)?d.candles:[]);
      const prices=candles.map(x=>Number(x.close)).filter(Number.isFinite);
      if(prices.length<40)throw new Error('Insuficientes datos: '+prices.length+' cierres; se requieren al menos 40');
      const market=await window.sbtLoadBotMarket(c,base);
      const br=await fetch(base+'/api/v1/built-in-bots/backtest',{method:'POST',headers:{'Content-Type':'application/json','Accept':'application/json'},body:JSON.stringify({bot_type:c.bot_type,prices:market.prices,series:market.series,initial_capital:Number(c.capital||10000),config:c})});
      if(!br.ok)throw new Error('Backtest HTTP '+br.status);
      const b=await br.json(); if(b.valid===false)throw new Error(b.error||'Backtest rejected'); window.__sbtLastBacktest=b;
      window.dispatchEvent(new CustomEvent('sbt:backtest',{detail:{backtest:b,config:c,symbol:market.symbol,timeframe:market.timeframe}}));
      try{
        const rr=await fetch(base+'/api/v1/built-in-bots/robustness',{method:'POST',headers:{'Content-Type':'application/json','Accept':'application/json'},body:JSON.stringify({bot_type:c.bot_type,prices:market.prices,series:market.series,initial_capital:Number(c.capital||10000),config:c})});
        if(rr.ok){const rb=await rr.json();window.__sbtLastRobustness=rb;window.dispatchEvent(new CustomEvent('sbt:robustness',{detail:{robustness:rb,config:c,symbol,timeframe:tf}}));}
      }catch(_e){/* robustness is advisory; backtest remains available */}
      out.textContent='BACKTEST DISPONIBLE · '+c.bot_type+' · '+market.symbol+' '+market.timeframe+' · '+market.prices.length+' cierres · Equity final '+Number(b.final_equity||0).toFixed(2)+' · Return '+Number(b.total_return_pct||0).toFixed(2)+'% · Trades '+Number(b.trades||0)+' · Win rate '+Number(b.win_rate_pct||0).toFixed(1)+'% · DD '+Number(b.max_drawdown_pct||0).toFixed(2)+'%. Sin órdenes live.';
    }catch(e){out.textContent='Backtest unavailable: '+e.message+'. No se muestran métricas inventadas.';}
  });
})();

(() => {
  window.sbtLoadBotMarket = async function(c, base) {
    const tf=c.timeframe||'H1';
    if(c.bot_type!=='rebalance') {
      const symbol=c.symbol||'EURUSD';
      const r=await fetch(base+'/api/v1/market/candles/'+encodeURIComponent(symbol)+'?timeframe='+encodeURIComponent(tf)+'&limit=200');
      if(!r.ok)throw new Error('Market data HTTP '+r.status);
      const d=await r.json(), candles=Array.isArray(d)?d:(Array.isArray(d.candles)?d.candles:[]);
      const prices=candles.map(x=>Number(x.close)).filter(Number.isFinite);
      if(prices.length<40)throw new Error('Insuficientes datos: '+prices.length+' cierres; se requieren al menos 40');
      return {prices,series:{},symbol,timeframe:tf};
    }
    const assets=String(c.assets||'BTC/USDT,ETH/USDT,USDT').split(',').map(x=>x.trim()).filter(Boolean);
    const series={}; let firstSymbol=null; let firstPrices=[];
    for(const asset of assets) {
      if(/^(USDT|USD|CASH)$/i.test(asset)) continue;
      const r=await fetch(base+'/api/v1/market/candles/'+encodeURIComponent(asset)+'?timeframe='+encodeURIComponent(tf)+'&limit=200');
      if(!r.ok)throw new Error('Market data '+asset+' HTTP '+r.status);
      const d=await r.json(), candles=Array.isArray(d)?d:(Array.isArray(d.candles)?d.candles:[]);
      const prices=candles.map(x=>Number(x.close)).filter(Number.isFinite);
      if(prices.length<40)throw new Error('Insuficientes datos para '+asset+': '+prices.length);
      if(!firstSymbol){firstSymbol=asset;firstPrices=prices;}
      series[asset]=prices;
    }
    const lengths=Object.values(series).map(x=>x.length); const min=Math.min(...lengths);
    if(!Number.isFinite(min)||min<40)throw new Error('Series multi-activo insuficientes');
    Object.keys(series).forEach(k=>{series[k]=series[k].slice(-min);});
    return {prices:firstPrices.slice(-min),series,symbol:assets.join(', '),timeframe:tf};
  };
})();


(() => {
  function mountEvaluationPanel() {
    const page=document.getElementById('bot-lab-page');
    const config=page?.querySelector('#sbtBotConfigResult')?.closest('section');
    if(!page||!config||page.dataset.botEvaluationV1)return;
    page.dataset.botEvaluationV1='1';
    const p=document.createElement('section');
    p.className='card';
    p.style.cssText='margin:18px 0;padding:20px';
    p.innerHTML='<span class="eyebrow">BOT EVALUATION</span><div style="display:flex;justify-content:space-between;gap:12px;align-items:flex-start;flex-wrap:wrap"><div><h2 id="sbtEvalTitle" style="margin:5px 0">Evaluación SBT</h2><p class="sub">Backtest, Robustness y Risk Gate determinan el estado del bot. No es una garantía de rendimiento.</p></div><span id="sbtEvalStage" class="badge">DRAFT</span></div><div id="sbtEvalMetrics" style="display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:10px;margin-top:15px"></div><div id="sbtEvalDecision" class="result" style="margin-top:14px">Esperando backtest…</div>';
    config.insertAdjacentElement('afterend',p);
    page.querySelector('#sbtEvalMetrics').innerHTML=['Return','Win Rate','Max Drawdown','Trades','Robustness','Risk Gate','Strategy Score','Lifecycle'].map(x=>'<div class="card" style="padding:12px"><div class="small">'+x+'</div><strong data-metric="'+x.toLowerCase().replace(/ /g,'-')+'">—</strong></div>').join('');
  }

  function score(backtest, robustness, risk) {
    const ret=Number(backtest?.total_return_pct||0);
    const wr=Number(backtest?.win_rate_pct||0);
    const dd=Number(backtest?.max_drawdown_pct||0);
    const trades=Number(backtest?.trades||0);
    const rb=Number(robustness?.score||0);
    const riskScore=risk?100:0;
    const returnScore=Math.max(0,Math.min(25,ret*2+12.5));
    const winScore=Math.max(0,Math.min(20,wr*0.2));
    const ddScore=Math.max(0,Math.min(20,20-dd*2));
    const tradeScore=trades>=10?10:trades>=3?7:trades>=1?4:0;
    return Math.round(Math.max(0,Math.min(100,returnScore+winScore+ddScore+tradeScore+(rb*0.25)+(riskScore*0.05))));
  }

  function updateEvaluation() {
    const b=window.__sbtLastBacktest||{}, rb=window.__sbtLastRobustness||{};
    const risk=window.__sbtLastRisk||null;
    const page=document.getElementById('bot-lab-page'); if(!page)return;
    const set=(key,value)=>{const e=page.querySelector('[data-metric="'+key+'"]');if(e)e.textContent=value;};
    set('return',Number(b.total_return_pct||0).toFixed(2)+'%');
    set('win-rate',Number(b.win_rate_pct||0).toFixed(1)+'%');
    set('max-drawdown',Number(b.max_drawdown_pct||0).toFixed(2)+'%');
    set('trades',String(b.trades||0));
    set('robustness',rb.valid?Number(rb.score||0).toFixed(1)+' / 100':'—');
    set('risk-gate',risk?'READY':'PENDING');
    const ready=!!b.valid&&!!rb.valid&&rb.status==='PASS'&&!!risk;
    const s=score(b,rb,risk);
    set('strategy-score',ready?s+' / 100':s+' / 100 · REVIEW');
    const stage=ready?'VALIDATED':b.valid?'ROBUSTNESS':'DRAFT';
    set('lifecycle',stage);
    const stageEl=page.querySelector('#sbtEvalStage');if(stageEl)stageEl.textContent=stage;
    const d=page.querySelector('#sbtEvalDecision');
    if(d)d.textContent=ready?'VALIDATED · El bot supera el screening configurado y puede pasar a DEMO. Live continúa bloqueado.':b.valid?'REVIEW · Completa Robustness y Risk Gate antes de considerar DEMO.':'DRAFT · Ejecuta un backtest válido para iniciar la evaluación.';
  }

  window.addEventListener('sbt:backtest',e=>{window.__sbtLastBacktest=e.detail?.backtest||window.__sbtLastBacktest;updateEvaluation();});
  window.addEventListener('sbt:robustness',e=>{window.__sbtLastRobustness=e.detail?.robustness||window.__sbtLastRobustness;updateEvaluation();});
  window.addEventListener('sbt:risk-preview',e=>{window.__sbtLastRisk=e.detail?.risk||e.detail?.riskPreview||window.__sbtLastRisk;updateEvaluation();});
  function boot(){mountEvaluationPanel();if(!document.querySelector('#bot-lab-page[data-bot-evaluation-v1]'))setTimeout(boot,250);}
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot);else boot();
})();


(() => {
  const KEY='sbt.myBots.v1';
  function load(){try{return JSON.parse(localStorage.getItem(KEY)||'[]')}catch(_e){return[]}}
  function save(a){localStorage.setItem(KEY,JSON.stringify(a.slice(0,50)))}
  function selectedConfig(){return window.__sbtSelectedBotConfig||null}
  function mountMyBots(){
    const page=document.getElementById('bot-lab-page');
    const anchor=page?.querySelector('[data-bot-filters]')?.closest('section');
    if(!page||!anchor||page.dataset.myBotsV1)return;
    page.dataset.myBotsV1='1';
    const p=document.createElement('section');p.className='card';p.style.cssText='margin:18px 0;padding:20px';
    p.innerHTML='<span class="eyebrow">MY BOTS</span><div style="display:flex;justify-content:space-between;align-items:flex-start;gap:12px;flex-wrap:wrap"><div><h2 style="margin:5px 0">Mis bots</h2><p class="sub">Persistencia local del navegador. No crea órdenes ni conecta dinero real.</p></div><button class="btn" id="sbtRefreshBots">Actualizar</button></div><div id="sbtMyBotsList" style="display:grid;gap:10px;margin-top:14px"></div>';
    anchor.insertAdjacentElement('beforebegin',p);
    const list=p.querySelector('#sbtMyBotsList');
    function render(){
      const bots=load();
      if(!bots.length){list.innerHTML='<div class="small">No hay bots guardados todavía. Configura uno y pulsa “Guardar configuración”.</div>';return;}
      list.innerHTML=bots.map((b,i)=>'<article class="card" style="padding:14px"><div style="display:flex;justify-content:space-between;gap:10px"><div><strong>'+b.name+'</strong><div class="small">'+b.bot_type.toUpperCase()+' · '+(b.symbol||b.assets||'market')+'</div></div><span class="badge">'+b.stage+'</span></div><div class="small" style="margin-top:8px">Strategy Score: '+(b.strategy_score??'—')+' · Robustness: '+(b.robustness_score??'—')+' · Updated: '+new Date(b.updated_at).toLocaleString()+'</div><div class="toolbar" style="margin-top:10px"><button class="btn" data-load-bot="'+i+'">Cargar</button><button class="btn" data-delete-bot="'+i+'">Eliminar</button></div></article>').join('');
    }
    p.addEventListener('click',e=>{
      const loadBtn=e.target.closest('[data-load-bot]'),del=e.target.closest('[data-delete-bot]');
      const bots=load();
      if(del){bots.splice(Number(del.dataset.deleteBot),1);save(bots);render();return;}
      if(loadBtn){const b=bots[Number(loadBtn.dataset.loadBot)];if(!b)return;sessionStorage.setItem('sbt.bot.'+b.id,JSON.stringify(b.config));window.__sbtSelectedBotConfig={...b.config,bot_id:b.id};const v=document.querySelector('[data-bot-view="'+b.bot_type+'"]');if(v)v.click();setTimeout(()=>window.dispatchEvent(new CustomEvent('sbt:bot-config',{detail:b.config})),50);}
    });
    p.querySelector('#sbtRefreshBots').onclick=render;
    window.addEventListener('sbt:bot-saved',render);render();
  }
  function hookSave(){
    const btn=document.getElementById('sbtBotSave');if(!btn||btn.dataset.myBotsHooked)return;
    btn.dataset.myBotsHooked='1';
    btn.addEventListener('click',()=>{
      const c=selectedConfig();if(!c?.bot_type)return;
      const bots=load();
      const name=({grid:'Grid Bot',dca:'DCA Bot',trend:'Trend Bot',breakout:'Breakout Bot','mean-reversion':'Mean Reversion',rebalance:'Rebalance Bot'}[c.bot_type]||c.bot_type);
      const cleanConfig={...c};delete cleanConfig.bot_id;
      const signature=JSON.stringify(cleanConfig);
      const existing=bots.find(x=>(c.bot_id&&x.id===c.bot_id)|| (x.bot_type===c.bot_type && JSON.stringify(x.config||{})===signature));
      const b=existing||{id:c.bot_type+'-'+Date.now()+'-'+Math.random().toString(36).slice(2,8),bot_type:c.bot_type,name,config:c,stage:'DRAFT',strategy_score:null,robustness_score:null,updated_at:new Date().toISOString()};
      b.config=cleanConfig;b.name=name;b.updated_at=new Date().toISOString();
      if(!existing)bots.unshift(b);save(bots);window.dispatchEvent(new CustomEvent('sbt:bot-saved',{detail:b}));
    });
  }
  function syncEvaluationToBot(){
    const bots=load(), c=selectedConfig();if(!c?.bot_type)return;
    const cleanConfig={...c};delete cleanConfig.bot_id;
    const signature=JSON.stringify(cleanConfig);
    const idx=bots.findIndex(x=>(c.bot_id&&x.id===c.bot_id)|| (x.bot_type===c.bot_type && JSON.stringify(x.config||{})===signature));
    if(idx<0)return;
    const b=bots[idx], rb=window.__sbtLastRobustness, bt=window.__sbtLastBacktest;
    b.strategy_score=(bt&&rb&&rb.valid)?Math.round(Math.max(0,Math.min(100,Number(bt.total_return_pct||0)*2+Number(bt.win_rate_pct||0)*0.2+(20-Number(bt.max_drawdown_pct||0)*2)+Number(rb.score||0)*0.25+5))):b.strategy_score;
    b.robustness_score=rb?.valid?Number(rb.score||0):b.robustness_score;
    if(bt?.valid&&rb?.valid&&rb.status==='PASS'&&window.__sbtLastRisk&&b.stage!=='PUBLISHED')b.stage='VALIDATED';
    b.updated_at=new Date().toISOString();save(bots);window.dispatchEvent(new CustomEvent('sbt:bot-saved',{detail:b}));
  }
  function boot(){mountMyBots();hookSave();syncEvaluationToBot();if(!document.querySelector('#bot-lab-page[data-my-bots-v1]'))setTimeout(boot,250)}
  window.addEventListener('sbt:backtest',syncEvaluationToBot);
  window.addEventListener('sbt:robustness',syncEvaluationToBot);
  window.addEventListener('sbt:risk-preview',syncEvaluationToBot);
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot);else boot();
})();


(() => {
  function mountDemoPanel(){
    const page=document.getElementById('bot-lab-page');
    const evalPanel=page?.querySelector('#sbtEvalDecision')?.closest('section');
    if(!page||!evalPanel||page.dataset.botDemoV1)return;
    page.dataset.botDemoV1='1';
    const p=document.createElement('section'); p.className='card'; p.style.cssText='margin:18px 0;padding:20px';
    p.innerHTML='<span class="eyebrow">DEMO BOT</span><div style="display:flex;justify-content:space-between;gap:12px;align-items:flex-start;flex-wrap:wrap"><div><h2 style="margin:5px 0">Demo virtual</h2><p class="sub">Ejecuta el bot con capital virtual usando el mismo motor determinista. No conecta dinero real.</p></div><span class="badge">VIRTUAL · NO LIVE ORDERS</span></div><div class="toolbar" style="margin-top:14px"><button class="btn primary" id="sbtStartDemo">Iniciar Demo</button><button class="btn" id="sbtRefreshDemo">Actualizar</button></div><div id="sbtDemoResult" class="result" style="margin-top:14px">Demo bloqueado hasta VALIDATED.</div>';
    evalPanel.insertAdjacentElement('afterend',p);
    const out=p.querySelector('#sbtDemoResult');
    async function run(){
      const b=window.__sbtLastBacktest||{}, rb=window.__sbtLastRobustness||{}, risk=window.__sbtLastRisk;
      const c=window.__sbtSelectedBotConfig;
      if(!(b.valid&&rb.valid&&rb.status==='PASS'&&risk&&c?.bot_type)){out.textContent='DEMO BLOQUEADO · primero completa Backtest + Robustness PASS + Risk Gate.';return;}
      const base=((window.SBT_API_URL||localStorage.getItem('sbt_api_base')||'').replace(/\/$/,''));
      const symbol=c.symbol||'EURUSD', tf=c.timeframe||'M5';
      out.textContent='Iniciando sesión virtual…';
      try{
        const market=await window.sbtLoadBotMarket(c,base), prices=market.prices, series=market.series;
        const dr=await fetch(base+'/api/v1/built-in-bots/demo/simulate',{method:'POST',headers:{'Content-Type':'application/json','Accept':'application/json'},body:JSON.stringify({bot_type:c.bot_type,prices,series,initial_capital:Number(c.capital||10000),config:c})});
        if(!dr.ok)throw new Error('Demo HTTP '+dr.status);
        const d=await dr.json(); if(d.valid===false)throw new Error(d.error||'Demo rejected');
        window.__sbtLastDemo=d;
        window.dispatchEvent(new CustomEvent("sbt:demo",{detail:{demo:d,config:c}}));
        localStorage.setItem('sbt.demo.last',JSON.stringify({config:c,result:d,updated_at:new Date().toISOString()}));
        out.textContent='DEMO ACTIVA · Capital virtual '+Number(d.initial_capital||0).toFixed(2)+' · Equity '+Number(d.final_equity||0).toFixed(2)+' · Return '+Number(d.total_return_pct||0).toFixed(2)+'% · Trades virtuales '+Number(d.trades||0)+' · Win rate '+Number(d.win_rate_pct||0).toFixed(1)+'% · DD '+Number(d.max_drawdown_pct||0).toFixed(2)+'%. VIRTUAL · NO LIVE ORDERS.';
      }catch(e){out.textContent='Demo unavailable: '+e.message+'. No se muestran métricas inventadas.';}
    }
    p.querySelector('#sbtStartDemo').onclick=run;
    p.querySelector('#sbtRefreshDemo').onclick=run;
    try{
      const saved=JSON.parse(localStorage.getItem('sbt.demo.last')||'null');
      if(saved?.result)out.textContent='Última Demo · Equity '+Number(saved.result.final_equity||0).toFixed(2)+' · Return '+Number(saved.result.total_return_pct||0).toFixed(2)+'% · '+new Date(saved.updated_at).toLocaleString()+' · VIRTUAL.';
    }catch(_e){}
  }
  function boot(){mountDemoPanel();if(!document.querySelector('#bot-lab-page[data-bot-demo-v1]'))setTimeout(boot,250)}
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot);else boot();
})();


(() => {
  function mountPaperPanel(){
    const page=document.getElementById('bot-lab-page');
    const demo=page?.querySelector('#sbtStartDemo')?.closest('section');
    if(!page||!demo||page.dataset.botPaperV1)return;
    page.dataset.botPaperV1='1';
    const p=document.createElement('section');p.className='card';p.style.cssText='margin:18px 0;padding:20px';
    p.innerHTML='<span class="eyebrow">PAPER TRADING</span><div style="display:flex;justify-content:space-between;gap:12px;align-items:flex-start;flex-wrap:wrap"><div><h2 style="margin:5px 0">Paper</h2><p class="sub">Simulación continua sin dinero real. Requiere bot VALIDATED y Demo completada.</p></div><span class="badge">PAPER · NO LIVE ORDERS</span></div><div class="toolbar" style="margin-top:14px"><button class="btn primary" id="sbtStartPaper">Iniciar Paper</button></div><div id="sbtPaperResult" class="result" style="margin-top:14px">Paper bloqueado hasta completar Demo.</div>';
    demo.insertAdjacentElement('afterend',p);
    const out=p.querySelector('#sbtPaperResult');
    async function run(){
      const d=window.__sbtLastDemo, c=window.__sbtSelectedBotConfig;
      if(!(d?.valid&&c?.bot_type)){out.textContent='PAPER BLOQUEADO · ejecuta una Demo válida primero.';return;}
      const base=((window.SBT_API_URL||localStorage.getItem('sbt_api_base')||'').replace(/\/$/,''));
      const symbol=c.symbol||'EURUSD',tf=c.timeframe||'M5';
      out.textContent='Preparando Paper…';
      try{
        const mr=await fetch(base+'/api/v1/market/candles/'+encodeURIComponent(symbol)+'?timeframe='+encodeURIComponent(tf)+'&limit=200');
        if(!mr.ok)throw new Error('Market data HTTP '+mr.status);
        const md=await mr.json(), candles=Array.isArray(md)?md:(Array.isArray(md.candles)?md.candles:[]);
        const prices=candles.map(x=>Number(x.close)).filter(Number.isFinite);
        if(prices.length<40)throw new Error('Insuficientes datos: '+prices.length);
        const pr=await fetch(base+'/api/v1/built-in-bots/paper/simulate',{method:'POST',headers:{'Content-Type':'application/json','Accept':'application/json'},body:JSON.stringify({bot_type:c.bot_type,prices,initial_capital:Number(c.capital||10000),config:c})});
        if(!pr.ok)throw new Error('Paper HTTP '+pr.status);
        const x=await pr.json();if(x.valid===false)throw new Error(x.error||'Paper rejected');
        window.__sbtLastPaper=x;
        window.dispatchEvent(new CustomEvent("sbt:paper",{detail:{paper:x,config:c}}));
        localStorage.setItem('sbt.paper.last',JSON.stringify({config:c,result:x,updated_at:new Date().toISOString()}));
        out.textContent='PAPER ACTIVO · Equity '+Number(x.final_equity||0).toFixed(2)+' · Return '+Number(x.total_return_pct||0).toFixed(2)+'% · Trades '+Number(x.trades||0)+' · Win rate '+Number(x.win_rate_pct||0).toFixed(1)+'% · DD '+Number(x.max_drawdown_pct||0).toFixed(2)+'%. PAPER · NO LIVE ORDERS.';
      }catch(e){out.textContent='Paper unavailable: '+e.message+'.';}
    }
    p.querySelector('#sbtStartPaper').onclick=run;
    try{const saved=JSON.parse(localStorage.getItem('sbt.paper.last')||'null');if(saved?.result)out.textContent='Último Paper · Equity '+Number(saved.result.final_equity||0).toFixed(2)+' · Return '+Number(saved.result.total_return_pct||0).toFixed(2)+'% · '+new Date(saved.updated_at).toLocaleString()+' · PAPER.';}catch(_e){}
  }
  function boot(){mountPaperPanel();if(!document.querySelector('#bot-lab-page[data-bot-paper-v1]'))setTimeout(boot,250)}
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot);else boot();
})();


(() => {
  const KEY='sbt.performance.v1';
  function mountPerformance(){
    const page=document.getElementById('bot-lab-page');
    const paper=page?.querySelector('#sbtStartPaper')?.closest('section');
    if(!page||!paper||page.dataset.performanceMonitorV1)return;
    page.dataset.performanceMonitorV1='1';
    const p=document.createElement('section');p.className='card';p.style.cssText='margin:18px 0;padding:20px';
    p.innerHTML='<span class="eyebrow">PERFORMANCE MONITOR</span><div style="display:flex;justify-content:space-between;gap:12px;align-items:flex-start;flex-wrap:wrap"><div><h2 style="margin:5px 0">Performance</h2><p class="sub">Monitor de equity para Demo/Paper. Solo muestra resultados de simulación.</p></div><span id="sbtPerfMode" class="badge">WAITING</span></div><div id="sbtPerfMetrics" style="display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:10px;margin-top:15px"></div><div id="sbtPerfChart" style="margin-top:14px;min-height:150px"></div><div id="sbtPerfResult" class="result" style="margin-top:14px">Esperando una sesión Demo o Paper…</div>';
    paper.insertAdjacentElement('afterend',p);
    p.querySelector('#sbtPerfMetrics').innerHTML=['Equity','P&L','Return','Drawdown','Trades','Win Rate','Profit Factor','Status'].map(x=>'<div class="card" style="padding:12px"><div class="small">'+x+'</div><strong data-perf="'+x.toLowerCase().replace(/ /g,'-')+'">—</strong></div>').join('');
  }
  function esc(v){return String(v).replace(/[&<>"]/g,x=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[x]));}
  function renderChart(curve){
    const host=document.getElementById('sbtPerfChart');if(!host||!curve?.length){return;}
    const w=700,h=150,pad=10,min=Math.min(...curve),max=Math.max(...curve),span=max-min||1;
    const pts=curve.map((v,i)=>{const x=pad+(i/(curve.length-1))*(w-pad*2);const y=h-pad-((v-min)/span)*(h-pad*2);return x.toFixed(1)+','+y.toFixed(1)}).join(' ');
    host.innerHTML='<svg viewBox="0 0 '+w+' '+h+'" width="100%" height="150" role="img" aria-label="Equity curve"><polyline points="'+esc(pts)+'" fill="none" stroke="currentColor" stroke-width="2"/><text x="10" y="18" font-size="11" fill="currentColor">Equity curve · simulated</text></svg>';
  }
  async function update(result,config,mode){
    const out=document.getElementById('sbtPerfResult');if(!out||!result)return;
    const curve=Array.isArray(result.equity_curve)?result.equity_curve:[];
    if(curve.length<2){out.textContent='Performance unavailable: la sesión no contiene equity curve.';return;}
    const base=((window.SBT_API_URL||localStorage.getItem('sbt_api_base')||'').replace(/\/$/,''));
    try{
      const r=await fetch(base+'/api/v1/built-in-bots/performance/snapshot',{method:'POST',headers:{'Content-Type':'application/json','Accept':'application/json'},body:JSON.stringify({equity_curve:curve,trades:Number(result.trades||0),wins:Number(result.wins||0),initial_capital:Number(result.initial_capital||config?.capital||10000),mode})});
      if(!r.ok)throw new Error('Performance HTTP '+r.status);
      const d=await r.json();if(d.valid===false)throw new Error(d.error||'Performance rejected');
      window.__sbtLastPerformance=d;localStorage.setItem(KEY,JSON.stringify({result:d,config,updated_at:new Date().toISOString()}));
      const set=(k,v)=>{const e=document.querySelector('[data-perf="'+k+'"]');if(e)e.textContent=v;};
      set('equity',Number(d.final_equity||0).toFixed(2));set('p&l',Number(d.pnl||0).toFixed(2));set('return',Number(d.return_pct||0).toFixed(2)+'%');set('drawdown',Number(d.max_drawdown_pct||0).toFixed(2)+'%');set('trades',String(d.trades||0));set('win-rate',Number(d.win_rate_pct||0).toFixed(1)+'%');set('profit-factor',d.profit_factor>900?'∞':Number(d.profit_factor||0).toFixed(2));set('status',d.status||'—');
      const modeEl=document.getElementById('sbtPerfMode');if(modeEl)modeEl.textContent=mode+' · NO LIVE ORDERS';
      out.textContent='PERFORMANCE · '+mode+' · Equity '+Number(d.final_equity||0).toFixed(2)+' · P&L '+Number(d.pnl||0).toFixed(2)+' · Return '+Number(d.return_pct||0).toFixed(2)+'% · DD '+Number(d.max_drawdown_pct||0).toFixed(2)+'%. Solo simulación.';
      renderChart(curve);
    }catch(e){out.textContent='Performance unavailable: '+e.message+'. No se muestran métricas inventadas.';}
  }
  function boot(){mountPerformance();if(!document.querySelector('#bot-lab-page[data-performance-monitor-v1]'))setTimeout(boot,250);}
  window.addEventListener('sbt:demo',e=>update(e.detail?.demo,e.detail?.config,'DEMO'));
  window.addEventListener('sbt:paper',e=>update(e.detail?.paper,e.detail?.config,'PAPER'));
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot);else boot();
})();

(() => {
  const KEY='sbt.myBots.v1';
  const PUBLISH_KEY='sbt.publishedBots.v1';
  const names={grid:'Grid Bot',dca:'DCA Bot',trend:'Trend Bot',breakout:'Breakout Bot','mean-reversion':'Mean Reversion',rebalance:'Rebalance Bot'};
  function bots(){try{return JSON.parse(localStorage.getItem(KEY)||'[]')}catch(_e){return[]}}
  function save(a){localStorage.setItem(KEY,JSON.stringify(a.slice(0,50)))}
  function published(){try{return JSON.parse(localStorage.getItem(PUBLISH_KEY)||'[]')}catch(_e){return[]}}
  function savePublished(a){localStorage.setItem(PUBLISH_KEY,JSON.stringify(a.slice(0,50)))}
  function mountPublishing(){
    const page=document.getElementById('bot-lab-page');
    const perf=page?.querySelector('#sbtPerfResult')?.closest('section');
    if(!page||!perf||page.dataset.botPublishingV1)return;
    page.dataset.botPublishingV1='1';
    const p=document.createElement('section');p.className='card';p.style.cssText='margin:18px 0;padding:20px';
    p.innerHTML='<span class="eyebrow">BOT PUBLISHING</span><div style="display:flex;justify-content:space-between;gap:12px;align-items:flex-start;flex-wrap:wrap"><div><h2 style="margin:5px 0">Publicar bot</h2><p class="sub">Publicar significa dejar el bot disponible en el catálogo SBT. No habilita dinero real.</p></div><span id="sbtPublishBadge" class="badge">PUBLISH LOCKED</span></div><div id="sbtPublishChecks" style="display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:10px;margin-top:15px"></div><div class="toolbar" style="margin-top:14px"><button class="btn primary" id="sbtPublishBot">Publicar en SBT</button><button class="btn" id="sbtRefreshPublished">Actualizar</button></div><div id="sbtPublishResult" class="result" style="margin-top:14px">Selecciona un bot VALIDATED y completa Paper.</div><div id="sbtPublishedList" style="display:grid;gap:10px;margin-top:14px"></div>';
    perf.insertAdjacentElement('afterend',p);
    p.querySelector('#sbtPublishChecks').innerHTML=['VALIDATED','DEMO','PAPER','PERFORMANCE'].map(x=>'<div class="card" style="padding:12px"><div class="small">'+x+'</div><strong data-publish-check="'+x.toLowerCase()+'">PENDING</strong></div>').join('');
    function current(){
      const c=window.__sbtSelectedBotConfig;
      if(!c?.bot_type)return null;
      const all=bots(), clean={...c}; delete clean.bot_id; const signature=JSON.stringify(clean);
      const b=all.find(x=>c.bot_id&&x.id===c.bot_id)||all.find(x=>x.bot_type===c.bot_type && JSON.stringify(x.config||{})===signature)||all.find(x=>x.bot_type===c.bot_type);
      return {config:c,bot:b};
    }
    function checks(){
      const cur=current(), bt=window.__sbtLastBacktest||{}, rb=window.__sbtLastRobustness||{}, risk=window.__sbtLastRisk, demo=window.__sbtLastDemo, paper=window.__sbtLastPaper, perf=window.__sbtLastPerformance||{};
      const validated=!!(bt.valid&&rb.valid&&rb.status==='PASS'&&risk);
      const demoOk=!!(demo?.valid&&demo?.session_mode==='VIRTUAL');
      const paperOk=!!(paper?.valid&&paper?.session_mode==='PAPER');
      const perfOk=!!(perf?.valid&&perf?.mode==='PAPER');
      const ready=!!cur&&validated&&demoOk&&paperOk&&perfOk;
      const set=(k,v)=>{const e=p.querySelector('[data-publish-check="'+k+'"]');if(e)e.textContent=v?'PASS':'PENDING';};
      set('validated',validated);set('demo',demoOk);set('paper',paperOk);set('performance',perfOk);
      const badge=p.querySelector('#sbtPublishBadge');if(badge)badge.textContent=ready?'READY TO PUBLISH':'PUBLISH LOCKED';
      const out=p.querySelector('#sbtPublishResult');
      if(out)out.textContent=ready?'Checklist completo · Publicar crea una entrada de catálogo, no una conexión de ejecución.':'Publicación bloqueada · requiere VALIDATED + DEMO + PAPER + PERFORMANCE.';
      return {ready,cur,perf};
    }
    function render(){
      const list=p.querySelector('#sbtPublishedList'), items=published();
      list.innerHTML=items.length?items.map((b,i)=>'<article class="card" style="padding:14px"><div style="display:flex;justify-content:space-between;gap:10px"><div><strong>'+b.name+'</strong><div class="small">'+b.bot_type.toUpperCase()+' · '+(b.symbol||b.assets||'market')+'</div></div><span class="badge">PUBLISHED · NO LIVE</span></div><div class="small" style="margin-top:8px">Return '+Number(b.return_pct||0).toFixed(2)+'% · DD '+Number(b.drawdown_pct||0).toFixed(2)+'% · Score '+(b.strategy_score??'—')+' · '+new Date(b.published_at).toLocaleString()+'</div></article>').join(''):'<div class="small">No hay bots publicados todavía.</div>';
      checks();
    }
    p.querySelector('#sbtPublishBot').onclick=()=>{
      const q=checks();if(!q.ready||!q.cur?.bot){p.querySelector('#sbtPublishResult').textContent='PUBLISH BLOQUEADO · completa todos los controles.';return;}
      const b=q.cur.bot, perf=q.perf;
      const items=published();
      const previous=items.filter(x=>x.bot_id===b.id||x.bot_type===b.bot_type);
      const version=previous.reduce((m,x)=>Math.max(m,Number(x.version||1)),0)+1;
      const risk=window.__sbtLastRisk||{};
      const entry={id:b.id+'-pub-v'+version+'-'+Date.now(),bot_id:b.id,version,bot_type:b.bot_type,name:b.name,config:{...(b.config||{})},stage:'PUBLISHED',symbol:b.config.symbol,assets:b.config.assets,strategy_score:b.strategy_score,robustness_score:b.robustness_score,return_pct:Number(perf.return_pct||0),drawdown_pct:Number(perf.max_drawdown_pct||0),risk_position_pct:Number(risk.max_position_pct||0),risk_trade_pct:Number(risk.max_loss_per_trade_pct||0),risk_daily_pct:Number(risk.max_daily_loss_pct||0),published_at:new Date().toISOString(),live:false};
      items.unshift(entry);savePublished(items);
      b.stage='PUBLISHED';b.updated_at=new Date().toISOString();save(bots());
      p.querySelector('#sbtPublishResult').textContent='PUBLISHED · '+b.name+' añadido al catálogo SBT. LIVE continúa bloqueado.';
      window.dispatchEvent(new CustomEvent('sbt:published',{detail:entry}));render();
    };
    p.querySelector('#sbtRefreshPublished').onclick=render;
    window.addEventListener('sbt:demo',checks);window.addEventListener('sbt:paper',checks);window.addEventListener('sbt:backtest',checks);window.addEventListener('sbt:robustness',checks);window.addEventListener('sbt:risk-preview',checks);window.addEventListener('sbt:published',render);
    render();
  }
  function boot(){mountPublishing();if(!document.querySelector('#bot-lab-page[data-bot-publishing-v1]'))setTimeout(boot,250)}
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot);else boot();
})();

(() => {
  function mountRebalanceDiagnostics(){
    const page=document.getElementById('bot-lab-page');
    const evalPanel=page?.querySelector('#sbtEvalDecision')?.closest('section');
    if(!page||!evalPanel||page.dataset.rebalanceDiagnosticsV1)return;
    page.dataset.rebalanceDiagnosticsV1='1';
    const p=document.createElement('section');p.className='card';p.style.cssText='margin:18px 0;padding:20px';
    p.innerHTML='<span class="eyebrow">PORTFOLIO ALLOCATION</span><div style="display:flex;justify-content:space-between;gap:12px;align-items:flex-start;flex-wrap:wrap"><div><h2 style="margin:5px 0">Rebalance Monitor</h2><p class="sub">Comparación entre peso objetivo y peso final de la cartera simulada.</p></div><span class="badge">MULTI-ASSET · NO LIVE</span></div><div id="sbtRebalanceWeights" style="display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:10px;margin-top:15px"></div><div id="sbtRebalanceEvents" class="result" style="margin-top:14px">Ejecuta un backtest de Rebalance para ver la composición.</div>';
    evalPanel.insertAdjacentElement('afterend',p);
    function render(){
      const c=window.__sbtSelectedBotConfig||{}; const b=window.__sbtLastBacktest||{};
      if(c.bot_type!=='rebalance'||!b.final_weights_pct){p.style.display=c.bot_type==='rebalance'?'block':'none';return;}
      p.style.display='block'; const target=b.target_weights_pct||{}; const final=b.final_weights_pct||{}; const keys=Object.keys(target);
      p.querySelector('#sbtRebalanceWeights').innerHTML=keys.map(k=>'<div class="card" style="padding:12px"><div class="small">'+k+'</div><strong>Objetivo '+Number(target[k]||0).toFixed(1)+'%</strong><div class="small">Final '+Number(final[k]||0).toFixed(1)+'% · Drift '+(Number(final[k]||0)-Number(target[k]||0)).toFixed(1)+' pp</div></div>').join('');
      const events=b.rebalance_events||[];p.querySelector('#sbtRebalanceEvents').textContent=events.length?'Rebalances ejecutados: '+events.length+' · Último índice: '+events[events.length-1].index+' · Equity en último rebalance: '+Number(events[events.length-1].equity||0).toFixed(2)+' · Drift disparador: '+Number(events[events.length-1].drift_pct||0).toFixed(2)+'%.':'Sin rebalanceos durante la simulación.';
    }
    window.addEventListener('sbt:backtest',render);window.addEventListener('sbt:bot-config',render);render();
  }
  function boot(){mountRebalanceDiagnostics();if(!document.querySelector('#bot-lab-page[data-rebalance-diagnostics-v1]'))setTimeout(boot,250)}
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot);else boot();
})();


(() => {
  const KEY='sbt.publishedBots.v1';
  const CATALOG=[
    {id:'grid',name:'Grid Bot',cat:'Crypto',icon:'▦',desc:'Malla de órdenes para mercados laterales.',market:'BTC/USDT'},
    {id:'dca',name:'DCA Bot',cat:'Portfolio',icon:'◉',desc:'Entradas escalonadas con control de exposición.',market:'BTC/USDT'},
    {id:'trend',name:'Trend Bot',cat:'Forex',icon:'↗',desc:'Seguimiento de tendencia con EMA + RSI + ATR.',market:'EUR/USD'},
    {id:'breakout',name:'Breakout Bot',cat:'Crypto',icon:'⇧',desc:'Rupturas con confirmación de volatilidad.',market:'BTC/USDT'},
    {id:'mean-reversion',name:'Mean Reversion',cat:'Forex',icon:'↔',desc:'Retorno a la media con filtro de régimen.',market:'EUR/USD'},
    {id:'rebalance',name:'Rebalance Bot',cat:'Portfolio',icon:'⇄',desc:'Mantiene pesos objetivo de una cartera.',market:'Multi-asset'}
  ];
  function read(){try{return JSON.parse(localStorage.getItem(KEY)||'[]')}catch(_e){return[]}}
  function mount(){
    const page=document.getElementById('bot-lab-page');
    const publish=page?.querySelector('#sbtPublishResult')?.closest('section');
    if(!page||!publish||page.dataset.botMarketplaceV1)return;
    page.dataset.botMarketplaceV1='1';
    const p=document.createElement('section');
    p.className='card';
    p.style.cssText='margin:18px 0;padding:20px';
    p.innerHTML='<span class="eyebrow">BOT MARKETPLACE</span>'+
      '<div style="display:flex;justify-content:space-between;gap:12px;align-items:flex-start;flex-wrap:wrap">'+
      '<div><h2 style="margin:5px 0">SBT Bot Marketplace</h2><p class="sub">Catálogo interno de bots validados y publicados. Seleccionar un bot prepara su configuración; no activa órdenes.</p></div>'+
      '<span id="sbtMarketBadge" class="badge">NO LIVE</span></div>'+
      '<div class="toolbar" style="margin-top:14px;display:flex;gap:8px;flex-wrap:wrap">'+
      '<input id="sbtMarketSearch" class="input" placeholder="Buscar bot, mercado o categoría…" style="min-width:240px">'+
      '<button class="btn primary" data-market-filter="ALL">Todos</button>'+
      '<button class="btn" data-market-filter="Crypto">Crypto</button>'+
      '<button class="btn" data-market-filter="Forex">Forex</button>'+
      '<button class="btn" data-market-filter="Portfolio">Portfolio</button></div>'+
      '<div id="sbtMarketStats" class="small" style="margin-top:12px"></div>'+
      '<div id="sbtMarketGrid" style="display:grid;grid-template-columns:repeat(auto-fit,minmax(250px,1fr));gap:12px;margin-top:14px"></div>'+
      '<div id="sbtMarketResult" class="result" style="margin-top:14px">Los bots publicados aparecerán aquí.</div>';
    publish.insertAdjacentElement('afterend',p);
    let filter='ALL';
    const esc=v=>String(v??'').replace(/[&<>"]/g,x=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[x]));
    function render(){
      const q=(p.querySelector('#sbtMarketSearch').value||'').toLowerCase().trim();
      const pub=read();
      const publishedCards=pub.map((b,i)=>{
        const c=CATALOG.find(x=>x.id===b.bot_type);
        if(!c)return null;
        const version=Number(b.version||1);
        const label=(b.name||c.name)+' · v'+version;
        const hay=(label+' '+c.market+' '+c.cat+' '+c.desc+' '+(b.symbol||'')+' '+(b.assets||'')).toLowerCase();
        if(filter!=='ALL'&&c.cat!==filter)return null;
        if(q&&!hay.includes(q))return null;
        return {kind:'published',id:b.id,bot:b,c,label,c};
      }).filter(Boolean);
      const templates=CATALOG.filter(c=>{
        const text=(c.name+' '+c.market+' '+c.cat+' '+c.desc).toLowerCase();
        return (filter==='ALL'||c.cat===filter)&&(!q||text.includes(q));
      }).map(c=>({kind:'template',id:c.id,c}));
      const cards=publishedCards.concat(templates);
      const counts=pub.reduce((m,x)=>(m[x.bot_type]=(m[x.bot_type]||0)+1,m),{});
      p.querySelector('#sbtMarketStats').textContent=pub.length+' versión(es) publicada(s) · '+cards.length+' entrada(s) visibles · '+Object.keys(counts).length+' bot(s) con versiones · LIVE bloqueado';
      p.querySelector('#sbtMarketGrid').innerHTML=cards.map(item=>{
        const c=item.c;
        if(item.kind==='published'){
          const b=item.bot;
          const metrics='Return '+Number(b.return_pct||0).toFixed(2)+'% · DD '+Number(b.drawdown_pct||0).toFixed(2)+'% · Score '+(b.strategy_score??'—');
          const when=b.published_at?new Date(b.published_at).toLocaleString():'';
          return '<article class="card" style="padding:15px">'+
            '<div style="display:flex;justify-content:space-between;gap:8px"><span style="font-size:24px">'+c.icon+'</span><span class="badge">PUBLISHED · NO LIVE</span></div>'+
            '<h3 style="margin:10px 0 4px">'+esc(b.name||c.name)+'</h3>'+
            '<div class="small">'+esc(c.cat)+' · '+esc(c.market)+' · v'+Number(b.version||1)+'</div>'+
            '<p class="sub" style="min-height:42px">'+esc(c.desc)+'</p>'+
            '<div class="small" style="margin:8px 0">'+esc(metrics)+(when?' · '+esc(when):'')+'</div>'+
            '<button class="btn primary sbt-market-use" data-kind="published" data-id="'+esc(b.id)+'">Usar bot</button></article>';
        }
        return '<article class="card" style="padding:15px">'+
          '<div style="display:flex;justify-content:space-between;gap:8px"><span style="font-size:24px">'+c.icon+'</span><span class="badge">BUILT-IN TEMPLATE</span></div>'+
          '<h3 style="margin:10px 0 4px">'+esc(c.name)+'</h3>'+
          '<div class="small">'+esc(c.cat)+' · '+esc(c.market)+'</div>'+
          '<p class="sub" style="min-height:42px">'+esc(c.desc)+'</p>'+
          '<div class="small" style="margin:8px 0">Pendiente de validar y publicar</div>'+
          '<button class="btn sbt-market-use" data-kind="template" data-id="'+esc(c.id)+'">Ver plantilla</button></article>';
      }).join('')||'<div class="small">No hay coincidencias.</div>';
      p.querySelectorAll('.sbt-market-use').forEach(btn=>btn.onclick=()=>{
        const id=btn.dataset.id, kind=btn.dataset.kind, c=CATALOG.find(x=>x.id===id);
        if(!c)return;
        if(kind==='published'){
          const b=pub.find(x=>String(x.id)===String(id));
          if(!b)return;
          window.__sbtSelectedBotConfig={...(b.config||{}),bot_type:b.bot_type,bot_id:b.id};
          window.dispatchEvent(new CustomEvent('sbt:bot-config',{detail:window.__sbtSelectedBotConfig}));
          p.querySelector('#sbtMarketResult').textContent='Versión cargada: '+(b.name||c.name)+' v'+Number(b.version||1)+' · configuración preparada para backtest. DEMO/PAPER · NO LIVE.';
        }else{
          const defaults={grid:{bot_type:'grid',symbol:'BTC/USDT',capital:10000,lower:90000,upper:120000,grids:12},dca:{bot_type:'dca',symbol:'BTC/USDT',capital:10000,initial:1000,safety:500,step:2,multiplier:1.5},trend:{bot_type:'trend',symbol:'EUR/USD',timeframe:'H1',capital:10000,emaFast:8,emaSlow:21,rsi:14,atr:14},breakout:{bot_type:'breakout',symbol:'BTC/USDT',timeframe:'H1',capital:10000,lookback:20,atr:14},'mean-reversion':{bot_type:'mean-reversion',symbol:'EUR/USD',timeframe:'H1',capital:10000,rsiLow:30,rsiHigh:70},rebalance:{bot_type:'rebalance',assets:'BTC/USDT,ETH/USDT,USDT',capital:10000,btc:50,eth:30,cash:20,threshold:5,frequency:20}};
          window.__sbtSelectedBotConfig=defaults[id]||{bot_type:id};
          window.dispatchEvent(new CustomEvent('sbt:bot-config',{detail:window.__sbtSelectedBotConfig}));
          p.querySelector('#sbtMarketResult').textContent='Plantilla '+c.name+' cargada. Ejecuta backtest y validación antes de publicar.';
        }
      });
    }
    p.querySelector('#sbtMarketSearch').oninput=render;
    p.querySelectorAll('[data-market-filter]').forEach(btn=>btn.onclick=()=>{filter=btn.dataset.marketFilter;render();});
    window.addEventListener('sbt:published',render);
    window.addEventListener('sbt:bot-saved',render);
    render();
  }
  function boot(){mount();if(!document.querySelector('#bot-lab-page[data-bot-marketplace-v1]'))setTimeout(boot,250)}
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot);else boot();
})();

(() => {
  const KEY='sbt.publishedBots.v1', MY='sbt.myBots.v1';
  const names={grid:'Grid Bot',dca:'DCA Bot',trend:'Trend Bot',breakout:'Breakout Bot','mean-reversion':'Mean Reversion',rebalance:'Rebalance Bot'};
  const read=k=>{try{return JSON.parse(localStorage.getItem(k)||'[]')}catch(_e){return[]}};
  const write=(k,v)=>localStorage.setItem(k,JSON.stringify(v.slice(0,50)));
  const esc=v=>String(v??'').replace(/[&<>"]/g,x=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[x]));
  function mount(){
    const page=document.getElementById('bot-lab-page'), market=page?.querySelector('#sbtMarketGrid')?.closest('section');
    if(!page||!market||page.dataset.botMarketplaceDetailV1)return;
    page.dataset.botMarketplaceDetailV1='1';
    const p=document.createElement('section');p.className='card';p.style.cssText='margin:18px 0;padding:20px';
    p.innerHTML='<span class="eyebrow">BOT DETAILS</span><div style="display:flex;justify-content:space-between;gap:12px;align-items:flex-start;flex-wrap:wrap"><div><h2 id="sbtBotDetailTitle" style="margin:5px 0">Selecciona una versión</h2><p id="sbtBotDetailSub" class="sub">Detalle, configuración y evolución de versiones.</p></div><span class="badge">DEMO / PAPER · LIVE LOCKED</span></div><div id="sbtBotDetailMetrics" style="display:grid;grid-template-columns:repeat(auto-fit,minmax(130px,1fr));gap:10px;margin-top:15px"></div><div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:12px;margin-top:15px"><div class="card" style="padding:14px"><div class="small">CONFIGURACIÓN</div><pre id="sbtBotDetailConfig" style="white-space:pre-wrap;overflow:auto;margin-top:8px">—</pre></div><div class="card" style="padding:14px"><div class="small">VERSION HISTORY</div><div id="sbtBotDetailHistory" style="margin-top:8px">—</div></div></div><div class="toolbar" style="margin-top:14px"><button class="btn primary" id="sbtBotDetailUse">Usar versión</button><button class="btn" id="sbtBotDetailClone">Clonar versión</button></div><div id="sbtBotDetailResult" class="result" style="margin-top:14px">LIVE permanece bloqueado.</div>';
    market.insertAdjacentElement('afterend',p);
    let selected=null;
    function render(){
      if(!selected){p.querySelector('#sbtBotDetailTitle').textContent='Selecciona una versión';p.querySelector('#sbtBotDetailSub').textContent='Abre una versión publicada desde el Marketplace para ver su detalle.';p.querySelector('#sbtBotDetailMetrics').innerHTML='';p.querySelector('#sbtBotDetailConfig').textContent='—';p.querySelector('#sbtBotDetailHistory').innerHTML='—';return;}
      const all=read(KEY), versions=all.filter(x=>x.bot_id===selected.bot_id||x.bot_type===selected.bot_type).sort((a,b)=>Number(b.version||0)-Number(a.version||0));
      const name=selected.name||names[selected.bot_type]||selected.bot_type;
      p.querySelector('#sbtBotDetailTitle').textContent=name+' · v'+Number(selected.version||1);
      p.querySelector('#sbtBotDetailSub').textContent=(selected.bot_type||'').toUpperCase()+' · '+(selected.symbol||selected.assets||'market')+' · PUBLISHED · NO LIVE';
      const metrics=[['Return',Number(selected.return_pct||0).toFixed(2)+'%'],['Drawdown',Number(selected.drawdown_pct||0).toFixed(2)+'%'],['Strategy Score',selected.strategy_score??'—'],['Robustness',selected.robustness_score??'—'],['Risk Gate',selected.risk_position_pct!=null?'PASS':'—'],['Published',selected.published_at?new Date(selected.published_at).toLocaleString():'—']];
      p.querySelector('#sbtBotDetailMetrics').innerHTML=metrics.map(x=>'<div class="card" style="padding:12px"><div class="small">'+esc(x[0])+'</div><strong>'+esc(x[1])+'</strong></div>').join('');
      const cfg={...(selected.config||{})};delete cfg.bot_id;p.querySelector('#sbtBotDetailConfig').textContent=JSON.stringify(cfg,null,2);
      p.querySelector('#sbtBotDetailHistory').innerHTML=versions.map(v=>'<button type="button" class="btn '+(String(v.id)===String(selected.id)?'primary':'')+' sbt-version-select" data-id="'+esc(v.id)+'" style="width:100%;text-align:left;margin-bottom:6px">v'+Number(v.version||1)+' · Return '+Number(v.return_pct||0).toFixed(2)+'% · DD '+Number(v.drawdown_pct||0).toFixed(2)+'% · Score '+esc(v.strategy_score??'—')+'</button>').join('')||'<div class="small">Sin historial.</div>';
      p.querySelector('#sbtBotDetailResult').textContent=(selected.risk_position_pct!=null?'Risk Gate · posición '+Number(selected.risk_position_pct).toFixed(2)+'% · pérdida/trade '+Number(selected.risk_trade_pct||0).toFixed(2)+'% · pérdida diaria '+Number(selected.risk_daily_pct||0).toFixed(2)+'%':'Risk Gate registrado durante validación')+' · DEMO/PAPER · LIVE LOCKED.';
    }
    function useSelected(){if(!selected)return;window.__sbtSelectedBotConfig={...(selected.config||{}),bot_type:selected.bot_type,bot_id:selected.bot_id||selected.id};window.dispatchEvent(new CustomEvent('sbt:bot-config',{detail:window.__sbtSelectedBotConfig}));p.querySelector('#sbtBotDetailResult').textContent='Versión v'+Number(selected.version||1)+' cargada. Preparada para backtest; no ejecuta órdenes live.';}
    function cloneSelected(){
      if(!selected)return;const cfg={...(selected.config||{})};delete cfg.bot_id;const clone={id:selected.bot_type+'-'+Date.now()+'-'+Math.random().toString(36).slice(2,8),bot_type:selected.bot_type,name:(selected.name||names[selected.bot_type]||selected.bot_type)+' Clone v'+Number(selected.version||1),config:cfg,stage:'DRAFT',strategy_score:null,robustness_score:null,created_at:new Date().toISOString(),updated_at:new Date().toISOString(),cloned_from:selected.id};
      const my=read(MY);my.unshift(clone);write(MY,my);window.__sbtSelectedBotConfig={...cfg,bot_type:selected.bot_type,bot_id:clone.id};window.dispatchEvent(new CustomEvent('sbt:bot-saved',{detail:clone}));window.dispatchEvent(new CustomEvent('sbt:bot-config',{detail:window.__sbtSelectedBotConfig}));p.querySelector('#sbtBotDetailResult').textContent='CLONADO · '+clone.name+' · DRAFT. Debe volver a pasar Backtest → Robustness → Risk Gate → Demo → Paper.';
    }
    p.addEventListener('click',e=>{const v=e.target.closest('.sbt-version-select');if(v){selected=read(KEY).find(x=>String(x.id)===String(v.dataset.id))||null;render();}});
    p.querySelector('#sbtBotDetailUse').onclick=useSelected;p.querySelector('#sbtBotDetailClone').onclick=cloneSelected;
    window.addEventListener('sbt:market-detail',e=>{selected=read(KEY).find(x=>String(x.id)===String(e.detail?.id))||null;render();});
    window.addEventListener('sbt:published',e=>{const risk=window.__sbtLastRisk;if(e.detail?.id&&risk){const pub=read(KEY),i=pub.findIndex(x=>String(x.id)===String(e.detail.id));if(i>=0){pub[i].risk_position_pct=Number(risk.max_position_pct??0);pub[i].risk_trade_pct=Number(risk.max_loss_per_trade_pct??0);pub[i].risk_daily_pct=Number(risk.max_daily_loss_pct??0);write(KEY,pub);selected=pub[i];}}render();});
    render();
  }
  function wireMarketplace(){const page=document.getElementById('bot-lab-page'),grid=page?.querySelector('#sbtMarketGrid');if(!grid)return false;if(!grid.dataset.detailWired){grid.dataset.detailWired='1';grid.addEventListener('click',e=>{const btn=e.target.closest('.sbt-market-use');if(btn?.dataset.kind==='published')window.dispatchEvent(new CustomEvent('sbt:market-detail',{detail:{id:btn.dataset.id}}));});}return true;}
  function boot(){mount();if(!wireMarketplace())setTimeout(boot,250)}
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot);else boot();
})();


(() => {
  const KEY='sbt.publishedBots.v1';
  const esc=v=>String(v??'').replace(/[&<>"]/g,x=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[x]));
  const read=()=>{try{return JSON.parse(localStorage.getItem(KEY)||'[]')}catch(_e){return[]}};
  function mount(){
    const page=document.getElementById('bot-lab-page'), grid=page?.querySelector('#sbtMarketGrid');
    const detail=page?.querySelector('#sbtBotDetailHistory')?.closest('section');
    if(!page||!grid||!detail||page.dataset.botVersionCompareV1)return;
    page.dataset.botVersionCompareV1='1';
    const host=document.createElement('div');host.style.cssText='margin-top:12px';
    host.innerHTML='<button class="btn" id="sbtCompareVersions">Comparar versiones</button><div id="sbtVersionCompare" class="result" style="display:none;margin-top:10px"></div>';
    detail.appendChild(host);
    let selectedIds=[];
    function render(){
      const out=host.querySelector('#sbtVersionCompare'), all=read();
      if(selectedIds.length!==2){out.style.display='none';return;}
      const a=all.find(x=>String(x.id)===String(selectedIds[0])),b=all.find(x=>String(x.id)===String(selectedIds[1]));
      if(!a||!b){out.style.display='none';return;}
      const delta=(x,y)=>Number(x||0)-Number(y||0);
      out.style.display='block';
      out.innerHTML='<strong>v'+Number(a.version||1)+' vs v'+Number(b.version||1)+'</strong>'+
        '<div class="small" style="margin-top:8px">Return Δ '+delta(a.return_pct,b.return_pct).toFixed(2)+' pp · DD Δ '+delta(a.drawdown_pct,b.drawdown_pct).toFixed(2)+' pp · Strategy Score Δ '+delta(a.strategy_score,b.strategy_score).toFixed(2)+' · Robustness Δ '+delta(a.robustness_score,b.robustness_score).toFixed(2)+'</div>'+
        '<div class="small" style="margin-top:6px">Risk posición '+Number(a.risk_position_pct||0).toFixed(2)+'% vs '+Number(b.risk_position_pct||0).toFixed(2)+'% · trade '+Number(a.risk_trade_pct||0).toFixed(2)+'% vs '+Number(b.risk_trade_pct||0).toFixed(2)+'% · diario '+Number(a.risk_daily_pct||0).toFixed(2)+'% vs '+Number(b.risk_daily_pct||0).toFixed(2)+'%</div>'+
        '<div class="small" style="margin-top:6px">Comparación informativa; no autoriza ejecución live.</div>';
    }
    host.querySelector('#sbtCompareVersions').onclick=()=>{
      const all=read();
      const botType=window.__sbtSelectedBotConfig?.bot_type;
      const versions=all.filter(x=>x.bot_type===botType).sort((a,b)=>Number(b.version||0)-Number(a.version||0));
      if(versions.length<2){host.querySelector('#sbtVersionCompare').style.display='block';host.querySelector('#sbtVersionCompare').textContent='Se necesitan al menos dos versiones publicadas del mismo bot para comparar.';return;}
      selectedIds=[versions[0].id,versions[1].id];render();
    };
  }
  function boot(){mount();if(!document.querySelector('#bot-lab-page[data-bot-version-compare-v1]'))setTimeout(boot,250)}
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot);else boot();
})();
