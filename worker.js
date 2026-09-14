export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const BUILD = 'f5-market-state-no-store';
    // Public verification marker: this Worker must report BUILD on every /health request.
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
  const syncMarketReadiness = () => {
    const row = getMarketRow(); if (!row) return;
    const badge = row.querySelector('b'); if (!badge) return;
    const state = window.BiteySBTMarketState;
    const source = String(state?.source || state?.provider || 'none').trim().toLowerCase();
    const feed = String(state?.feedState || 'OFFLINE').trim().toUpperCase();
    const available = source !== 'none' && ['CONNECTING', 'HISTORICAL', 'LIVE'].includes(feed);
    const value = available ? 'READY' : 'OFFLINE';
    if (badge.textContent !== value) badge.textContent = value;
    badge.style.color = available ? 'var(--accent)' : 'var(--danger)';
  };
  const enforceMarketReadiness = () => {
    syncMarketReadiness();
    const row = getMarketRow();
    if (row && typeof MutationObserver !== 'undefined' && !row.dataset.sbtMarketObserver) {
      row.dataset.sbtMarketObserver = '1';
      new MutationObserver(() => syncMarketReadiness()).observe(row, { childList: true, subtree: true, characterData: true });
    }
  };
  const redrawSbtChart = () => {
    const page = document.getElementById('bot-lab-page'); if (!page || !page.classList.contains('active')) return;
    requestAnimationFrame(() => requestAnimationFrame(() => { try { if (window.BiteyWebTrader?.drawChart) window.BiteyWebTrader.drawChart(); } catch (_) {} }));
  };
  const addTerminalLink = () => {
    const nav = document.querySelector('.nav'); if (!nav || nav.querySelector('[data-sbt-terminal-link]')) return;
    const marker = Array.from(nav.querySelectorAll('button[data-page]')).find(b => b.dataset.page === 'bots'); if (!marker) return;
    const a = document.createElement('button'); a.type = 'button'; a.dataset.sbtTerminalLink = '1'; a.textContent = '▣ Trading Terminal';
    a.style.cssText = 'display:block;width:100%;text-align:left;background:transparent;color:#91a0b1;padding:10px 12px;border-radius:10px;margin:2px 0;border:1px solid transparent;font-size:14px;cursor:pointer;';
    a.addEventListener('click', () => { closeMobileMenu(); if (window.BiteySBT?.openWebTrader) window.BiteySBT.openWebTrader().catch(console.error); else if (window.BiteySBT?.openBotLab) window.BiteySBT.openBotLab().catch(console.error); });
    marker.insertAdjacentElement('afterend', a);
  };
  document.addEventListener('click', event => { const target = event.target.closest('[data-page]'); if (target) { closeMobileMenu(); if (target.dataset.page === 'bots') redrawSbtChart(); enforceMarketReadiness(); } }, true);
  document.addEventListener('keydown', event => { if (event.key === 'Escape') closeMobileMenu(); });
  document.addEventListener('click', event => { const side = document.getElementById('side'); const hamburger = document.getElementById('hamb'); if (!side || !side.classList.contains('open')) return; if (!side.contains(event.target) && event.target !== hamburger) closeMobileMenu(); });
  window.addEventListener('bitesbt:market-state', enforceMarketReadiness);
  const watchChartVisibility = () => { const page = document.getElementById('bot-lab-page'); const chartWrap = page && page.querySelector('.chart-wrap'); if (!chartWrap || typeof ResizeObserver === 'undefined') return; new ResizeObserver(redrawSbtChart).observe(chartWrap); };
  const boot = () => { enforceMarketReadiness(); watchChartVisibility(); addTerminalLink(); setInterval(enforceMarketReadiness, 1000); };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot, { once: true }); else boot();
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
