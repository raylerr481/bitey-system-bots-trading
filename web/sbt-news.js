(() => {
  const apiBase = () => window.SBT_API_URL || localStorage.getItem('sbt_api_base') || '';
  const esc = (v) => String(v ?? '').replace(/[&<>\"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','\"':'&quot;',"'":'&#39;'}[c]));
  const api = async (path, options = {}) => {
    const token = localStorage.getItem('sbt_access_token') || localStorage.getItem('access_token');
    const headers = {'Content-Type':'application/json', ...(options.headers || {})};
    if (token) headers.Authorization = `Bearer ${token}`;
    const r = await fetch(`${apiBase()}${path}`, {...options, headers});
    const data = await r.json().catch(() => ({}));
    if (!r.ok) throw new Error(data.detail || data.reason || `HTTP ${r.status}`);
    return data;
  };

  const sample = {
    event_id:'demo-fed-001',
    headline:'Central bank rate decision increases market volatility expectations',
    event_type:'rate_decision', sector:'financials', assets:['EURUSD','SPY','TLT'], source:'Demo event'
  };

  function install() {
    const nav = document.querySelector('nav') || document.querySelector('.sidebar') || document.querySelector('aside');
    if (nav && !document.getElementById('sbtNewsNav')) {
      const a = document.createElement('a'); a.id='sbtNewsNav'; a.href='#market-intelligence'; a.textContent='Market Intelligence';
      a.style.cssText='display:block;padding:10px 12px;text-decoration:none;cursor:pointer;'; nav.appendChild(a);
      a.onclick = e => { e.preventDefault(); show(); };
    }
    if (!document.getElementById('sbtNewsPage')) {
      const page = document.createElement('section'); page.id='sbtNewsPage'; page.hidden=true;
      page.style.cssText='padding:24px;max-width:1200px;margin:auto;';
      page.innerHTML = `
        <div style="display:flex;justify-content:space-between;gap:16px;align-items:center;flex-wrap:wrap">
          <div><h1 style="margin:0">Bitey Market Intelligence</h1><p>Noticias y eventos que pueden mover mercados.</p></div>
          <button id="sbtNewsDemo">Probar evento demo</button>
        </div>
        <div style="display:flex;gap:8px;flex-wrap:wrap;margin:16px 0">
          <input id="sbtNewsHeadline" style="flex:1;min-width:280px" placeholder="Buscar / pegar titular o evento...">
          <select id="sbtNewsType"><option value="rate_decision">Rate decision</option><option value="earnings">Earnings</option><option value="inflation">Inflation</option><option value="employment">Employment</option><option value="commodity_supply">Commodity supply</option><option value="geopolitical">Geopolitical</option><option value="merger_acquisition">M&A</option></select>
          <input id="sbtNewsAssets" placeholder="Activos: EURUSD, SPY">
          <button id="sbtNewsAnalyze">Analizar evento</button>
        </div>
        <div id="sbtNewsResult"></div>
      `;
      document.body.appendChild(page);
      document.getElementById('sbtNewsDemo').onclick=()=>run(sample);
      document.getElementById('sbtNewsAnalyze').onclick=()=>run({event_id:`manual-${Date.now()}`,headline:document.getElementById('sbtNewsHeadline').value || 'Market event for research',event_type:document.getElementById('sbtNewsType').value,sector:'unknown',assets:document.getElementById('sbtNewsAssets').value.split(',').map(x=>x.trim()).filter(Boolean),source:'user input'});
    }
  }

  function show(){
    install();
    document.getElementById('sbtNewsPage').hidden=false;
    window.scrollTo({top:0,behavior:'smooth'});
  }

  async function run(event) {
    show(); const out=document.getElementById('sbtNewsResult'); out.innerHTML='<p>Analizando evento…</p>';
    try {
      const data=await api('/api/v1/news/bot-prompts',{method:'POST',body:JSON.stringify({event,timeframe:'1h'})});
      const a=data.event_analysis;
      out.innerHTML=`
        <div style="padding:16px;border:1px solid #444;border-radius:12px;margin-bottom:16px">
          <h2>${esc(a.headline)}</h2>
          <p><b>${esc(a.bias)}</b> · impacto ${esc(a.impact)} · horizonte ${esc(a.horizon)}</p>
          <p>Oportunidad: <b>${Number(a.opportunity_score).toFixed(2)}</b> · Riesgo: <b>${Number(a.risk_score).toFixed(2)}</b> · Volatilidad: <b>${Number(a.volatility_score).toFixed(2)}</b></p>
          <p>${esc(a.rationale)}</p>
          <p><b>Conflictos:</b> ${esc((a.conflicts||[]).join(' · ') || 'Ninguno detectado')}</p>
          <p style="opacity:.75">⚠ Las noticias generan hipótesis y alertas; no ejecutan órdenes.</p>
        </div>
        <h2>Propuestas de BOT</h2>
        <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:12px">
          ${data.proposals.map(p=>`<article style="padding:16px;border:1px solid #444;border-radius:12px"><h3>${esc(p.profile)}</h3><p>${esc(p.objective)}</p><p><b>Hipótesis:</b> ${esc(p.hypothesis)}</p><p><b>Entrada:</b> ${esc(p.entry_filters.join(' '))}</p><p><b>Riesgo:</b> ${esc(p.risk_controls.join(' '))}</p><p><b>Validación:</b> ${esc(p.validation_requirements.join(' '))}</p><button class="sbtCopyPrompt" data-id="${esc(p.prompt_id)}">Copiar especificación</button></article>`).join('')}
        </div>`;
      out.querySelectorAll('.sbtCopyPrompt').forEach(btn=>btn.onclick=async()=>{const p=data.proposals.find(x=>x.prompt_id===btn.dataset.id); await navigator.clipboard?.writeText(JSON.stringify(p,null,2)); btn.textContent='Copiado';});
    } catch(e) { out.innerHTML=`<div style="padding:16px;border:1px solid #833;border-radius:12px"><b>No se pudo conectar con SBT:</b> ${esc(e.message)}</div>`; }
  }

  if (document.readyState==='loading') document.addEventListener('DOMContentLoaded',install); else install();
  window.SBTNews={show,run};
})();
