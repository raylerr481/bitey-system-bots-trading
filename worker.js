export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === '/health') {
      return new Response(JSON.stringify({
        service: 'bitey-system-bots-trading',
        status: 'ok',
        mode: 'research-demo',
        live: false,
        real_money: false,
        broker_orders: 0,
        web_build: '5c010c0'
      }), { headers: { 'content-type': 'application/json; charset=utf-8' } });
    }

    const response = await env.ASSETS.fetch(request);
    const contentType = response.headers.get('content-type') || '';
    if (!contentType.includes('text/html')) return response;

    let firstReadyBadge = true;
    return new HTMLRewriter()
      .on('b', {
        text(text) {
          if (!firstReadyBadge) return;
          const value = text.text.trim();
          if (value !== 'READY') return;
          text.replace('OFFLINE');
          firstReadyBadge = false;
        }
      })
      .on('body', {
        element(element) {
          element.append(`<script>
(() => {
  const closeMobileMenu = () => { const side = document.getElementById('side'); if (side) side.classList.remove('open'); };
  const getMarketRow = () => Array.from(document.querySelectorAll('.risk')).find(item => item.querySelector('span')?.textContent?.trim().toLowerCase() === 'market data');
  const syncMarketReadiness = () => {
    const row = getMarketRow(); if (!row) return false;
    const badge = row.querySelector('b'); if (!badge) return false;
    const state = window.BiteySBTMarketState;
    const source = String(state?.source || state?.provider || 'none').trim().toLowerCase();
    const feed = String(state?.feedState || 'OFFLINE').trim().toUpperCase();
    const available = source !== 'none' && ['CONNECTING', 'HISTORICAL', 'LIVE'].includes(feed);
    badge.textContent = available ? 'READY' : 'OFFLINE';
    badge.style.color = available ? 'var(--accent)' : 'var(--danger)';
    return true;
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
  document.addEventListener('click', event => { const target = event.target.closest('[data-page]'); if (target) { closeMobileMenu(); if (target.dataset.page === 'bots') redrawSbtChart(); syncMarketReadiness(); } }, true);
  document.addEventListener('keydown', event => { if (event.key === 'Escape') closeMobileMenu(); });
  document.addEventListener('click', event => { const side = document.getElementById('side'); const hamburger = document.getElementById('hamb'); if (!side || !side.classList.contains('open')) return; if (!side.contains(event.target) && event.target !== hamburger) closeMobileMenu(); });
  window.addEventListener('bitesbt:market-state', syncMarketReadiness);
  const watchChartVisibility = () => { const page = document.getElementById('bot-lab-page'); const chartWrap = page && page.querySelector('.chart-wrap'); if (!chartWrap || typeof ResizeObserver === 'undefined') return; new ResizeObserver(redrawSbtChart).observe(chartWrap); };
  const boot = () => { syncMarketReadiness(); watchChartVisibility(); addTerminalLink(); let attempts = 0; const timer = setInterval(() => { attempts += 1; syncMarketReadiness(); if (window.BiteySBTMarketState || attempts >= 20) clearInterval(timer); }, 250); };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot, { once: true }); else boot();
})();
</script>`, { html: true });
        }
      })
      .transform(response);
  }
};
