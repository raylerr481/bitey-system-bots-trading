export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const BUILD = 'f6-canonical-terminal';

    if (url.pathname === '/health') {
      return new Response(JSON.stringify({
        service: 'bitey-system-bots-trading',
        status: 'ok',
        mode: 'research-demo',
        live: false,
        real_money: false,
        broker_orders: 0,
        web_build: BUILD
      }), { headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store, no-cache, must-revalidate, max-age=0', 'x-sbt-build': BUILD } });
    }

    const response = await env.ASSETS.fetch(request);
    const contentType = response.headers.get('content-type') || '';
    if (!contentType.includes('text/html')) return response;

    return new HTMLRewriter()
      .on('body', {
        element(element) {
          element.append(`<script>
(() => {
  const closeMobileMenu = () => { const side = document.getElementById('side'); if (side) side.classList.remove('open'); };
  const getMarketRow = () => Array.from(document.querySelectorAll('.risk')).find(item => item.querySelector('span')?.textContent?.trim().toLowerCase() === 'market data');
  const canonical = () => window.BiteySBTMarketState?.canonical || null;

  const syncMarketReadiness = () => {
    const row = getMarketRow(); if (!row) return;
    const badge = row.querySelector('b'); if (!badge) return;
    const state = window.BiteySBTMarketState;
    const feed = String(canonical()?.state || state?.feedState || 'OFFLINE').trim().toUpperCase();
    const available = ['CONNECTING', 'HISTORICAL', 'LIVE', 'DEGRADED'].includes(feed);
    const value = available ? (feed === 'LIVE' ? 'LIVE' : 'READY') : 'OFFLINE';
    if (badge.textContent !== value) badge.textContent = value;
    badge.style.color = available ? 'var(--accent)' : 'var(--danger)';
  };

  const syncCanonicalTerminal = () => {
    const state = window.BiteySBTMarketState;
    const c = canonical();
    if (!state || !c?.state) { syncMarketReadiness(); return; }
    const canonicalState = String(c.state).toUpperCase();
    const labels = {
      OFFLINE: '● MARKET OFFLINE',
      CONNECTING: '● CONNECTING LIVE FEED',
      HISTORICAL: '● HISTORICAL DATA',
      LIVE: '● LIVE DATA',
      DEGRADED: '● DEGRADED MARKET DATA',
      STALE: '● STALE MARKET DATA',
      ERROR: '● MARKET ERROR'
    };
    state.feedState = canonicalState;
    state.error = canonicalState === 'ERROR' && c.last_quote?.error ? c.last_quote.error : null;
    if (c.provider) {
      state.provider = String(c.provider);
      state.source = String(c.provider).toLowerCase();
    }
    const status = document.getElementById('mtFeedStatus');
    if (status) status.textContent = labels[canonicalState] || labels.OFFLINE;
    if (status) status.textContent += ' · ' + (c.symbol || state.symbol) + ' · ' + (c.timeframe || state.timeframe);
    const overlay = document.getElementById('mtOverlay');
    if (overlay) overlay.textContent = 'Bitey SBT · ' + (c.symbol || state.symbol) + ' · ' + (c.timeframe || state.timeframe) + ' · ' + canonicalState;
    syncMarketReadiness();
  };

  const enforceMarketReadiness = () => {
    syncCanonicalTerminal();
    const row = getMarketRow();
    if (row && typeof MutationObserver !== 'undefined' && !row.dataset.sbtMarketObserver) {
      row.dataset.sbtMarketObserver = '1';
      new MutationObserver(() => syncCanonicalTerminal()).observe(row, { childList: true, subtree: true, characterData: true });
    }
  };

  const redrawSbtChart = () => {
    const page = document.getElementById('bot-lab-page');
    if (!page || !page.classList.contains('active')) return;
    requestAnimationFrame(() => requestAnimationFrame(() => {
      try { if (window.BiteyWebTrader?.drawChart) window.BiteyWebTrader.drawChart(); } catch (_) {}
      syncCanonicalTerminal();
    }));
  };

  const openTerminal = () => {
    closeMobileMenu();
    const marker = document.querySelector('.nav button[data-page="bots"]');
    if (marker) {
      marker.click();
      redrawSbtChart();
      return;
    }
    if (window.BiteySBT?.openWebTrader) window.BiteySBT.openWebTrader().catch(console.error);
    else if (window.BiteySBT?.openBotLab) window.BiteySBT.openBotLab().catch(console.error);
  };

  const addTerminalLink = () => {
    const nav = document.querySelector('.nav');
    if (!nav || nav.querySelector('[data-sbt-terminal-link]')) return;
    const marker = nav.querySelector('button[data-page="bots"]');
    if (!marker) return;
    const a = document.createElement('button');
    a.type = 'button';
    a.dataset.sbtTerminalLink = '1';
    a.textContent = '▣ Trading Terminal';
    a.style.cssText = 'display:block;width:100%;text-align:left;background:transparent;color:#91a0b1;padding:10px 12px;border-radius:10px;margin:2px 0;border:1px solid transparent;font-size:14px;cursor:pointer;';
    a.addEventListener('click', openTerminal);
    marker.insertAdjacentElement('afterend', a);
  };

  document.addEventListener('click', event => {
    const target = event.target.closest('[data-page]');
    if (target) {
      closeMobileMenu();
      if (target.dataset.page === 'bots') redrawSbtChart();
      enforceMarketReadiness();
    }
  }, true);
  document.addEventListener('keydown', event => { if (event.key === 'Escape') closeMobileMenu(); });
  window.addEventListener('bitesbt:market-state', enforceMarketReadiness);

  const watchChartVisibility = () => {
    const page = document.getElementById('bot-lab-page');
    const chartWrap = page && page.querySelector('.chart-wrap');
    if (!chartWrap || typeof ResizeObserver === 'undefined') return;
    new ResizeObserver(redrawSbtChart).observe(chartWrap);
  };

  const boot = () => {
    enforceMarketReadiness();
    watchChartVisibility();
    addTerminalLink();
    setInterval(enforceMarketReadiness, 1000);
  };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot, { once: true });
  else boot();
})();
</script>`, { html: true });
        }
      })
      .transform(new Response(response.body, {
        status: response.status,
        statusText: response.statusText,
        headers: new Headers(response.headers)
      }));
  }
};
