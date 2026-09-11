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

    // Mobile navigation guard: selecting any page must close the side menu.
    // Also redraw the SBT canvas after Bot Lab becomes visible. The chart is
    // initialized while its page is hidden, so its first canvas measurement
    // can be 0x0. Redraw after navigation and whenever the chart container
    // changes size.
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
    document.addEventListener('DOMContentLoaded', watchChartVisibility, { once: true });
  } else {
    watchChartVisibility();
  }
})();
</script>`, { html: true });
        }
      })
      .transform(response);
  }
};
