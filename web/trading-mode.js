(() => {
  const STORAGE_KEY = 'bitey-sbt-trading-mode-v1';
  const state = { mode: 'DEMO', realIntent: false, confirmed: false };

  function load() {
    try {
      const saved = JSON.parse(localStorage.getItem(STORAGE_KEY) || '{}');
      if (['DEMO', 'PAPER', 'REAL'].includes(saved.mode)) state.mode = saved.mode;
      state.realIntent = saved.realIntent === true;
      state.confirmed = saved.confirmed === true;
    } catch (_) {}
  }

  function save() {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
    window.dispatchEvent(new CustomEvent('bitey:sbt-trading-mode', { detail: { ...state } }));
  }

  function style() {
    if (document.getElementById('sbt-trading-mode-style')) return;
    const s = document.createElement('style');
    s.id = 'sbt-trading-mode-style';
    s.textContent = `
      #sbt-trading-mode{margin-top:15px}
      #sbt-trading-mode .tm-grid{display:grid;grid-template-columns:repeat(3,1fr);gap:8px;margin-top:10px}
      #sbt-trading-mode .tm-mode{padding:12px;border:1px solid var(--line,#242a32);border-radius:9px;background:#090e14;color:#cbd7e3;cursor:pointer;text-align:left}
      #sbt-trading-mode .tm-mode.active{border-color:var(--accent,#19c77a);background:#0c1b15;color:#fff}
      #sbt-trading-mode .tm-mode strong{display:block;font-size:12px}.tm-mode small{display:block;margin-top:5px;color:#718093;line-height:1.35}
      #sbt-trading-mode .tm-real{margin-top:10px;padding:12px;border:1px solid #4b4021;border-radius:9px;background:#15140d;color:#d8c58b;font-size:11px;line-height:1.5}
      #sbt-trading-mode .tm-actions{display:flex;gap:8px;flex-wrap:wrap;margin-top:10px}
      #sbt-trading-mode .tm-status{margin-top:10px;font:10px ui-monospace,SFMono-Regular,Consolas,monospace;color:#9aa7b5}
      @media(max-width:700px){#sbt-trading-mode .tm-grid{grid-template-columns:1fr}}
    `;
    document.head.appendChild(s);
  }

  function render() {
    const page = document.getElementById('bot-lab-page');
    if (!page) return;
    let host = document.getElementById('sbt-trading-mode');
    if (!host) {
      host = document.createElement('div');
      host.id = 'sbt-trading-mode';
      const controls = page.querySelector('.lab-controls');
      if (controls) controls.parentElement.appendChild(host);
    }
    if (!host) return;
    const realReady = false;
    host.innerHTML = `
      <div class="card">
        <h3>Trading Mode · control de capital</h3>
        <p style="color:#718093;font-size:11px;margin:6px 0 0">El modo real existe como una ruta explícita, pero la ejecución permanece bloqueada hasta que todas las capas de seguridad estén habilitadas.</p>
        <div class="tm-grid">
          <button class="tm-mode ${state.mode === 'DEMO' ? 'active' : ''}" data-mode="DEMO"><strong>DEMO</strong><small>Dinero virtual · MT5 Demo · sin órdenes reales</small></button>
          <button class="tm-mode ${state.mode === 'PAPER' ? 'active' : ''}" data-mode="PAPER"><strong>PAPER</strong><small>Mercado real · órdenes simuladas · sin broker execution</small></button>
          <button class="tm-mode ${state.mode === 'REAL' ? 'active' : ''}" data-mode="REAL"><strong>REAL</strong><small>Capital real · requiere activación explícita y Risk Gate</small></button>
        </div>
        <div class="tm-real">
          <strong>⚠ REAL MONEY CONTROL</strong><br>
          Activar REAL no concede permisos por sí solo. Requiere cuenta de broker, límites de riesgo, confirmación explícita y un adaptador de ejecución autorizado. En esta versión la ejecución real está bloqueada: <b>${realReady ? 'READY' : 'LOCKED'}</b>.
        </div>
        <div class="tm-actions">
          <button class="btn" id="sbtRealPrepare">Preparar cuenta REAL</button>
          <button class="btn" id="sbtRealDisable">Bloquear REAL</button>
        </div>
        <div class="tm-status" id="sbtTradingModeStatus"></div>
      </div>`;

    host.querySelectorAll('[data-mode]').forEach(btn => btn.addEventListener('click', () => {
      const mode = btn.dataset.mode;
      if (mode === 'REAL') {
        const confirmed = window.confirm('REAL MONEY: quieres preparar el modo REAL? Esto NO ejecutará ninguna orden y seguirá bloqueado.');
        if (!confirmed) return;
        state.realIntent = true;
        state.confirmed = true;
      } else {
        state.realIntent = false;
        state.confirmed = false;
      }
      state.mode = mode;
      save();
      render();
    }));

    host.querySelector('#sbtRealPrepare')?.addEventListener('click', () => {
      state.mode = 'REAL';
      state.realIntent = true;
      state.confirmed = false;
      save();
      render();
      const status = document.getElementById('sbtTradingModeStatus');
      if (status) status.textContent = 'REAL preparado como intención del usuario · ejecución bloqueada · broker_orders=0';
    });

    host.querySelector('#sbtRealDisable')?.addEventListener('click', () => {
      state.mode = 'DEMO';
      state.realIntent = false;
      state.confirmed = false;
      save();
      render();
    });

    const status = host.querySelector('#sbtTradingModeStatus');
    if (status) status.textContent = `MODE=${state.mode} · REAL_INTENT=${state.realIntent} · EXECUTION_LOCKED=true`;
  }

  function init() {
    load();
    style();
    render();
  }

  window.BiteySBTTradingMode = { init, getState: () => ({ ...state }) };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init); else init();

  // Live candle bridge: applies the actual MT5 Bid stream to the currently forming OHLC candle.
  // It never creates prices; it only aggregates an already received MT5 quote.
  function timeframeSeconds(tf) {
    return ({ M1: 60, M5: 300, M15: 900, M30: 1800, H1: 3600, H4: 14400, D1: 86400 })[tf] || 300;
  }

  function applyLiveQuote() {
    const market = window.BiteySBTMarketState;
    if (!market || !Array.isArray(market.candles) || !market.candles.length || !market.quote) return;
    const bid = Number(market.quote.bid);
    const rawTime = Number(market.quote.timestamp);
    if (!Number.isFinite(bid) || !Number.isFinite(rawTime)) return;
    const timestamp = rawTime > 1e12 ? rawTime / 1000 : rawTime;
    const interval = timeframeSeconds(market.timeframe);
    const bucket = Math.floor(timestamp / interval) * interval;
    const last = market.candles[market.candles.length - 1];
    if (!last || !Number.isFinite(Number(last.time))) return;
    const lastBucket = Math.floor(Number(last.time) / interval) * interval;

    if (bucket === lastBucket) {
      last.high = Math.max(Number(last.high), bid);
      last.low = Math.min(Number(last.low), bid);
      last.close = bid;
      last.volume = Number(last.volume || 0) + 1;
    } else if (bucket > lastBucket && bucket - lastBucket <= interval * 2) {
      // A new candle is created only from the received MT5 Bid tick.
      market.candles.push({ time: bucket, open: bid, high: bid, low: bid, close: bid, volume: 1 });
      if (market.candles.length > 500) market.candles.shift();
    } else {
      return;
    }

    window.dispatchEvent(new Event('resize'));
    window.dispatchEvent(new CustomEvent('bitey:sbt-live-candle', {
      detail: { symbol: market.symbol, timeframe: market.timeframe, timestamp, bid }
    }));
  }

  // Wait for Web Trader initialization, then keep the forming candle synchronized with MT5 quotes.
  const liveTimer = setInterval(applyLiveQuote, 250);
  window.addEventListener('beforeunload', () => clearInterval(liveTimer));
})();
