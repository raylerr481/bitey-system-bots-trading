(() => {
  function patchWebSocket() {
    if (window.__biteySbtTimeframeWsPatched) return;
    const NativeWebSocket = window.WebSocket;
    if (!NativeWebSocket) return;
    const PatchedWebSocket = function(url, protocols) {
      try {
        const text = String(url);
        if (text.includes('/api/v1/market/stream/')) {
          const trader = window.BiteyWebTrader;
          const timeframe = String(trader?.state?.timeframe || 'M5').toUpperCase();
          const separator = text.includes('?') ? '&' : '?';
          url = `${text}${separator}timeframe=${encodeURIComponent(timeframe)}`;
        }
      } catch (_) {}
      return protocols === undefined ? new NativeWebSocket(url) : new NativeWebSocket(url, protocols);
    };
    PatchedWebSocket.prototype = NativeWebSocket.prototype;
    Object.setPrototypeOf(PatchedWebSocket, NativeWebSocket);
    window.WebSocket = PatchedWebSocket;
    window.__biteySbtTimeframeWsPatched = true;
  }

  function install() {
    patchWebSocket();
    const page = document.getElementById('bot-lab-page');
    const toolbar = page?.querySelector('.mt-toolbar');
    if (!page || !toolbar) return false;
    if (toolbar.querySelector('[data-tf="M1"]')) return true;

    const button = document.createElement('button');
    button.type = 'button';
    button.dataset.tf = 'M1';
    button.textContent = '1m';
    button.title = '1 minute timeframe';
    button.addEventListener('click', () => {
      const trader = window.BiteyWebTrader;
      if (trader?.state) {
        trader.state.timeframe = 'M1';
        trader.state.viewEnd = null;
        page.querySelectorAll('.mt-toolbar [data-tf]').forEach(b => b.classList.toggle('active', b === button));
        const tf = document.getElementById('mtTf');
        const overlay = document.getElementById('mtOverlay');
        const pair = trader.state.symbol || 'EURUSD';
        if (tf) tf.textContent = 'M1 · BiQuote';
        if (overlay) overlay.textContent = `Bitey SBT · ${pair} · M1`;
        if (typeof trader.resetView === 'function') trader.resetView();
        if (typeof trader.drawChart === 'function') trader.drawChart();
        window.dispatchEvent(new CustomEvent('bitey:sbt-timeframe',{detail:{timeframe:'M1'}}));
        const refresh = document.getElementById('mtRefresh');
        if (refresh) refresh.click();
        return;
      }
      const fallback = toolbar.querySelector('[data-tf="M5"]') || toolbar.querySelector('[data-tf]');
      if (fallback) {
        const original = fallback.dataset.tf;
        fallback.dataset.tf = 'M1';
        fallback.click();
        fallback.dataset.tf = original;
      }
    });

    const first = toolbar.querySelector('[data-tf]');
    if (first) first.insertAdjacentElement('beforebegin', button);
    else toolbar.insertBefore(button, toolbar.firstChild);
    return true;
  }

  function boot() {
    if (install()) return;
    setTimeout(boot, 150);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();
})();
