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
    try { const r = await fetch(API + '/api/v1/system'); if (!r.ok) throw new Error('HTTP '+r.status); return r.json(); }
    catch (_) { return null; }
  }
  function loadWebTrader() {
    if (window.BiteyWebTrader) { window.BiteyWebTrader.init(); return; }
    if (document.querySelector('script[data-bitey-web-trader]')) return;
    const script = document.createElement('script');
    script.src = '/web-trader.js';
    script.defer = true;
    script.dataset.biteyWebTrader = '1';
    document.head.appendChild(script);
  }
  function loadTradingMode() {
    if (window.BiteySBTTradingMode) { window.BiteySBTTradingMode.init(); return; }
    if (document.querySelector('script[data-bitey-trading-mode]')) return;
    const script = document.createElement('script');
    script.src = '/trading-mode.js';
    script.defer = true;
    script.dataset.biteyTradingMode = '1';
    document.head.appendChild(script);
  }
  async function openThesisLab() {
    if (document.getElementById('thesis-lab-page')) return activateThesisLab();
    const main = document.querySelector('main.main');
    if (!main) return;
    const r = await fetch('/thesis-lab.html', { cache:'no-store' });
    if (!r.ok) throw new Error('Thesis Lab HTTP '+r.status);
    const wrap = document.createElement('div');
    wrap.innerHTML = await r.text();
    const section = wrap.querySelector('#thesis-lab-page');
    if (!section) throw new Error('Thesis Lab markup missing');
    main.appendChild(section);
    Array.from(wrap.querySelectorAll('script')).forEach(s => { const n=document.createElement('script'); n.textContent=s.textContent; document.body.appendChild(n); });
    activateThesisLab();
  }
  function activateThesisLab() {
    document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
    const p=document.getElementById('thesis-lab-page'); if(p) p.classList.add('active');
    const title=document.getElementById('title'); if(title) title.textContent='Mathematical Thesis Lab';
    document.querySelectorAll('.nav button').forEach(b=>b.classList.toggle('active',b.dataset.page==='thesis-lab'));
  }
  function installThesisNav() {
    const nav=document.querySelector('.nav'); if(!nav || nav.querySelector('[data-page="thesis-lab"]')) return;
    const small=Array.from(nav.querySelectorAll('small')).find(x=>x.textContent.trim().toLowerCase()==='build');
    const b=document.createElement('button'); b.dataset.page='thesis-lab'; b.textContent='∑ Mathematical Thesis Lab';
    b.addEventListener('click',()=>openThesisLab().catch(e=>console.error(e)));
    if(small) small.insertAdjacentElement('afterend',b); else nav.appendChild(b);
  }
  async function openBotLab() {
    if (document.getElementById('bot-lab-page')) return activateBotLab();
    const main = document.querySelector('main.main');
    if (!main) return;
    const r = await fetch('/bot-lab.html', { cache:'no-store' });
    if (!r.ok) throw new Error('Bot Lab HTTP '+r.status);
    const wrap = document.createElement('div');
    wrap.innerHTML = await r.text();
    const section = wrap.querySelector('#bot-lab-page');
    if (!section) throw new Error('Bot Lab markup missing');
    main.appendChild(section);
    Array.from(wrap.querySelectorAll('script')).forEach(s => { const n=document.createElement('script'); n.textContent=s.textContent; document.body.appendChild(n); });
    activateBotLab();
  }
  function closeMobileMenu() {
    const side = document.getElementById('side');
    if (!side) return;
    side.classList.remove('open');
    if (window.matchMedia('(max-width: 850px)').matches) {
      side.style.transform = 'translateX(-100%)';
      side.style.pointerEvents = 'none';
    }
  }
  function activateBotLab() {
    closeMobileMenu();
    document.querySelectorAll('.page').forEach(p=>p.classList.remove('active'));
    const p=document.getElementById('bot-lab-page'); if(p) p.classList.add('active');
    const title=document.getElementById('title'); if(title) title.textContent='Bot Lab';
    document.querySelectorAll('.nav button').forEach(b=>b.classList.toggle('active',b.dataset.page==='bots'));
    const status=document.getElementById('apiStatus'); if(status) status.textContent='Bot Lab connected · live trading disabled';
    loadWebTrader();
    loadTradingMode();
  }
  function installBotLabNav() {
    const nav=document.querySelector('.nav'); if(!nav || nav.querySelector('[data-page="bots"]')) return;
    const small=Array.from(nav.querySelectorAll('small')).find(x=>x.textContent.trim().toLowerCase()==='workspace');
    const b=document.createElement('button'); b.dataset.page='bots'; b.textContent='◉ Bot Lab';
    b.addEventListener('click',()=>openBotLab().catch(e=>console.error(e)));
    if(small) small.insertAdjacentElement('afterend',b); else nav.appendChild(b);
  }
  function interceptExistingBotButton() {
    document.querySelectorAll('[data-page="bots"]').forEach(b=>{
      if (b.dataset.botLabWired) return;
      b.dataset.botLabWired='1';
      b.addEventListener('click',event=>{
        event.preventDefault();
        event.stopImmediatePropagation();
        closeMobileMenu();
        openBotLab().catch(e=>console.error(e));
      },true);
    });
  }
  function expose() {
    window.BiteySBT = { api:API, safety:window.SBT_SAFETY, health,
      async validation(){const r=await fetch(API+'/api/v1/validation/virtual',{method:'POST',headers:{'content-type':'application/json'},body:'{}'});if(!r.ok)throw new Error('Validation HTTP '+r.status);return r.json()},
      async strategyRegistry(){const r=await fetch(API+'/api/v1/strategy/registry');if(!r.ok)throw new Error('Registry HTTP '+r.status);return r.json()},
      async riskGateEvaluate(payload){const r=await fetch(API+'/api/v1/strategy/risk-gate/evaluate',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(payload)});if(!r.ok)throw new Error('Risk Gate HTTP '+r.status);return r.json()},
      openThesisLab,
      openBotLab
    };
  }
  function boot(){expose();banner();installThesisNav();installBotLabNav();interceptExistingBotButton();health();}
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot);else boot();
})();