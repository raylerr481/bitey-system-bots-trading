(() => {
  function install() {
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
