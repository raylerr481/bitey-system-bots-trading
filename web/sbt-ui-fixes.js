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
    rebalance:{title:'Rebalance Bot',fields:[['assets','Activos','BTC/USDT,ETH/USDT,USDT','text'],['capital','Capital','10000','number'],['btc','BTC %','50','number'],['eth','ETH %','30','number'],['cash','Cash %','20','number'],['threshold','Umbral rebalance %','5','number']]}
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
    p.querySelector('#sbtBotRisk').onclick=async()=>{if(!selected){out.style.display='block';out.textContent='Selecciona un bot primero.';return;}out.style.display='block';out.textContent='Consultando Risk Gate…';try{const base=((window.SBT_API_URL||localStorage.getItem('sbt_api_base')||'').replace(/\/$/,''));const cfg=read();const r=await fetch(base+'/api/v1/built-in-bots/risk-preview',{method:'POST',headers:{'Content-Type':'application/json','Accept':'application/json'},body:JSON.stringify({bot_type:selected,prices:[1,1],initial_capital:Number(cfg.capital||10000),config:cfg})});if(!r.ok)throw new Error('API HTTP '+r.status);const d=await r.json();if(d.valid===false)throw new Error(d.error||'Risk preview rejected');out.textContent='RISK GATE · posición máxima '+Number(d.max_position_value||0).toFixed(2)+' · pérdida/trade '+Number(d.configured_loss_per_trade||0).toFixed(2)+' · pérdida diaria '+Number(d.configured_daily_loss||0).toFixed(2)+'. DEMO/PAPER · LIVE LOCKED.';}catch(e){out.textContent='Risk Gate unavailable: '+e.message+'. No se muestran límites inventados.';}};
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
      if(prices.length<30)throw new Error('Insuficientes datos: '+prices.length+' cierres');
      const br=await fetch(base+'/api/v1/built-in-bots/backtest',{method:'POST',headers:{'Content-Type':'application/json','Accept':'application/json'},body:JSON.stringify({bot_type:c.bot_type,prices,initial_capital:Number(c.capital||10000),config:c})});
      if(!br.ok)throw new Error('Backtest HTTP '+br.status);
      const b=await br.json(); if(b.valid===false)throw new Error(b.error||'Backtest rejected'); window.__sbtLastBacktest=b;
      window.dispatchEvent(new CustomEvent('sbt:backtest',{detail:{backtest:b,config:c,symbol,timeframe:tf}}));
      try{
        const rr=await fetch(base+'/api/v1/built-in-bots/robustness',{method:'POST',headers:{'Content-Type':'application/json','Accept':'application/json'},body:JSON.stringify({bot_type:c.bot_type,prices,initial_capital:Number(c.capital||10000),config:c})});
        if(rr.ok){const rb=await rr.json();window.__sbtLastRobustness=rb;window.dispatchEvent(new CustomEvent('sbt:robustness',{detail:{robustness:rb,config:c,symbol,timeframe:tf}}));}
      }catch(_e){/* robustness is advisory; backtest remains available */}
      out.textContent='BACKTEST DISPONIBLE · '+c.bot_type+' · '+symbol+' '+tf+' · '+prices.length+' cierres · P/L '+Number(b.total_pnl??b.realized_pnl??0).toFixed(2)+'. Este resultado usa el motor SBT disponible; parámetros no soportados por el endpoint no se simulan. Sin órdenes live.';
    }catch(e){out.textContent='Backtest unavailable: '+e.message+'. No se muestran métricas inventadas.';}
  });
})();
