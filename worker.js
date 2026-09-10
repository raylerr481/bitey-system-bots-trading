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
    // This is intentionally defensive because the existing page() handler
    // already closes the menu, but cached/older clients may retain the state.
    return new HTMLRewriter()
      .on('body', {
        element(element) {
          element.append(`<script>
(() => {
  const closeMobileMenu = () => {
    const side = document.getElementById('side');
    if (side) side.classList.remove('open');
  };

  document.addEventListener('click', (event) => {
    const target = event.target.closest('[data-page]');
    if (target) closeMobileMenu();
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
})();
</script>`, { html: true });
        }
      })
      .transform(response);
  }
};
