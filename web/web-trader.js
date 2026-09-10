(() => {
  const API = (window.SBT_API_URL || 'https://bitey-system-bots-trading-api.onrender.com').replace(/\/$/, '');
  const state = { symbol: 'EURUSD', timeframe: 'M5', candles: [], quote: null, analysis: null, timer: null, ws: null, feedState: 'OFFLINE', firstTickReceived: false };

  const el = (id) => document.getElementById(id);
  const setText = (id, value) => { const node = el(id); if (node) node.textContent = value; };
  const num = (v, digits = 5) => Number.isFinite(Number(v)) ? Number(v).toFixed(digits) : '—';

  function normalize(c) {
    const time = c.time ?? c.timestamp ?? c.datetime ?? c.t;
    return {
      time: Number(time) > 1e12 ? Number(time) / 1000 : Number(time),
      open: Number(c.open ?? c.o), high: Number(c.high ?? c.h), low: Number(c.low ?? c.l),
      close: Number(c.close ?? c.c), volume: Number(c.volume ?? c.tick_volume ?? c.v ?? 0)
    };
  }

  function validCandles(candles) {
    return candles.map(normalize).filter(c =>
      Number.isFinite(c.time) && [c.open, c.high, c.low, c.close].every(Number.isFinite)
    ).sort((a, b) => a.time - b.time);
  }

  function upsertCandle(candle) {
    const normalized = normalize(candle);
    if (!Number.isFinite(normalized.time)) return;
    const index = state.candles.findIndex(c => c.time === normalized.time);
    if (index >= 0) state.candles[index] = normalized;
    else state.candles.push(normalized);
    state.candles.sort((a, b) => a.time - b.time);
    if (state.candles.length > 500) state.candles = state.candles.slice(-500);
    updateIndicators(); drawChart();
  }

  function ema(values, period) {
    if (values.length < period) return null;
    let value = values.slice(0, period).reduce((a, b) => a + b, 0) / period;
    const alpha = 2 / (period + 1);
    for (let i = period; i < values.length; i++) value = alpha * values[i] + (1 - alpha) * value;
    return value;
  }

  function rsi(values, period = 14) {
    if (values.length <= period) return null;
    let gain = 0, loss = 0;
    for (let i = 1; i <= period; i++) { const d = values[i] - values[i - 1]; gain += Math.max(d, 0); loss += Math.max(-d, 0); }
    let avgGain = gain / period, avgLoss = loss / period;
    for (let i = period + 1; i < values.length; i++) { const d = values[i] - values[i - 1]; avgGain = (avgGain * (period - 1) + Math.max(d, 0)) / period; avgLoss = (avgLoss * (period - 1) + Math.max(-d, 0)) / period; }
    if (avgLoss === 0) return 100;
    return 100 - (100 / (1 + avgGain / avgLoss));
  }

  function atr(candles, period = 14) {
    if (candles.length <= period) return null;
    const tr = candles.slice(1).map((c, i) => Math.max(c.high - c.low, Math.abs(c.high - candles[i].close), Math.abs(c.low - candles[i].close)));
    return tr.slice(-period).reduce((a, b) => a + b, 0) / period;
  }

  function indicators(candles) {
    const closes = candles.map(c => c.close);
    const ema9 = ema(closes, 9), ema21 = ema(closes, 21), rsi14 = rsi(closes), atr14 = atr(candles);
    return { ema9, ema21, rsi14, atr14, trend: ema9 == null || ema21 == null ? '—' : ema9 > ema21 ? 'ALCISTA' : ema9 < ema21 ? 'BAJISTA' : 'LATERAL' };
  }

  function resizeCanvas(canvas) {
    const rect = canvas.getBoundingClientRect();
    const dpr = window.devicePixelRatio || 1;
    canvas.width = Math.max(1, Math.floor(rect.width * dpr));
    canvas.height = Math.max(1, Math.floor(rect.height * dpr));
    return { w: rect.width, h: rect.height, dpr };
  }

  function drawChart() {
    const canvas = el('mtChart'); if (!canvas || !state.candles.length) return;
    const { w, h, dpr } = resizeCanvas(canvas), ctx = canvas.getContext('2d');
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0); ctx.clearRect(0, 0, w, h);
    const candles = state.candles.slice(-Math.min(120, state.candles.length));
    const left = 58, right = 70, top = 28, bottom = 30;
    const max = Math.max(...candles.map(c => c.high)), min = Math.min(...candles.map(c => c.low));
    const range = Math.max(max - min, 1e-9), pad = range * 0.06, hi = max + pad, lo = min - pad;
    const y = value => top + ((hi - value) / (hi - lo)) * (h - top - bottom);
    const step = (w - left - right) / candles.length, body = Math.max(2, step * 0.62);

    ctx.font = '10px system-ui'; ctx.textAlign = 'right';
    for (let i = 0; i <= 6; i++) {
      const yy = top + i * (h - top - bottom) / 6, price = hi - i * (hi - lo) / 6;
      ctx.strokeStyle = '#18222d'; ctx.beginPath(); ctx.moveTo(left, yy); ctx.lineTo(w - right, yy); ctx.stroke();
      ctx.fillStyle = '#7d8997'; ctx.fillText(price.toFixed(5), w - 6, yy + 3);
    }

    candles.forEach((c, i) => {
      const x = left + i * step + step / 2, up = c.close >= c.open;
      ctx.strokeStyle = up ? '#52e6a2' : '#ff7272'; ctx.fillStyle = ctx.strokeStyle;
      ctx.beginPath(); ctx.moveTo(x, y(c.high)); ctx.lineTo(x, y(c.low)); ctx.stroke();
      const a = y(Math.max(c.open, c.close)), b = y(Math.min(c.open, c.close));
      ctx.fillRect(x - body / 2, a, body, Math.max(2, b - a));
    });

    const closes = candles.map(c => c.close);
    const drawEma = (period, color) => {
      if (closes.length < period) return;
      let value = closes.slice(0, period).reduce((a, b) => a + b, 0) / period;
      const alpha = 2 / (period + 1), series = new Array(closes.length).fill(null); series[period - 1] = value;
      for (let i = period; i < closes.length; i++) { value = alpha * closes[i] + (1 - alpha) * value; series[i] = value; }
      ctx.strokeStyle = color; ctx.lineWidth = 1.5; ctx.beginPath(); let started = false;
      series.forEach((v, i) => { if (v == null) return; const x = left + i * step + step / 2; if (!started) { ctx.moveTo(x, y(v)); started = true; } else ctx.lineTo(x, y(v)); }); ctx.stroke();
    };
    drawEma(9, '#78a7ff'); drawEma(21, '#f2c76d');

    if (state.quote && Number.isFinite(Number(state.quote.bid))) {
      const live = Number(state.quote.bid), yy = y(live);
      if (yy >= top && yy <= h - bottom) { ctx.strokeStyle = '#ffffff'; ctx.setLineDash([4, 4]); ctx.beginPath(); ctx.moveTo(left, yy); ctx.lineTo(w - right, yy); ctx.stroke(); ctx.setLineDash([]); ctx.fillStyle = '#ffffff'; ctx.textAlign = 'left'; ctx.fillText('BID ' + live.toFixed(5), left + 4, yy - 5); }
    }

    ctx.fillStyle = '#edf3f8'; ctx.textAlign = 'left'; ctx.font = 'bold 11px system-ui'; ctx.fillText(`${state.symbol} · ${state.timeframe} · BiQuote`, left, 14);
    ctx.font = '10px system-ui'; ctx.fillStyle = '#7d8997'; ctx.fillText(`OHLC + live ticks · ${candles.length} candles`, left + 150, 14);
  }

  function setFeedState(feedState, detail = '') {
    state.feedState = feedState;
    const labels = { HISTORICAL: '● HISTORICAL DATA', CONNECTING: '● CONNECTING LIVE FEED', LIVE: '● LIVE DATA', OFFLINE: '● FEED OFFLINE' };
    setText('mtFeedStatus', `${labels[feedState] || '● FEED OFFLINE'} · ${state.symbol} · ${state.timeframe}${detail ? ` · ${detail}` : ''}`);
  }

  async function loadCandles(runAnalysis = true) {
    setFeedState('CONNECTING');
    try {
      const response = await fetch(`${API}/api/v1/market/candles/${encodeURIComponent(state.symbol)}?timeframe=${encodeURIComponent(state.timeframe)}&limit=200`, { cache: 'no-store' });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const payload = await response.json(), candles = validCandles(payload.candles || []);
      if (candles.length < 20) throw new Error('insufficient candle data');
      state.candles = candles;
      const empty = el('mtChartEmpty'); if (empty) empty.style.display = 'none';
      updateIndicators(); drawChart();
      if (runAnalysis) await analyzeSameSnapshot();
      if (!state.firstTickReceived) setFeedState('HISTORICAL');
    } catch (error) {
      state.candles = []; state.analysis = null; drawChart();
      const empty = el('mtChartEmpty'); if (empty) { empty.style.display = 'grid'; empty.textContent = 'MARKET FEED UNAVAILABLE · no invented market data'; }
      if (!state.firstTickReceived) setFeedState('OFFLINE', error.message);
      setText('mtChange', error.message);
    }
  }

  async function analyzeSameSnapshot() {
    if (!state.candles.length) return;
    try {
      const response = await fetch(`${API}/api/v1/sbt/market-intelligence/analyze`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ symbol: state.symbol, timeframe: state.timeframe, candles: state.candles, capital: 10000, language: 'es', event: 'market_structure', evidence: [{ source: 'biquote', contract: 'sbt-candles-v1', snapshot_candles: state.candles.length }] }) });
      if (!response.ok) throw new Error(`analysis HTTP ${response.status}`);
      state.analysis = await response.json();
      updateIndicators();
    } catch (_) { /* Market chart remains usable when intelligence is temporarily unavailable. */ }
  }

  function updateIndicators() {
    const i = indicators(state.candles); setText('mtEma9', num(i.ema9)); setText('mtEma21', num(i.ema21)); setText('mtRsi', i.rsi14 == null ? '—' : i.rsi14.toFixed(1)); setText('mtAtr', num(i.atr14, 6)); setText('mtTrend', i.trend);
    const quote = state.quote; if (quote) { setText('mtBid', num(quote.bid)); setText('mtAsk', num(quote.ask)); setText('mtPrice', num(quote.last ?? quote.mid ?? quote.bid)); }
  }

  function connectQuoteStream() {
    if (state.ws) { try { state.ws.close(); } catch (_) {} }
    state.firstTickReceived = false; state.quote = null; setFeedState('CONNECTING');
    const url = API.replace(/^http/, 'ws') + `/api/v1/market/stream/${encodeURIComponent(state.symbol)}`;
    try {
      const ws = new WebSocket(url); state.ws = ws;
      ws.onmessage = event => {
        try {
          const data = JSON.parse(event.data);
          if (Array.isArray(data.historical_candles)) {
            const historical = validCandles(data.historical_candles);
            if (historical.length) { state.candles = historical; updateIndicators(); drawChart(); }
          }
          if (data.state === 'OFFLINE') { setFeedState('OFFLINE', data.error || 'provider unavailable'); return; }
          if (data.state !== 'LIVE' || !data.mid && !data.bid && !data.ask) return;
          state.firstTickReceived = true;
          state.quote = data;
          setFeedState('LIVE');
          if (data.candle) upsertCandle(data.candle); else { updateIndicators(); drawChart(); }
          const price = Number(data.mid ?? data.bid); setText('mtChange', Number.isFinite(price) ? `Bid ${num(data.bid)} · Ask ${num(data.ask)} · spread ${num(data.spread, 6)}` : 'Live quote connected');
        } catch (_) {}
      };
      ws.onclose = () => { if (state.ws === ws) { if (!state.firstTickReceived) setFeedState('OFFLINE', 'stream closed'); setTimeout(() => connectQuoteStream(), 3000); } };
      ws.onerror = () => { if (!state.firstTickReceived) setFeedState('OFFLINE', 'WebSocket error'); };
    } catch (_) { setFeedState('OFFLINE', 'WebSocket unavailable'); }
  }

  function setup() {
    if (!el('bot-lab-page') || el('bot-lab-page').dataset.webTraderReady) return;
    el('bot-lab-page').dataset.webTraderReady = '1';
    document.querySelectorAll('#bot-lab-page [data-tf]').forEach(button => button.addEventListener('click', () => { state.timeframe = button.dataset.tf; document.querySelectorAll('#bot-lab-page [data-tf]').forEach(b => b.classList.toggle('active', b === button)); connectQuoteStream(); loadCandles(true); }));
    const refresh = el('mtRefresh'); if (refresh) refresh.addEventListener('click', () => loadCandles(true));
    const symbols = ['EURUSD', 'GBPUSD', 'USDJPY', 'XAUUSD', 'BTCUSD'];
    const watch = el('mtWatchBody');
    if (watch) watch.innerHTML = symbols.map(symbol => `<tr data-symbol="${symbol}" class="${symbol === state.symbol ? 'selected' : ''}"><td><span class="mt-symbol">${symbol}</span><small>BiQuote</small></td><td>—</td></tr>`).join('');
    if (watch) watch.querySelectorAll('[data-symbol]').forEach(row => row.addEventListener('click', () => { state.symbol = row.dataset.symbol; watch.querySelectorAll('tr').forEach(r => r.classList.toggle('selected', r === row)); setText('mtPair', state.symbol); setText('mtOverlay', `Bitey SBT · ${state.symbol} · ${state.timeframe}`); state.quote = null; connectQuoteStream(); loadCandles(true); }));
    setText('mtPair', state.symbol); setText('mtTf', `${state.timeframe} · BiQuote`); setText('mtOverlay', `Bitey SBT · ${state.symbol} · ${state.timeframe}`);
    loadCandles(true); connectQuoteStream();
    clearInterval(state.timer); state.timer = setInterval(() => loadCandles(true), 10000);
    window.addEventListener('resize', drawChart);
    window.BiteySBTMarketState = state;
  }

  window.BiteyWebTrader = { init: setup, state };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', () => setTimeout(setup, 0)); else setTimeout(setup, 0);
})();
