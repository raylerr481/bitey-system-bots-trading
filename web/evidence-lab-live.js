(() => {
  'use strict';

  const API = (window.SBT_API_URL || 'https://bitey-system-bots-trading-api.onrender.com').replace(/\/$/, '');
  const esc = v => String(v ?? '—').replace(/[&<>"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
  const text = (id, value) => { const e = document.getElementById(id); if (e) e.textContent = value ?? '—'; };
  const n = (v, d=2) => Number.isFinite(Number(v)) ? Number(v).toFixed(d) : '—';
  const ageSec = ts => { const t = Date.parse(ts || ''); return Number.isFinite(t) ? Math.max(0, (Date.now()-t)/1000) : Infinity; };

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
    const account = r.account || {};
    const cap = r.capital_correspondence || account.capital_correspondence || {};

    const signal = r.signal || metrics.signal || state.current || 'NONE';
    const positions = Number(
      account.position_count ??
      metrics.positions_open ??
      state.position_count ??
      r.position_count ??
      0
    );

    const operationalCapital = Number(
      cap.sbt_operational_capital_usd ??
      risk.operational_capital_usd ??
      500
    );

    const balance = Number(cap.mt4_balance_usd ?? account.balance);
    const equity = Number(cap.mt4_equity_usd ?? account.equity);
    const floating = Number.isFinite(equity) && Number.isFinite(balance) ? equity - balance : Number(cap.mt4_floating_pnl_usd);
    const mt4DdAbs = Number(cap.mt4_drawdown_abs_usd ?? account.drawdown_abs ?? account.absolute_drawdown);
    const mt4DdPct = Number(cap.mt4_drawdown_pct ?? account.drawdown_pct ?? account.relative_drawdown_pct);
    const sbtDdPct = Number(cap.sbt_operational_drawdown_pct ?? metrics.sbt_operational_drawdown_pct);

    // MT4 Evidence Lab sends these values in top-level capital/risk/bot objects.
    // Keep them live: never fall back to UI defaults when MT4 supplied a value.
    const mt4Params = {
      reference_capital_usd: Number(r.capital?.reference_usd),
      risk_pct: Number(r.capital?.risk_pct ?? risk.risk_pct),
      risk_budget_usd: Number(r.capital?.risk_budget_usd),
      max_daily_loss_pct: Number(risk.max_daily_loss_pct),
      max_spread_points: Number(risk.max_spread_points),
      max_trades_day: Number(risk.max_trades_day),
      max_open_trades: Number(risk.max_open_trades),
      magic: Number(r.bot?.magic),
      slippage_points: Number(r.slippage_points ?? risk.slippage_points),
      stop_atr: Number(r.stop_atr ?? r.strategy_params?.stop_atr),
      target_r: Number(r.target_r ?? r.strategy_params?.target_r),
      hard_risk_usd: Number(risk.hard_risk_usd)
    };

    return {
      ...r,
      account,
      risk,
      metrics: { ...metrics, ...state, ...counters },
      counters,
      market: r.market || {},
      turtle: r.turtle_controller || r.turtle || {},
      signal,
      direction: r.direction || (signal === 'BUY' || signal === 'SELL' ? signal : 'NONE'),
      previous_signal: r.previous_signal || state.previous || 'NONE',
      signal_change: r.signal_change || state.change || 'NONE',
      regime: r.regime || 'UNKNOWN',
      strategy: r.strategy || r.bot?.strategy || 'ENSEMBLE',
      timeframe: r.timeframe || r.strategy_timeframe || 'M15',
      chart_timeframe: r.chart_timeframe || 'H1',
      positions,
      operational_capital: operationalCapital,
      mt4_balance: balance,
      mt4_equity: equity,
      mt4_floating_pnl: floating,
      mt4_dd_abs: mt4DdAbs,
      mt4_dd_pct: mt4DdPct,
      sbt_dd_pct: sbtDdPct,
      capital_ratio_pct: Number(cap.sbt_capital_as_pct_of_mt4_balance),
      capital_multiple: Number(cap.mt4_balance_multiple_of_sbt_capital),
      mt4_params: mt4Params,
      htf_direction: r.htf_direction || r.htf || '—',
      buy_ev: Number(r.buy_ev), sell_ev: Number(r.sell_ev),
      buy_pf: Number(r.buy_pf), sell_pf: Number(r.sell_pf),
      wfo_positive: r.wfo_positive || '—',
      age: ageSec(r.timestamp)
    };
  }

  function signalBadge(signal) {
    const s = String(signal || 'NONE').toUpperCase();
    const cls = s === 'BUY' ? 'badge' : 'badge ' + (s === 'SELL' ? 'danger' : 'warn');
    return '<span class="' + cls + '">' + esc(s) + '</span>';
  }

  function ensureGlobalPanel() {
    let host = document.getElementById('mt4LiveContext');
    if (host) return host;
    host = document.createElement('section');
    host.id = 'mt4LiveContext';
    host.style.cssText = 'margin:0 0 12px;padding:12px 14px;background:#080f15;border:1px solid #263746;border-radius:10px;';
    host.innerHTML =
      '<div style="display:flex;justify-content:space-between;gap:10px;align-items:center;flex-wrap:wrap">' +
        '<div><span class="eyebrow">MT4 → SBT · LIVE TELEMETRY</span><strong id="mt4LiveTitle" style="display:block;margin-top:3px">Esperando MT4…</strong></div>' +
        '<div id="mt4LiveHeartbeat" class="badge">OFFLINE</div>' +
      '</div>' +
      '<div id="mt4LiveGrid" style="display:grid;grid-template-columns:repeat(8,minmax(90px,1fr));gap:7px;margin-top:10px"></div>' +
      '<div id="mt4CapitalGrid" style="display:grid;grid-template-columns:repeat(5,minmax(130px,1fr));gap:7px;margin-top:8px"></div>' +
      '<div id="mt4ParamsGrid" style="display:grid;grid-template-columns:repeat(4,minmax(130px,1fr));gap:7px;margin-top:8px"></div>' +
      '<div id="mt4LiveMeta" class="small" style="margin-top:8px"></div>';
    const main = document.querySelector('.main');
    const top = main?.querySelector('.top');
    if (top) top.insertAdjacentElement('afterend', host);
    return host;
  }

  function renderGlobal(r) {
    ensureGlobalPanel();
    if (!r) {
      text('mt4LiveTitle', 'Esperando el primer snapshot de MT4…');
      const hb = document.getElementById('mt4LiveHeartbeat');
      if (hb) { hb.textContent = 'OFFLINE'; hb.className = 'badge danger'; }
      return;
    }

    text('mt4LiveTitle', (r.bot?.name || 'Bitey SBT Evidence Lab v1.15') + ' · ' + r.symbol + ' · ' + r.timeframe);
    const hb = document.getElementById('mt4LiveHeartbeat');
    if (hb) {
      const fresh = r.age < 90;
      hb.textContent = fresh ? 'ONLINE · ' + n(r.age,0) + 's' : 'STALE · ' + n(r.age,0) + 's';
      hb.className = fresh ? 'badge' : 'badge warn';
    }

    const vals = [
      ['SIGNAL', r.signal], ['DIRECTION', r.direction], ['REGIME', r.regime], ['POSITIONS', r.positions],
      ['SBT CAPITAL', '$' + n(r.operational_capital)], ['RISK', n(r.risk.risk_pct,3) + '%'],
      ['MT4 DD', n(r.mt4_dd_pct,3) + '%'], ['TRADES', r.metrics.trades_today ?? '—'], ['HTF', r.htf_direction]
    ];
    const grid = document.getElementById('mt4LiveGrid');
    if (grid) grid.innerHTML = vals.map(([k,v]) =>
      '<div style="padding:7px 8px;background:#0b151d;border:1px solid #1b2a36;border-radius:7px"><span style="display:block;color:#6f8090;font-size:8px">' +
      k + '</span><b style="display:block;margin-top:3px">' + esc(v) + '</b></div>').join('');

    const capitalVals = [
      ['MT4 BALANCE', '$' + n(r.mt4_balance)],
      ['MT4 EQUITY', '$' + n(r.mt4_equity)],
      ['FLOATING P/L', '$' + n(r.mt4_floating_pnl)],
      ['SBT / MT4', n(r.capital_ratio_pct,2) + '%'],
      ['MT4 / SBT', n(r.capital_multiple,2) + '×']
    ];
    const cg = document.getElementById('mt4CapitalGrid');
    if (cg) cg.innerHTML = capitalVals.map(([k,v]) =>
      '<div style="padding:7px 8px;background:#0b151d;border:1px solid #1b2a36;border-radius:7px"><span style="display:block;color:#6f8090;font-size:8px">' +
      k + '</span><b style="display:block;margin-top:3px">' + esc(v) + '</b></div>').join('');

    const p = r.mt4_params || {};
    const paramVals = [
      ['REFERENCE', '$' + n(p.reference_capital_usd)],
      ['RISK %', n(p.risk_pct,3) + '%'],
      ['RISK BUDGET', '$' + n(p.risk_budget_usd)],
      ['MAX DAILY DD', n(p.max_daily_loss_pct,2) + '%'],
      ['MAX SPREAD', n(p.max_spread_points,1)],
      ['MAX TRADES/DAY', Number.isFinite(p.max_trades_day) ? p.max_trades_day : '—'],
      ['MAX OPEN', Number.isFinite(p.max_open_trades) ? p.max_open_trades : '—'],
      ['MAGIC', Number.isFinite(p.magic) ? p.magic : '—'], ['HARD RISK', '
    ];
    const pg = document.getElementById('mt4ParamsGrid');
    if (pg) pg.innerHTML = paramVals.map(([k,v]) =>
      '<div style="padding:7px 8px;background:#0b151d;border:1px solid #1b2a36;border-radius:7px"><span style="display:block;color:#6f8090;font-size:8px">' +
      k + '</span><b style="display:block;margin-top:3px">' + esc(v) + '</b></div>').join('');

    const accountMode = String(r.mode || r.account_mode || r.account?.mode || 'UNKNOWN').toUpperCase();
    const virtualMoney = accountMode !== 'REAL';
    text('mt4LiveMeta',
      'MT4 source · mode: ' + accountMode +
      ' · VIRTUAL_MONEY=' + (virtualMoney ? 'true' : 'false') +
      ' · LIVE=true · Last change: ' + r.signal_change);
  }
  function fillPageSpecific(r) {
    if (!r) return;
    const m = r.metrics || {}, a = r.account || {}, risk = r.risk || {}, c = r.counters || m;
    const tm = r.turtle?.state || r.turtle || {};

    text('terminalSymbol', r.symbol);
    text('terminalTimeframe', r.chart_timeframe || r.timeframe);
    text('terminalEnvironment', 'MT4 DEMO / TRADER WILL');
    text('terminalExecution', 'MT4 DEMO · BROKER ACTIVE');
    text('apiStatus', 'MT4 ' + (r.age < 90 ? 'CONNECTED' : 'STALE') + ' · ' + r.symbol + ' · ' + r.signal);

    text('eccMt4', r.age < 90 ? 'ONLINE' : 'STALE');
    text('eccMt4Meta', r.symbol + ' · ' + r.timeframe + ' · heartbeat ' + n(r.age,0) + 's');
    text('eccBots', '1');
    text('eccBotsMeta', r.bot?.name || 'Bitey SBT Evidence Lab v1.15');
    text('eccMarket', r.symbol + ' · ' + r.timeframe);
    text('eccChartTf', r.chart_timeframe || 'H1');
    text('eccMode', 'MT4 DEMO / TRADER WILL');
    text('eccBot', r.bot?.name || 'Bitey SBT Evidence Lab v1.15');
    text('eccSignal', (r.signal || 'NONE') + ' · ' + (r.regime || 'UNKNOWN'));
    text('eccNext', r.signal === 'BUY' || r.signal === 'SELL' ? 'Evaluar Risk Gate / ejecución MT4' : 'Esperando señal válida');
    text('eccNotice', 'MT4 snapshot recibido. MT4 conserva la autoridad de ejecución; SBT Risk Gate conserva el límite operativo.');
    text('dashboardEvidence', r.signal && r.signal !== 'NONE' ? 'LIVE SNAPSHOT' : 'WAITING MT4');

    text('observerSelectedBot', r.bot?.name || 'Bitey SBT Evidence Lab v1.15');
    text('observerSignal', r.signal);
    text('observerRegime', r.regime);
    text('observerDirection', r.direction);
    text('observerPositionCount', r.positions);
    text('observerRiskDD', n(r.sbt_dd_pct ?? m.daily_drawdown_pct,3) + '%');
    text('observerExplanation', 'Snapshot MT4 recibido. SBT usa $500 como capital operativo; el balance del broker solo se observa.');

    text('aiBotName', r.bot?.name || 'Bitey SBT Evidence Lab v1.15');
    text('aiBotConnection', r.age < 90 ? 'MT4 conectado' : 'MT4 stale');
    text('aiBotMarket', r.symbol + ' · ' + r.timeframe);
    text('aiBotMode', 'MT4 DEMO / TRADER WILL · reported mode ' + (r.mode || 'UNKNOWN'));
    text('aiEnvironment', 'MT4 DEMO / TRADER WILL');
    text('aiProductionStatus', 'DEMO · MT4 EXECUTION UNDER RISK GATE');
    text('aiBotParams',
      'Strategy=' + r.strategy + ' · TF=' + r.timeframe + ' · Chart=' + r.chart_timeframe +
      ' · Reference=
    const msg = document.getElementById('aiBotMessages');
    if (msg) msg.innerHTML =
      '• Señal: ' + signalBadge(r.signal) + '<br>• Dirección: ' + esc(r.direction) +
      '<br>• Régimen: ' + esc(r.regime) + '<br>• Posiciones MT4: ' + esc(r.positions) +
      '<br>• Capital SBT: $' + n(r.operational_capital);

    text('aiBotRecommendation', r.signal === 'BUY' || r.signal === 'SELL'
      ? 'Bitey debe evaluar la señal con Risk Gate antes de cualquier acción.'
      : 'Esperando una señal operable del Evidence Lab.');

    text('turtleConnection', r.age < 90 ? 'ONLINE' : 'STALE');
    text('turtleHeartbeat', new Date(r.timestamp).toLocaleTimeString());
    text('turtleExec', 'MT4 DEMO · BROKER ACTIVE · RISK GATE CONTROLLED');
    text('turtleStatus', 'Evidence Lab v1.02 conectado. Datos de mercado y cuenta vienen de MT4; el capital operativo de SBT permanece en $500.');
    text('turtleSymbol', r.symbol + ' · ' + (r.chart_timeframe || r.timeframe));
    text('turtleMode', 'Strategy ' + r.strategy + ' · TF ' + r.timeframe + ' · Chart ' + r.chart_timeframe);

    const market = r.market || {};
    const turtle = r.turtle || {};
    const bid = market.bid ?? market.Bid ?? market.price_bid;
    const ask = market.ask ?? market.Ask ?? market.price_ask;
    const atr = market.atr ?? market.ATR ?? m.atr ?? m.ATR;
    const rsi = market.rsi ?? market.RSI ?? m.rsi ?? m.RSI;
    const adx = market.adx ?? market.ADX ?? m.adx ?? m.ADX;

    text('turtleBid', n(bid,5));
    text('turtleAsk', n(ask,5));
    text('turtleAtr', n(atr,5));
    text('turtleRsi', n(rsi,2));
    text('turtleAdx', n(adx,2));
    text('turtleOpenTrades', String(r.positions));

    const campaign = r.positions > 0 ? (tm.next_action || 'MANAGE_POSITION') : (tm.next_action || 'WAIT');
    text('turtleCampaign', campaign);
    text('turtleCampaignMeta', tm.reason || (r.signal !== 'NONE' ? 'Señal MT4 recibida' : 'Sin señal activa'));
    text('turtleUnits', String(r.positions));
    text('turtleDirection', r.direction || 'FLAT');
    text('turtleSystem', r.bot?.name || 'Bitey SBT Evidence Lab v1.15');
    text('turtleDir', r.direction || 'FLAT');
    text('turtleLastEntry', tm.last_entry ?? turtle.last_entry ?? '—');
    text('turtleCampaignN', tm.campaign_n ?? turtle.campaign_n ?? '—');
    text('turtleSkipNext', tm.s1_skip_next ?? turtle.s1_skip_next ?? '—');
    text('turtleSkipLatched', tm.s1_skip_latched ?? turtle.s1_skip_latched ?? '—');

    text('turtleS1Signals', (Number(c.buy_signals || 0) + Number(c.sell_signals || 0)) + ' (B ' + Number(c.buy_signals || 0) + ' / S ' + Number(c.sell_signals || 0) + ')');
    text('turtleS2Signals', '—');
    text('turtleHistoryBlocked', Number(c.block_spread || 0) + Number(c.block_session || 0) + Number(c.block_daily_dd || 0) + Number(c.block_trade_limit || 0));
    text('turtleBalance', Number.isFinite(Number(r.mt4_balance)) ? '$' + n(r.mt4_balance) : '—');
    text('turtleEquity', Number.isFinite(Number(r.mt4_equity)) ? '$' + n(r.mt4_equity) : '—');
    text('turtleRegime', r.regime);
    text('turtleModePanel',
      'Entorno: MT4 DEMO / TRADER WILL · MT4 balance $' + n(r.mt4_balance) +
      ' · SBT capital operativo $' + n(r.operational_capital) +
      ' · SBT representa ' + n(r.capital_ratio_pct,2) + '% de la cuenta MT4');
    text('turtleProbability', '—');
    text('turtlePerformanceFlag', 'MT4 DD ' + n(r.mt4_dd_pct,3) + '% · SBT DD equivalente ' + n(r.sbt_dd_pct,3) + '%');
    text('turtleLiveReady', r.age < 90 ? 'READY · MT4 TELEMETRY' : 'STALE');
    text('turtleReadiness', 'Execution: MT4 DEMO · Risk Gate: $500 cap');
    text('validationEnvironment', 'MT4 DEMO / TRADER WILL');
    text('validationStatus', r.signal !== 'NONE' ? 'MT4 evidence received' : 'Waiting for MT4 evidence');

    const riskPanel = document.getElementById('riskGateMt4Evidence');
    if (riskPanel) riskPanel.innerHTML =
      '<strong>MT4 Evidence Lab</strong><br>' +
      'MT4 Balance $' + n(r.mt4_balance) + ' · Equity $' + n(r.mt4_equity) + ' · Floating P/L $' + n(r.mt4_floating_pnl) +
      '<br><strong>SBT Operational Capital $' + n(r.operational_capital) + '</strong> · Risk ' + n(risk.risk_pct,3) + '%' +
      ' · SBT/MT4 ' + n(r.capital_ratio_pct,2) + '% · Positions ' + r.positions +
      '<br>MT4 DD ' + n(r.mt4_dd_pct,3) + '% · SBT operational DD ' + n(r.sbt_dd_pct,3) + '%';
  }

  function ensureRiskPanel() {
    if (document.getElementById('riskGateMt4Evidence')) return;
    const risk = document.getElementById('risk');
    if (!risk) return;
    const p = document.createElement('div');
    p.id = 'riskGateMt4Evidence';
    p.className = 'notice';
    p.style.marginBottom = '12px';
    risk.insertBefore(p, risk.firstChild);
  }

  function renderHistory(items) {
    const body = document.getElementById('turtleHistoryBody');
    if (!body) return;
    if (!items.length) {
      body.innerHTML = '<tr><td colspan="10" class="muted">Sin snapshots recibidos.</td></tr>';
      return;
    }
    body.innerHTML = items.slice(0,20).map(x => {
      const r = normalize(x), m = r?.metrics || {};
      return '<tr><td>' + new Date(r.timestamp).toLocaleTimeString() + '</td><td>' + esc(r.symbol) +
        '</td><td>' + esc(r.regime) + '</td><td>' + esc(r.direction) + '</td><td>' + esc(r.positions) +
        '</td><td>—</td><td>—</td><td>—</td><td>$' + n(r.mt4_equity) + '</td><td>' +
        esc(m.trades_today ?? 0) + '</td></tr>';
    }).join('');
  }

  function renderTrades(items) {
    const bodies = document.querySelectorAll('#observerActivityBody');
    bodies.forEach(body => {
      if (!items.length) {
        body.innerHTML = '<tr><td colspan="7" class="muted">Sin operaciones cerradas recibidas desde MT4.</td></tr>';
        return;
      }
      body.innerHTML = items.slice(0,20).map(t =>
        '<tr><td>' + esc(t.close_time || t.open_time || '—') +
        '</td><td>' + esc(t.bot_id || t.source || 'MT4') +
        '</td><td>' + esc(t.exit_reason || 'CLOSED') +
        '</td><td>' + esc(t.symbol) + '</td><td>' + esc(t.side) +
        '</td><td>' + esc(t.lots ?? 1) + '</td><td>' + n(t.pnl,2) + '</td></tr>'
      ).join('');
    });
  }

  async function refresh() {
    try {
      const [latest, history, trades] = await Promise.all([
        get('/api/v1/mt4/bitey-latest'),
        get('/api/v1/mt4/bitey-history?limit=20'),
        get('/api/v1/mt4/trades?limit=20')
      ]);
      const r = normalize(latest);
      renderGlobal(r);
      ensureRiskPanel();
      fillPageSpecific(r);
      renderHistory(history?.items || []);
      renderTrades(trades?.items || []);
      window.dispatchEvent(new CustomEvent('sbt:mt4-live', {
        detail: { report:r, history:history?.items || [], trades:trades?.items || [] }
      }));
    } catch (e) {
      renderGlobal(null);
      const st = document.getElementById('apiStatus');
      if (st) st.textContent = 'SBT MT4 API unavailable';
    }
  }

  function boot() {
    ensureGlobalPanel();
    ensureRiskPanel();
    refresh();
    setInterval(refresh, 5000);
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot, {once:true});
  else boot();
})(); + n(p.hard_risk_usd)]
    ];
    const pg = document.getElementById('mt4ParamsGrid');
    if (pg) pg.innerHTML = paramVals.map(([k,v]) =>
      '<div style="padding:7px 8px;background:#0b151d;border:1px solid #1b2a36;border-radius:7px"><span style="display:block;color:#6f8090;font-size:8px">' +
      k + '</span><b style="display:block;margin-top:3px">' + esc(v) + '</b></div>').join('');

    const accountMode = String(r.mode || r.account_mode || r.account?.mode || 'UNKNOWN').toUpperCase();
    const virtualMoney = accountMode !== 'REAL';
    text('mt4LiveMeta',
      'MT4 source · mode: ' + accountMode +
      ' · VIRTUAL_MONEY=' + (virtualMoney ? 'true' : 'false') +
      ' · LIVE=true · Last change: ' + r.signal_change);
  }
  function fillPageSpecific(r) {
    if (!r) return;
    const m = r.metrics || {}, a = r.account || {}, risk = r.risk || {}, c = r.counters || m;
    const tm = r.turtle?.state || r.turtle || {};

    text('terminalSymbol', r.symbol);
    text('terminalTimeframe', r.chart_timeframe || r.timeframe);
    text('terminalEnvironment', 'MT4 DEMO / TRADER WILL');
    text('terminalExecution', 'MT4 DEMO · BROKER ACTIVE');
    text('apiStatus', 'MT4 ' + (r.age < 90 ? 'CONNECTED' : 'STALE') + ' · ' + r.symbol + ' · ' + r.signal);

    text('eccMt4', r.age < 90 ? 'ONLINE' : 'STALE');
    text('eccMt4Meta', r.symbol + ' · ' + r.timeframe + ' · heartbeat ' + n(r.age,0) + 's');
    text('eccBots', '1');
    text('eccBotsMeta', r.bot?.name || 'Bitey SBT Evidence Lab v1.15');
    text('eccMarket', r.symbol + ' · ' + r.timeframe);
    text('eccChartTf', r.chart_timeframe || 'H1');
    text('eccMode', 'MT4 DEMO / TRADER WILL');
    text('eccBot', r.bot?.name || 'Bitey SBT Evidence Lab v1.15');
    text('eccSignal', (r.signal || 'NONE') + ' · ' + (r.regime || 'UNKNOWN'));
    text('eccNext', r.signal === 'BUY' || r.signal === 'SELL' ? 'Evaluar Risk Gate / ejecución MT4' : 'Esperando señal válida');
    text('eccNotice', 'MT4 snapshot recibido. MT4 conserva la autoridad de ejecución; SBT Risk Gate conserva el límite operativo.');
    text('dashboardEvidence', r.signal && r.signal !== 'NONE' ? 'LIVE SNAPSHOT' : 'WAITING MT4');

    text('observerSelectedBot', r.bot?.name || 'Bitey SBT Evidence Lab v1.15');
    text('observerSignal', r.signal);
    text('observerRegime', r.regime);
    text('observerDirection', r.direction);
    text('observerPositionCount', r.positions);
    text('observerRiskDD', n(r.sbt_dd_pct ?? m.daily_drawdown_pct,3) + '%');
    text('observerExplanation', 'Snapshot MT4 recibido. SBT usa $500 como capital operativo; el balance del broker solo se observa.');

    text('aiBotName', r.bot?.name || 'Bitey SBT Evidence Lab v1.15');
    text('aiBotConnection', r.age < 90 ? 'MT4 conectado' : 'MT4 stale');
    text('aiBotMarket', r.symbol + ' · ' + r.timeframe);
    text('aiBotMode', 'MT4 DEMO / TRADER WILL · reported mode ' + (r.mode || 'UNKNOWN'));
    text('aiEnvironment', 'MT4 DEMO / TRADER WILL');
    text('aiProductionStatus', 'DEMO · MT4 EXECUTION UNDER RISK GATE');
    text('aiBotParams',
      'Strategy=' + r.strategy + ' · TF=' + r.timeframe + ' · Chart=' + r.chart_timeframe +
      ' · Reference=
    const msg = document.getElementById('aiBotMessages');
    if (msg) msg.innerHTML =
      '• Señal: ' + signalBadge(r.signal) + '<br>• Dirección: ' + esc(r.direction) +
      '<br>• Régimen: ' + esc(r.regime) + '<br>• Posiciones MT4: ' + esc(r.positions) +
      '<br>• Capital SBT: $' + n(r.operational_capital);

    text('aiBotRecommendation', r.signal === 'BUY' || r.signal === 'SELL'
      ? 'Bitey debe evaluar la señal con Risk Gate antes de cualquier acción.'
      : 'Esperando una señal operable del Evidence Lab.');

    text('turtleConnection', r.age < 90 ? 'ONLINE' : 'STALE');
    text('turtleHeartbeat', new Date(r.timestamp).toLocaleTimeString());
    text('turtleExec', 'MT4 DEMO · BROKER ACTIVE · RISK GATE CONTROLLED');
    text('turtleStatus', 'Evidence Lab v1.02 conectado. Datos de mercado y cuenta vienen de MT4; el capital operativo de SBT permanece en $500.');
    text('turtleSymbol', r.symbol + ' · ' + (r.chart_timeframe || r.timeframe));
    text('turtleMode', 'Strategy ' + r.strategy + ' · TF ' + r.timeframe + ' · Chart ' + r.chart_timeframe);

    const market = r.market || {};
    const turtle = r.turtle || {};
    const bid = market.bid ?? market.Bid ?? market.price_bid;
    const ask = market.ask ?? market.Ask ?? market.price_ask;
    const atr = market.atr ?? market.ATR ?? m.atr ?? m.ATR;
    const rsi = market.rsi ?? market.RSI ?? m.rsi ?? m.RSI;
    const adx = market.adx ?? market.ADX ?? m.adx ?? m.ADX;

    text('turtleBid', n(bid,5));
    text('turtleAsk', n(ask,5));
    text('turtleAtr', n(atr,5));
    text('turtleRsi', n(rsi,2));
    text('turtleAdx', n(adx,2));
    text('turtleOpenTrades', String(r.positions));

    const campaign = r.positions > 0 ? (tm.next_action || 'MANAGE_POSITION') : (tm.next_action || 'WAIT');
    text('turtleCampaign', campaign);
    text('turtleCampaignMeta', tm.reason || (r.signal !== 'NONE' ? 'Señal MT4 recibida' : 'Sin señal activa'));
    text('turtleUnits', String(r.positions));
    text('turtleDirection', r.direction || 'FLAT');
    text('turtleSystem', r.bot?.name || 'Bitey SBT Evidence Lab v1.15');
    text('turtleDir', r.direction || 'FLAT');
    text('turtleLastEntry', tm.last_entry ?? turtle.last_entry ?? '—');
    text('turtleCampaignN', tm.campaign_n ?? turtle.campaign_n ?? '—');
    text('turtleSkipNext', tm.s1_skip_next ?? turtle.s1_skip_next ?? '—');
    text('turtleSkipLatched', tm.s1_skip_latched ?? turtle.s1_skip_latched ?? '—');

    text('turtleS1Signals', (Number(c.buy_signals || 0) + Number(c.sell_signals || 0)) + ' (B ' + Number(c.buy_signals || 0) + ' / S ' + Number(c.sell_signals || 0) + ')');
    text('turtleS2Signals', '—');
    text('turtleHistoryBlocked', Number(c.block_spread || 0) + Number(c.block_session || 0) + Number(c.block_daily_dd || 0) + Number(c.block_trade_limit || 0));
    text('turtleBalance', Number.isFinite(Number(r.mt4_balance)) ? '$' + n(r.mt4_balance) : '—');
    text('turtleEquity', Number.isFinite(Number(r.mt4_equity)) ? '$' + n(r.mt4_equity) : '—');
    text('turtleRegime', r.regime);
    text('turtleModePanel',
      'Entorno: MT4 DEMO / TRADER WILL · MT4 balance $' + n(r.mt4_balance) +
      ' · SBT capital operativo $' + n(r.operational_capital) +
      ' · SBT representa ' + n(r.capital_ratio_pct,2) + '% de la cuenta MT4');
    text('turtleProbability', '—');
    text('turtlePerformanceFlag', 'MT4 DD ' + n(r.mt4_dd_pct,3) + '% · SBT DD equivalente ' + n(r.sbt_dd_pct,3) + '%');
    text('turtleLiveReady', r.age < 90 ? 'READY · MT4 TELEMETRY' : 'STALE');
    text('turtleReadiness', 'Execution: MT4 DEMO · Risk Gate: $500 cap');
    text('validationEnvironment', 'MT4 DEMO / TRADER WILL');
    text('validationStatus', r.signal !== 'NONE' ? 'MT4 evidence received' : 'Waiting for MT4 evidence');

    const riskPanel = document.getElementById('riskGateMt4Evidence');
    if (riskPanel) riskPanel.innerHTML =
      '<strong>MT4 Evidence Lab</strong><br>' +
      'MT4 Balance $' + n(r.mt4_balance) + ' · Equity $' + n(r.mt4_equity) + ' · Floating P/L $' + n(r.mt4_floating_pnl) +
      '<br><strong>SBT Operational Capital $' + n(r.operational_capital) + '</strong> · Risk ' + n(risk.risk_pct,3) + '%' +
      ' · SBT/MT4 ' + n(r.capital_ratio_pct,2) + '% · Positions ' + r.positions +
      '<br>MT4 DD ' + n(r.mt4_dd_pct,3) + '% · SBT operational DD ' + n(r.sbt_dd_pct,3) + '%';
  }

  function ensureRiskPanel() {
    if (document.getElementById('riskGateMt4Evidence')) return;
    const risk = document.getElementById('risk');
    if (!risk) return;
    const p = document.createElement('div');
    p.id = 'riskGateMt4Evidence';
    p.className = 'notice';
    p.style.marginBottom = '12px';
    risk.insertBefore(p, risk.firstChild);
  }

  function renderHistory(items) {
    const body = document.getElementById('turtleHistoryBody');
    if (!body) return;
    if (!items.length) {
      body.innerHTML = '<tr><td colspan="10" class="muted">Sin snapshots recibidos.</td></tr>';
      return;
    }
    body.innerHTML = items.slice(0,20).map(x => {
      const r = normalize(x), m = r?.metrics || {};
      return '<tr><td>' + new Date(r.timestamp).toLocaleTimeString() + '</td><td>' + esc(r.symbol) +
        '</td><td>' + esc(r.regime) + '</td><td>' + esc(r.direction) + '</td><td>' + esc(r.positions) +
        '</td><td>—</td><td>—</td><td>—</td><td>$' + n(r.mt4_equity) + '</td><td>' +
        esc(m.trades_today ?? 0) + '</td></tr>';
    }).join('');
  }

  function renderTrades(items) {
    const bodies = document.querySelectorAll('#observerActivityBody');
    bodies.forEach(body => {
      if (!items.length) {
        body.innerHTML = '<tr><td colspan="7" class="muted">Sin operaciones cerradas recibidas desde MT4.</td></tr>';
        return;
      }
      body.innerHTML = items.slice(0,20).map(t =>
        '<tr><td>' + esc(t.close_time || t.open_time || '—') +
        '</td><td>' + esc(t.bot_id || t.source || 'MT4') +
        '</td><td>' + esc(t.exit_reason || 'CLOSED') +
        '</td><td>' + esc(t.symbol) + '</td><td>' + esc(t.side) +
        '</td><td>' + esc(t.lots ?? 1) + '</td><td>' + n(t.pnl,2) + '</td></tr>'
      ).join('');
    });
  }

  async function refresh() {
    try {
      const [latest, history, trades] = await Promise.all([
        get('/api/v1/mt4/bitey-latest'),
        get('/api/v1/mt4/bitey-history?limit=20'),
        get('/api/v1/mt4/trades?limit=20')
      ]);
      const r = normalize(latest);
      renderGlobal(r);
      ensureRiskPanel();
      fillPageSpecific(r);
      renderHistory(history?.items || []);
      renderTrades(trades?.items || []);
      window.dispatchEvent(new CustomEvent('sbt:mt4-live', {
        detail: { report:r, history:history?.items || [], trades:trades?.items || [] }
      }));
    } catch (e) {
      renderGlobal(null);
      const st = document.getElementById('apiStatus');
      if (st) st.textContent = 'SBT MT4 API unavailable';
    }
  }

  function boot() {
    ensureGlobalPanel();
    ensureRiskPanel();
    refresh();
    setInterval(refresh, 5000);
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot, {once:true});
  else boot();
})();