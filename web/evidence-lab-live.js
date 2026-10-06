(() => {
  'use strict';

  const API = (window.SBT_API_URL || 'https://bitey-system-bots-trading-api.onrender.com').replace(/\/$/, '');
  const esc = v => String(v ?? '—').replace(/[&<>"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
  const text = (id, value) => { const e = document.getElementById(id); if (e) e.textContent = value ?? '—'; };
  const num = (v, d=2) => Number.isFinite(Number(v)) ? Number(v).toFixed(d) : '—';
  const ageSec = ts => { const t=Date.parse(ts||''); return Number.isFinite(t) ? Math.max(0,(Date.now()-t)/1000) : Infinity; };

  let lastReport = null;
  let lastTrades = [];

  async function get(path) {
    const r = await fetch(API + path, { cache: 'no-store' });
    if (!r.ok) throw new Error('HTTP ' + r.status);
    return r.json();
  }

  function normalize(raw) {
    const r = raw?.report || raw?.data || raw;
    if (!r || !r.symbol) return null;
    const state = r.state || {};
    const risk = r.risk || {};
    const counters = r.counters || {};
    const metrics = r.metrics || {};
    const signal = r.signal || metrics.signal || state.current || 'NONE';
    const positions = Number(metrics.positions_open ?? state.position_count ?? r.account?.position_count ?? 0);
    return {
      ...r,
      signal,
      direction: r.direction || (signal === 'BUY' || signal === 'SELL' ? signal : 'NONE'),
      previous_signal: r.previous_signal || state.previous || 'NONE',
      signal_change: r.signal_change || state.change || 'NONE',
      regime: r.regime || 'UNKNOWN',
      strategy: r.strategy || r.bot?.strategy || 'ENSEMBLE',
      timeframe: r.timeframe || r.strategy_timeframe || 'M15',
      chart_timeframe: r.chart_timeframe || 'H1',
      account: r.account || {},
      metrics: { ...metrics, ...state, ...counters },
      risk,
      bot: r.bot || {},
      positions,
      operational_capital: Number(risk.operational_capital_usd || 0),
      age: ageSec(r.timestamp)
    };
  }

  function signalBadge(signal) {
    const s=String(signal||'NONE').toUpperCase();
    const cls=s==='BUY'?'badge':'badge '+(s==='SELL'?'danger':'warn');
    return '<span class="'+cls+'">'+esc(s)+'</span>';
  }

  function ensureGlobalPanel() {
    let host=document.getElementById('mt4LiveContext');
    if (host) return host;
    host=document.createElement('section');
    host.id='mt4LiveContext';
    host.style.cssText='margin:0 0 12px;padding:12px 14px;background:#080f15;border:1px solid #263746;border-radius:10px;';
    host.innerHTML='<div style="display:flex;justify-content:space-between;gap:10px;align-items:center;flex-wrap:wrap"><div><span class="eyebrow">MT4 → SBT · LIVE TELEMETRY</span><strong id="mt4LiveTitle" style="display:block;margin-top:3px">Esperando MT4…</strong></div><div id="mt4LiveHeartbeat" class="badge">OFFLINE</div></div><div id="mt4LiveGrid" style="display:grid;grid-template-columns:repeat(8,minmax(90px,1fr));gap:7px;margin-top:10px"></div><div id="mt4LiveMeta" class="small" style="margin-top:8px"></div>';
    const main=document.querySelector('.main');
    const top=main?.querySelector('.top');
    if(top) top.insertAdjacentElement('afterend',host);
    return host;
  }

  function renderGlobal(r) {
    const host=ensureGlobalPanel();
    if(!r) {
      text('mt4LiveTitle','Esperando el primer snapshot de MT4…');
      const hb=document.getElementById('mt4LiveHeartbeat'); if(hb){hb.textContent='OFFLINE';hb.className='badge danger';}
      return;
    }
    text('mt4LiveTitle', (r.bot?.name || 'Bitey Evidence Lab v1.02')+' · '+r.symbol+' · '+r.timeframe);
    const hb=document.getElementById('mt4LiveHeartbeat');
    const fresh=r.age<90;
    if(hb){hb.textContent=fresh?'ONLINE · '+num(r.age,0)+'s':'STALE · '+num(r.age,0)+'s';hb.className=fresh?'badge':'badge warn';}
    const vals=[
      ['SIGNAL',r.signal],['DIRECTION',r.direction],['REGIME',r.regime],['POSITIONS',r.positions],
      ['CAPITAL','$'+num(r.operational_capital,2)],['RISK',num(r.risk.risk_pct,3)+'%'],
      ['DD',num(r.metrics.daily_drawdown_pct,3)+'%'],['TRADES',r.metrics.trades_today ?? '—']
    ];
    const grid=document.getElementById('mt4LiveGrid');
    if(grid) grid.innerHTML=vals.map(([k,v])=>'<div style="padding:7px 8px;background:#0b151d;border:1px solid #1b2a36;border-radius:7px"><span style="display:block;color:#6f8090;font-size:8px">'+k+'</span><b style="display:block;margin-top:3px">'+esc(v)+'</b></div>').join('');
    text('mt4LiveMeta',
      'Strategy '+r.strategy+' · Strategy TF '+r.timeframe+' · Chart '+r.chart_timeframe+
      ' · Mode reported by MT4 '+(r.mode||'UNKNOWN')+
      ' · Demo environment: '+(r.account?.operating_environment || (r.mode==='REAL'?'DEMO (configured)':'UNKNOWN'))+
      ' · Last change: '+r.signal_change);
  }

  function fillPageSpecific(r) {
    if(!r) return;
    const m=r.metrics||{}, a=r.account||{}, risk=r.risk||{}, c=r.counters||m;
    text('terminalSymbol',r.symbol);
    text('terminalTimeframe',r.chart_timeframe || r.timeframe);
    text('terminalEnvironment',r.account?.operating_environment || (r.mode==='REAL'?'DEMO':'UNKNOWN'));
    text('terminalExecution',r.execution_enabled?'MT4 EXECUTION ENABLED':'OBSERVE / BLOCKED');
    text('apiStatus','MT4 '+(r.age<90?'CONNECTED':'STALE')+' · '+r.symbol+' · '+r.signal);

    text('eccMt4',r.age<90?'ONLINE':'STALE');
    text('eccMt4Meta',r.symbol+' · '+r.timeframe+' · heartbeat '+num(r.age,0)+'s');
    text('eccBots','1');
    text('eccBotsMeta',r.bot?.name||'Bitey Evidence Lab v1.02');
    text('eccMarket',r.symbol+' · '+r.timeframe);
    text('eccChartTf',r.chart_timeframe||'H1');
    text('eccMode',r.account?.operating_environment || (r.mode==='REAL'?'DEMO':'UNKNOWN'));
    text('eccBot',r.bot?.name||'Bitey Evidence Lab v1.02');
    text('eccSignal',(r.signal||'NONE')+' · '+(r.regime||'UNKNOWN'));
    text('eccNext',r.signal==='BUY'||r.signal==='SELL'?'Evaluar Risk Gate / ejecución MT4':'Esperando señal válida');
    text('eccNotice','MT4 snapshot recibido. SBT observa; MT4 conserva la autoridad de ejecución.');
    text('dashboardEvidence',r.signal && r.signal!=='NONE'?'LIVE SNAPSHOT':'WAITING MT4');

    text('observerSelectedBot',r.bot?.name||'Bitey Evidence Lab v1.02');
    text('observerSignal',r.signal);
    text('observerRegime',r.regime);
    text('observerDirection',r.direction);
    text('observerPositionCount',r.positions);
    text('observerRiskDD',num(m.daily_drawdown_pct,3)+'%');
    text('observerExplanation','Último snapshot recibido desde MT4/SBT. Señales y riesgo provienen del Evidence Lab v1.02.');

    text('aiBotName',r.bot?.name||'Bitey Evidence Lab v1.02');
    text('aiBotConnection',r.age<90?'MT4 conectado':'MT4 stale');
    text('aiBotMarket',r.symbol+' · '+r.timeframe);
    text('aiBotMode',r.account?.operating_environment || (r.mode==='REAL'?'DEMO':'UNKNOWN'));
    text('aiEnvironment',r.account?.operating_environment || (r.mode==='REAL'?'DEMO':'UNKNOWN'));
    text('aiProductionStatus',r.execution_enabled?'DEMO / MT4 ENABLED':'OBSERVATION');
    text('aiBotParams',
      'Strategy='+r.strategy+' · TF='+r.timeframe+' · Chart='+r.chart_timeframe+
      ' · Capital=$'+num(r.operational_capital,2)+' · Risk='+num(risk.risk_pct,3)+'%'+
      ' · Max DD='+num(risk.max_daily_loss_pct,3)+'% · Max trades/day='+(risk.max_trades_day??'—'));
    const msg=document.getElementById('aiBotMessages');
    if(msg) msg.innerHTML='• Señal actual: '+signalBadge(r.signal)+'<br>• Dirección: '+esc(r.direction)+'<br>• Régimen: '+esc(r.regime)+'<br>• Posiciones: '+esc(r.positions)+'<br>• Último cambio: '+esc(r.signal_change);
    text('aiBotRecommendation',r.signal==='BUY'||r.signal==='SELL'?'Bitey debe evaluar la señal con Risk Gate antes de cualquier acción.':'Esperando una señal operable del Evidence Lab.');

    text('turtleConnection',r.age<90?'ONLINE':'STALE');
    text('turtleHeartbeat',new Date(r.timestamp).toLocaleTimeString());
    text('turtleExec',r.execution_enabled?'MT4 EXECUTION ENABLED':'EVIDENCE LAB · READ ONLY');
    text('turtleStatus','Evidence Lab v1.02 conectado. Esta pantalla muestra el snapshot MT4 aunque el bot no sea Turtle.');
    text('turtleS1Signals',(Number(c.buy_signals||0)+Number(c.sell_signals||0))+' (B '+Number(c.buy_signals||0)+' / S '+Number(c.sell_signals||0)+')');
    text('turtleS2Signals','—');
    text('turtleHistoryBlocked',Number(c.block_spread||0)+Number(c.block_session||0)+Number(c.block_daily_dd||0)+Number(c.block_trade_limit||0));
    text('turtleBalance',a.balance!=null?num(a.balance,2):'$'+num(r.operational_capital,2));
    text('turtleEquity',a.equity!=null?num(a.equity,2):'$'+num(r.operational_capital,2));
    text('turtleRegime',r.regime);
    text('turtleModePanel','Entorno operativo: DEMO · MT4 reporta '+(r.mode||'UNKNOWN')+' · capital operativo $'+num(r.operational_capital,2));

    text('validationEnvironment',r.account?.operating_environment || 'DEMO');
    text('validationStatus',r.signal!=='NONE'?'MT4 evidence received':'Waiting for MT4 evidence');

    const riskPanel=document.getElementById('riskGateMt4Evidence');
    if(riskPanel) riskPanel.innerHTML='<strong>MT4 Evidence Lab</strong><br>Signal '+signalBadge(r.signal)+' · '+esc(r.symbol)+' · '+esc(r.timeframe)+'<br>Capital operativo $'+num(r.operational_capital,2)+' · Risk '+num(risk.risk_pct,3)+'% · DD '+num(m.daily_drawdown_pct,3)+'% · Positions '+r.positions;
  }

  function ensureRiskPanel(){
    if(document.getElementById('riskGateMt4Evidence')) return;
    const risk=document.getElementById('risk');
    if(!risk) return;
    const p=document.createElement('div');p.id='riskGateMt4Evidence';p.className='notice';p.style.marginBottom='12px';risk.insertBefore(p,risk.firstChild);
  }

  function renderHistory(items){
    const body=document.getElementById('turtleHistoryBody');
    if(!body)return;
    if(!items.length){body.innerHTML='<tr><td colspan="10" class="muted">Sin snapshots recibidos.</td></tr>';return;}
    body.innerHTML=items.slice(0,20).map(x=>{
      const r=normalize(x),m=r?.metrics||{};
      return '<tr><td>'+new Date(r.timestamp).toLocaleTimeString()+'</td><td>'+esc(r.symbol)+'</td><td>'+esc(r.regime)+'</td><td>'+esc(r.direction)+'</td><td>'+esc(r.positions)+'</td><td>—</td><td>—</td><td>—</td><td>'+esc(r.account?.equity??'$'+num(r.operational_capital,2))+'</td><td>'+esc(m.trades_today??0)+'</td></tr>';
    }).join('');
  }

  function renderTrades(items){
    lastTrades=items||[];
    const rows=document.querySelectorAll('#observerActivityBody');
    rows.forEach(body=>{
      if(!lastTrades.length){body.innerHTML='<tr><td colspan="7" class="muted">Sin operaciones cerradas recibidas desde MT4.</td></tr>';return;}
      body.innerHTML=lastTrades.slice(0,20).map(t=>'<tr><td>'+esc(t.close_time||t.open_time||'—')+'</td><td>'+esc(t.bot_id||t.source||'MT4')+'</td><td>'+esc(t.exit_reason||'CLOSED')+'</td><td>'+esc(t.symbol)+'</td><td>'+esc(t.side)+'</td><td>1</td><td>'+num(t.pnl,2)+'</td></tr>').join('');
    });
  }

  async function refresh(){
    try{
      const [latest,history,trades]=await Promise.all([
        get('/api/v1/mt4/bitey-latest'),
        get('/api/v1/mt4/bitey-history?limit=20'),
        get('/api/v1/mt4/trades?limit=20')
      ]);
      const r=normalize(latest);
      lastReport=r;
      renderGlobal(r);
      ensureRiskPanel();
      fillPageSpecific(r);
      renderHistory(history?.items||[]);
      renderTrades(trades?.items||[]);
      window.dispatchEvent(new CustomEvent('sbt:mt4-live',{detail:{report:r,history:history?.items||[],trades:trades?.items||[]}}));
    }catch(e){
      renderGlobal(null);
      const st=document.getElementById('apiStatus'); if(st)st.textContent='SBT MT4 API unavailable';
    }
  }

  function boot(){
    ensureGlobalPanel();
    ensureRiskPanel();
    refresh();
    setInterval(refresh,5000);
  }

  if(document.readyState==='loading') document.addEventListener('DOMContentLoaded',boot,{once:true});
  else boot();
})();
