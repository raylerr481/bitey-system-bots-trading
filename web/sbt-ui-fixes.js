(() => {
  const TIMEFRAMES = [
    ['M1', '1m'], ['M5', '5m'], ['M15', '15m'], ['M30', '30m'],
    ['H1', '1h'], ['H4', '4h'], ['D1', '1D'], ['W1', '1W']
  ];

  function installTimeframes() {
    const page = document.getElementById('bot-lab-page');
    const toolbar = page?.querySelector('.mt-toolbar');
    if (!page || !toolbar) return false;

    const existing = new Map(Array.from(toolbar.querySelectorAll('[data-tf]')).map(b => [b.dataset.tf, b]));
    const anchor = toolbar.querySelector('[data-tf]');
    if (!anchor) return false;

    TIMEFRAMES.forEach(([tf, label]) => {
      let button = existing.get(tf);
      if (!button) {
        button = document.createElement('button');
        button.type = 'button';
        button.dataset.tf = tf;
        button.textContent = label;
        button.title = `${label} timeframe`;
        anchor.parentElement.insertBefore(button, anchor);
      }
      button.addEventListener('click', () => selectTimeframe(tf, button), { once: true });
    });
    return true;
  }

  function selectTimeframe(tf, button) {
    const trader = window.BiteyWebTrader;
    const page = document.getElementById('bot-lab-page');
    if (!page) return;
    page.querySelectorAll('.mt-toolbar [data-tf]').forEach(b => b.classList.toggle('active', b.dataset.tf === tf));
    if (trader?.state) {
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
  }

  function boot() {
    if (installTimeframes()) return;
    setTimeout(boot, 150);
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();
})();
