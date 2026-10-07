(() => {
  const API = (window.SBT_API_URL || 'https://bitey-system-bots-trading-api.onrender.com').replace(/\/$/, '');
  const esc = (v) => String(v ?? '—').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const fmt = (v, d=2) => v == null || v === '' || Number.isNaN(Number(v)) ? '—' : Number(v).toFixed(d);
  const fetchJson = async (path) => {
    const r = await fetch(API + path, {cache:'no-store'});
    if (!r.ok) throw new Error('HTTP ' + r.status);
    return r.json();
  };

  function installStyle() {
    if (document.getElementById('sbt-live-center-style')) return;
    const s = document.createElement('style');
    s.id = 'sbt-live-center-style';
    s.textContent = `
      #sbtLiveCenter{margin:0 0 12px;padding:12px;background:linear-gradient(180deg,#081018,#070c12);border:1px solid #243545;border-radius:12px}
      #sbtLiveCenter .slc-head{display:flex;justify-content:space-between;gap:12px;align-items:center;margin-bottom:10px}
      #sbtLiveCenter .slc-title{font-size:12px;font-weight:900;letter-spacing:.08em}
      #sbtLiveCenter .slc-sub{font-size:10px;color:#738396}
      #sbtLiveCenter .slc-live{font-size:9px;padding:4px 7px;border-radius:99px;border:1px solid #24563f;background:#0b1a14;color:#52e6a2;font-weight:900}
      #sbtLiveCenter .slc-grid{display:grid;grid-template-columns:repeat(6,1fr);gap:7px}
      #sbtLiveCenter .slc-cell{padding:9px;border:1px solid #1b2835;background:#090f15;border-radius:8px;min-width:0}
      #sbtLiveCenter .slc-label{display:block;color:#68798b;font-size:8px;text-transform:uppercase;letter-spacing:.1em}
      #sbtLiveCenter .slc-value{display:block;margin-top:4px;font-size:12px;font-weight:850;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
      #sbtLiveCenter .ok{color:#52e6a2}.warn{color:#f2c76d}.bad{color:#ff7272}
      #sbtLiveCenter .slc-flow{display:grid;grid-template-columns:repeat(5,1fr);gap:6px;margin-top:9px}
      #sbtLiveCenter .slc-node{padding:8px;border:1px solid #1d2a37;border-radius:8px;text-align:center;background:#080d13;font-size:9px;color:#78899a}
      #sbtLiveCenter .slc-node.active{border-color:#2d6c52;color:#d9f7e8;background:#0b1813}
      #sbtLiveCenter .slc-node strong{display:block;color:#e9f1f7;font-size:10px;margin-bottom:2px}
      #sbtLiveCenter .slc-detail{display:grid;grid-template-columns:1.1fr .9fr;gap:8px;margin-top:9px}
      #sbtLiveCenter .slc-panel{padding:9px;border:1px solid #1b2835;border-radius:8px;background:#080d13;font-size:10px;line-height:1.55;color:#9aa8b6}
      #sbtLiveCenter .slc-panel b{color:#e8eef4}
      @media(max-width:1000px){#sbtLiveCenter .slc-grid{grid-template-columns:repeat(3,1fr)}}
      @media(max-width:650px){#sbtLiveCenter .slc-grid,#sbtLiveCenter .slc-flow,#sbtLiveCenter .slc-detail{grid-template-columns:1fr 1fr}.slc-detail .slc-panel{grid-column:1/-1}}
    `;
    document.head.appendChild(s);
  }

  function ensure() {
    if (document.getElementById('sbtLiveCenter')) return document.getElementById('sbtLiveCenter');
    const host = document.querySelector('.terminal-strip');
    if (!host) return null;
    const el = document.createElement('section');
    el.id = 'sbtLiveCenter';
    el.innerHTML = '<div class="slc-head"><div><div class="slc-title">LIVE INTELLIGENCE LOOP</div><div class="slc-sub">MT4 → Bridge → SBT → Bitey · evidencia virtual en tiempo real</div></div><span class="slc-live" id="slcPulse">CONNECTING</span></div>' +
      '<div class="slc-grid">' +
      '<div class="slc-cell"><span class="slc-label">MT4</span><span class="slc-value" id="slcMt4">WAITING</span></div>' +
      '<div class="slc-cell"><span class="slc-label">Bot</span><span class="slc-value" id="slcBot">—</span></div>' +
      '<div class="slc-cell"><span class="slc-label">Positions</span><span class="slc-value" id="slcPos">—</span></div>' +
      '<div class="slc-cell"><span class="slc-label">Last P/L</span><span class="slc-value" id="slcPnl">—</span></div>' +
      '<div class="slc-cell"><span class="slc-label">Evidence</span><span class="slc-value" id="slcEvidence">—</span></div>' +
      '<div class="slc-cell"><span class="slc-label">Evolution</span><span class="slc-value" id="slcEvolution">—</span></div>' +
      '</div>' +
      '<div class="slc-flow">' +
      '<div class="slc-node" id="slcNodeMt4"><strong>01 MT4</strong>telemetry</div>' +
      '<div class="slc-node" id="slcNodeBridge"><strong>02 BRIDGE</strong>transport</div>' +
      '<div class="slc-node" id="slcNodeSbt"><strong>03 SBT</strong>analysis</div>' +
      '<div class="slc-node" id="slcNodeBitey"><strong>04 BITEY</strong>context</div>' +
      '<div class="slc-node" id="slcNodeEvo"><strong>05 EVOLUTION</strong>validation</div>' +
      '</div>' +
      '<div class="slc-detail"><div class="slc-panel" id="slcTrade">Esperando operación cerrada recibida desde MT4.</div><div class="slc-panel" id="slcDecision">Esperando evidencia suficiente para una hipótesis de mejora.</div></div>';
    host.insertAdjacentElement('afterend', el);
    return el;
  }

  function set(id, value, cls='') {
    const e=document.getElementById(id); if(!e)return;
    e.textContent=value;
    e.className='slc-value '+cls;
  }

  async function refresh() {
    const el=ensure();
    if(!el)return;
    const pulse=document.getElementById('slcPulse');
    try {
      const [latest, trades, evolution, turtle] = await Promise.all([
        fetchJson('/api/v1/mt4/bitey-latest'),
        fetchJson('/api/v1/mt4/trades?limit=5'),
        fetchJson('/api/v1/evolution/status'),
        fetchJson('/api/v1/turtle/context')
      ]);
      const account=latest?.account || {};
      const bot=latest?.bot || {};
      const items=trades?.items || [];
      const last=items[0] || {};
      const observed=Boolean(latest?.timestamp || turtle?.observed);
      const mt4Mode=account.mode || latest?.mode || turtle?.state?.mode || 'UNKNOWN';
      const evidenceCount=Number(evolution?.telemetry_snapshots || 0);
      const backtests=Number(evolution?.backtests || 0);
      const eligible=evolution?.best_observed_candidate ? 'CANDIDATE' : (backtests ? 'RESEARCH' : 'WAITING');

      pulse.textContent='LIVE · DATA RECEIVED';
      pulse.className='slc-live';
      set('slcMt4', observed ? (latest.symbol || turtle?.state?.symbol || 'CONNECTED') + ' · ' + (latest.timeframe || turtle?.state?.timeframe || '—') : 'WAITING','ok');
      set('slcBot', bot.name || bot.id || latest.strategy || 'TURTLE');
      set('slcPos', account.position_count ?? turtle?.state?.position_count ?? '—');
      set('slcPnl', last.pnl == null ? '—' : '$'+fmt(last.pnl), Number(last.pnl)>=0?'ok':'bad');
      set('slcEvidence', evidenceCount+' snapshots · '+items.length+' trades','ok');
      set('slcEvolution', eligible, eligible==='CANDIDATE'?'ok':'warn');

      ['slcNodeMt4','slcNodeBridge','slcNodeSbt','slcNodeBitey'].forEach(id=>document.getElementById(id)?.classList.add('active'));
      if(backtests>0)document.getElementById('slcNodeEvo')?.classList.add('active');

      document.getElementById('slcTrade').innerHTML =
        '<b>Último cierre:</b> '+esc(last.ticket || '—')+' · '+esc(last.symbol || latest.symbol || '—')+' · '+esc(last.side || '—')+
        ' · '+esc(last.exit_reason || 'CLOSED')+' · P/L <b>$'+fmt(last.pnl)+'</b>' +
        '<br><b>Cuenta:</b> '+esc(mt4Mode)+' · capital operativo SBT <b>$'+fmt(account.operational_capital_usd ?? latest.metrics?.operational_capital_usd ?? 500)+'</b>';
      document.getElementById('slcDecision').innerHTML =
        '<b>SBT:</b> '+esc(evolution?.objective || 'maximize_monthly_profit_subject_to_risk_and_robustness')+
        '<br><b>Backtests:</b> '+backtests+' · <b>Next:</b> '+esc(evolution?.next_experiments?.items?.[0]?.reason || 'acumular evidencia')+
        '<br><b>Regla:</b> una transformación solo se promueve después de evidencia comparable + validación.';
    } catch (err) {
      pulse.textContent='RECONNECTING';
      pulse.className='slc-live warn';
      ['slcNodeMt4','slcNodeBridge','slcNodeSbt','slcNodeBitey','slcNodeEvo'].forEach(id=>document.getElementById(id)?.classList.remove('active'));
      set('slcMt4','API OFFLINE','bad');
    }
  }

  function init(){installStyle();ensure();refresh();setInterval(refresh,5000);}
  window.BiteySBTLiveCenter={init,refresh};
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init);else init();
})();