(() => {
  // Market-state contract monitor. Keeps the browser state explicit and
  // provider-neutral without enabling execution.
  const api = (window.SBT_API_URL || 'https://bitey-system-bots-trading-api.onrender.com').replace(/\/$/, '');
  const normalizeSource = (value) => {
    const source = String(value || '').trim().toLowerCase();
    return source || 'none';
  };
  const publish = () => {
    const state = window.BiteySBTMarketState;
    if (!state) return;
    state.provider = normalizeSource(state.provider || state.source);
    state.source = state.provider;
    state.execution_enabled = false;
    state.live = false;
    state.real_money = false;
    window.dispatchEvent(new CustomEvent('bitesbt:market-state', {
      detail: {
        symbol: state.symbol,
        timeframe: state.timeframe,
        source: state.source,
        provider: state.provider,
        state: state.feedState,
        error: state.error || null,
        candle_count: Array.isArray(state.candles) ? state.candles.length : 0,
        execution_enabled: false,
        live: false,
        real_money: false
      }
    }));
  };
  const sync = () => {
    const state = window.BiteySBTMarketState;
    if (!state) return;
    if (!state.provider && !state.source) state.provider = 'none';
    state.source = normalizeSource(state.source || state.provider);
    state.provider = state.source;
    state.execution_enabled = false;
    state.live = false;
    state.real_money = false;
    if (state.feedState === 'OFFLINE') {
      state.error = state.error || 'market provider unavailable';
      state.source = 'none';
      state.provider = 'none';
    }
    publish();
  };
  const observer = new MutationObserver(sync);
  const start = () => {
    sync();
    observer.observe(document.documentElement, { childList: true, subtree: true });
    setInterval(sync, 1000);
  };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start, { once: true });
  else start();
})();
