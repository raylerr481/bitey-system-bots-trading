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

  const addTerminalLink = () => {
    const nav = document.querySelector('.nav');
    if (!nav || nav.querySelector('[data-sbt-terminal-link]')) return;
    const marker = Array.from(nav.querySelectorAll('button[data-page]')).find(b => b.dataset.page === 'bots');
    if (!marker) return;
    const a = document.createElement('a');
    a.href = '/terminal.html';
    a.dataset.sbtTerminalLink = '1';
    a.textContent = '▣ Trading Terminal';
    a.style.cssText = 'display:block;text-decoration:none;color:#91a0b1;padding:10px 12px;border-radius:10px;margin:2px 0;border:1px solid transparent;font-size:14px;';
    a.onmouseenter = () => { a.style.background='#101720'; a.style.color='#fff'; a.style.borderColor='#1b2836'; };
    a.onmouseleave = () => { a.style.background='transparent'; a.style.color='#91a0b1'; a.style.borderColor='transparent'; };
    marker.insertAdjacentElement('afterend', a);
  };

  document.addEventListener('click', (event) => {
    const target = event.target.closest('[data-page]');
    if (target) {
      closeMobileMenu();
      if (target.dataset.page === 'bots') redrawSbtChart();
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
    }, { once: true });
  } else {
    watchChartVisibility();
    addTerminalLink();
  }
})();
</script>`, { html: true });
        }
      })
      .transform(response);
  }
};
