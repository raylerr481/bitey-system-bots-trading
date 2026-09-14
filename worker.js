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
        broker_orders: 0
      }), { headers: { 'content-type': 'application/json; charset=utf-8' } });
    }

    const response = await env.ASSETS.fetch(request);
    const contentType = response.headers.get('content-type') || '';
    if (!contentType.includes('text/html')) return response;

    return new HTMLRewriter()
      .on('body', {
        element(element) {
          element.append(`<script>
(() => {
  const closeMobileMenu = () => {
    const side = document.getElementById('side');
    if (side) side.classList.remove('open');
  };

  const redrawSbtChart = () => {
    const page = document.getElementById('bot-lab-page');
    if (!page || !page.classList.contains('active')) return;
    const redraw = () => {
      try {
        if (window.BiteyWebTrader && typeof window.BiteyWebTrader.drawChart === 'function') {
          window.BiteyWebTrader.drawChart();
        }
      } catch (_) {}
    };
    requestAnimationFrame(() => requestAnimationFrame(redraw));
  };

  const syncMarketReadiness = () => {
    const rows = Array.from(document.querySelectorAll('.risk'));
    const row = rows.find(item => item.querySelector('span')?.textContent?.trim().toLowerCase() === 'market data');
    if (!row) return;
    const badge = row.querySelector('b');
    if (!badge) return;
    const state = window.BiteySBTMarketState;
    const source = String(state?.source || state?.provider || 'none').trim().toLowerCase();
    const feed = String(state?.feedState || 'OFFLINE').trim().toUpperCase();
    const available = source !== 'none' && ['CONNECTING', 'HISTORICAL', 'LIVE'].includes(feed);
    badge.textContent = available ? 'READY' : 'OFFLINE';
    badge.style.color = available ? 'var(--accent)' : 'var(--danger)';
  };

  const addTerminalLink = () => {
    const nav = document.querySelector('.nav');
    if (!nav || nav.querySelector('[data-sbt-terminal-link]')) return;
    const marker = Array.from(nav.querySelectorAll('button[data-page]')).find(b => b.dataset.page === 'bots');
    if (!marker) return;
    const a = document.createElement('button');
    a.type = 'button';
    a.dataset.sbtTerminalLink = '1';
    a.textContent = '▣ Trading Terminal';
    a.style.cssText = 'display:block;width:100%;text-align:left;background:transparent;color:#91a0b1;padding:10px 12px;border-radius:10px;margin:2px 0;border:1px solid transparent;font-size:14px;cursor:pointer;';
    a.addEventListener('click', () => {
      closeMobileMenu();
      if (window.BiteySBT && typeof window.BiteySBT.openWebTrader === 'function') {
        window.BiteySBT.openWebTrader().catch(err => console.error(err));
      } else if (window.BiteySBT && typeof window.BiteySBT.openBotLab === 'function') {
        window.BiteySBT.openBotLab().catch(err => console.error(err));
      }
    });
    marker.insertAdjacentElement('afterend', a);
  };

  document.addEventListener('click', (event) => {
    const target = event.target.closest('[data-page]');
    if (target) {
      closeMobileMenu();
      if (target.dataset.page === 'bots') redrawSbtChart();
      syncMarketReadiness();
    }
  }, true);

  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') closeMobileMenu();
  });

  document.addEventListener('click', (event) => {
    const side = document.getElementById('side');
    const hamburger = document.getElementById('hamb');
    if (!side || !side.classList.contains('open')) return;
    if (!side.contains(event.target) && event.target !== hamburger) closeMobileMenu();
  });

  window.addEventListener('bitesbt:market-state', syncMarketReadiness);

  const watchChartVisibility = () => {
    const page = document.getElementById('bot-lab-page');
    const chartWrap = page && page.querySelector('.chart-wrap');
    if (!chartWrap || typeof ResizeObserver === 'undefined') return;
    const observer = new ResizeObserver(() => redrawSbtChart());
    observer.observe(chartWrap);
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => {
      watchChartVisibility();
      addTerminalLink();
      syncMarketReadiness();
    }, { once: true });
  } else {
    watchChartVisibility();
    addTerminalLink();
    syncMarketReadiness();
  }
})();
</script>`, { html: true });
        }
      })
      .transform(response);
  }
};
