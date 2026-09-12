(() => {
  const STORAGE_KEY = 'bitey-sbt-active-bot-v1';

  function readSpec() {
    const specEl = document.getElementById('blSpec');
    const text = specEl?.textContent?.trim() || '';
    if (!text || text === 'Aún no hay una especificación.') return null;
    return text;
  }

  function activateFromLab() {
    const spec = readSpec();
    if (!spec) return false;
    const prompt = document.getElementById('blPrompt')?.value?.trim() || '';
    const payload = {
      id: 'bot-' + Date.now(),
      name: prompt ? prompt.slice(0, 72) : 'Bitey Demo Bot',
      spec,
      mode: 'DEMO',
      status: 'ACTIVE',
      activatedAt: new Date().toISOString(),
      realMoney: false,
      brokerOrders: 0,
    };
    localStorage.setItem(STORAGE_KEY, JSON.stringify(payload));
    window.dispatchEvent(new CustomEvent('bitey:sbt-bot-activated', { detail: payload }));
    return true;
  }

  function getActive() {
    try { return JSON.parse(localStorage.getItem(STORAGE_KEY) || 'null'); } catch (_) { return null; }
  }

  function clear() {
    localStorage.removeItem(STORAGE_KEY);
    window.dispatchEvent(new CustomEvent('bitey:sbt-bot-cleared'));
  }

  function installLabHook() {
    const btn = document.getElementById('blDemo');
    if (!btn || btn.dataset.botBridgeReady) return;
    btn.dataset.botBridgeReady = '1';
    btn.addEventListener('click', () => setTimeout(activateFromLab, 150));
  }

  function renderTerminal() {
    const page = document.getElementById('bot-lab-page');
    if (!page?.classList.contains('web-trader-only')) return;
    let host = document.getElementById('sbt-active-bot');
    if (!host) {
      host = document.createElement('div');
      host.id = 'sbt-active-bot';
      host.style.cssText = 'position:absolute;right:14px;top:10px;z-index:5;max-width:310px;padding:8px 10px;border:1px solid #24563f;border-radius:8px;background:rgba(9,23,18,.94);color:#b9e9d0;font:10px ui-monospace,SFMono-Regular,Consolas,monospace;pointer-events:auto;backdrop-filter:blur(6px)';
      const wrap = page.querySelector('.chart-wrap');
      if (wrap) wrap.appendChild(host);
    }
    const bot = getActive();
    if (!bot) { host.style.display = 'none'; return; }
    host.style.display = 'block';
    host.innerHTML = `<b>BOT ACTIVE · DEMO</b><br><span>${escapeHtml(bot.name)}</span><br><span>REAL=false · BROKER_ORDERS=0</span><br><button type="button" id="sbtBotStop" style="margin-top:6px;padding:4px 7px;border:1px solid #395347;border-radius:5px;background:#101814;color:#b9e9d0;cursor:pointer;font-size:10px">Detener bot</button>`;
    host.querySelector('#sbtBotStop')?.addEventListener('click', () => { clear(); renderTerminal(); });
  }

  function escapeHtml(value) {
    return String(value).replace(/[&<>\"']/g, ch => ({'&':'&amp;','<':'&lt;','>':'&gt;','\"':'&quot;',"'":'&#39;'}[ch]));
  }

  function init() {
    installLabHook();
    renderTerminal();
  }

  window.BiteySBTBotBridge = { init, activateFromLab, getActive, clear };
  window.addEventListener('bitey:sbt-bot-activated', renderTerminal);
  window.addEventListener('bitey:sbt-bot-cleared', renderTerminal);
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init); else init();
})();
