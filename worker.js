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
  const addTerminalLink = () => {
    const nav = document.querySelector('.nav');
    if (!nav || nav.querySelector('[data-sbt-terminal-link]')) return;
    const marker = Array.from(nav.querySelectorAll('button[data-page]')).find(b => b.dataset.page === 'bots');
    if (!marker) return;
    const wrap = marker.parentElement;
    const a = document.createElement('a');
    a.href = '/terminal.html';
    a.dataset.sbtTerminalLink = '1';
    a.textContent = '▣ Trading Terminal';
    a.style.cssText = 'display:block;text-decoration:none;color:#91a0b1;padding:10px 12px;border-radius:10px;margin:2px 0;border:1px solid transparent;font-size:14px;';
    a.onmouseenter = () => { a.style.background='#101720'; a.style.color='#fff'; a.style.borderColor='#1b2836'; };
    a.onmouseleave = () => { a.style.background='transparent'; a.style.color='#91a0b1'; a.style.borderColor='transparent'; };
    marker.insertAdjacentElement('afterend', a);
  };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', addTerminalLink, {once:true});
  else addTerminalLink();
})();
</script>`, { html: true });
        }
      })
      .transform(response);
  }
};
