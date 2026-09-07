(() => {
  const API = (window.SBT_API_URL || 'https://bitey-system-bots-trading-api.onrender.com').replace(/\/$/, '');
  window.SBT_LIVE_TRADING_ENABLED = false;
  window.SBT_SAFETY = { live: false, real_money: false, broker_orders: 0 };

  function banner() {
    const el = document.createElement('div');
    el.textContent = 'RESEARCH / DEMO ONLY · LIVE=false · REAL_MONEY=false · BROKER_ORDERS=0';
    el.style.cssText = 'position:fixed;bottom:0;left:0;right:0;z-index:9999;padding:8px;text-align:center;background:#111;color:#fff;font:600 12px system-ui;letter-spacing:.04em';
    document.body.appendChild(el);
  }
  async function health() {
    try {
      const r = await fetch(API + '/api/v1/system');
      if (!r.ok) throw new Error('HTTP ' + r.status);
      return r.json();
    } catch (_) { return null; }
  }
  function expose() {
    window.BiteySBT = {
      api: API,
      safety: window.SBT_SAFETY,
      health,
      async validation() {
        const r = await fetch(API + '/api/v1/validation/virtual', { method: 'POST', headers: {'content-type':'application/json'}, body: '{}' });
        if (!r.ok) throw new Error('Validation HTTP ' + r.status);
        return r.json();
      },
      async strategyRegistry() {
        const r = await fetch(API + '/api/v1/strategy/registry');
        if (!r.ok) throw new Error('Registry HTTP ' + r.status);
        return r.json();
      },
      async riskGateEvaluate(payload) {
        const r = await fetch(API + '/api/v1/strategy/risk-gate/evaluate', { method:'POST', headers:{'content-type':'application/json'}, body:JSON.stringify(payload) });
        if (!r.ok) throw new Error('Risk Gate HTTP ' + r.status);
        return r.json();
      }
    };
  }
  function boot() { expose(); banner(); health(); }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot); else boot();
})();
