const API = (window.TRADINGSYSTEMBOT_API || '').replace(/\/$/, '');
const api = (path) => `${API}${path}`;
const $ = (id) => document.getElementById(id);

const copy = {
  es: { hello:'Hola. Soy el analista de TradingSystemBot. Puedo ayudarte a investigar una estrategia, interpretar un backtest o revisar riesgo.', placeholder:'Ej.: analiza una estrategia SMA para EUR/USD…' },
  pt: { hello:'Olá. Sou o analista do TradingSystemBot. Posso ajudar a pesquisar uma estratégia, interpretar um backtest ou revisar risco.', placeholder:'Ex.: analise uma estratégia SMA para EUR/USD…' },
  en: { hello:'Hello. I am the TradingSystemBot analyst. I can help research a strategy, interpret a backtest, or review risk.', placeholder:'Example: analyze an SMA strategy for EUR/USD…' }
};
let lang = localStorage.getItem('tsb-language') || 'es';
$('language').value = lang;
$('language').addEventListener('change', e => { lang=e.target.value; localStorage.setItem('tsb-language',lang); $('chat-input').placeholder=copy[lang].placeholder; });
$('chat-input').placeholder=copy[lang].placeholder;

async function getJSON(path, options={}) {
  const r = await fetch(api(path), { headers:{'Content-Type':'application/json'}, ...options });
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  return r.json();
}

async function loadSystem(){
  try { const s=await getJSON('/api/v1/system'); $('mode-value').textContent=s.live_trading_enabled?'LIVE':'DEMO'; }
  catch(e) { console.warn('System API unavailable',e); }
}

async function loadProfiles(){
  const root=$('profiles');
  try {
    const profiles=await getJSON('/api/v1/bot-profiles');
    $('profiles-value').textContent=profiles.length;
    root.innerHTML=profiles.map(p=>`<article class="card profile"><h3>${escapeHTML(p.name)}</h3><p>${escapeHTML(p.short_description)}</p><div class="risk"><span>Riesgo: ${escapeHTML(p.risk.level)}</span><span>Posición: ${(p.risk.max_position_pct*100).toFixed(1)}%</span></div><p>${escapeHTML(p.beginner_explanation)}</p><button class="btn secondary" data-profile="${escapeHTML(p.id)}">Ver riesgo</button><div id="risk-${escapeHTML(p.id)}" class="result muted"></div></article>`).join('');
    root.querySelectorAll('[data-profile]').forEach(b=>b.addEventListener('click',()=>previewRisk(b.dataset.profile)));
  } catch(e) { root.innerHTML='<div class="card profile"><p>La API todavía no está disponible. La interfaz está lista para conectarse.</p></div>'; }
}
async function previewRisk(id){
  const capital=Number($('bt-capital').value)||10000;
  try { const r=await getJSON(`/api/v1/bot-profiles/${id}/risk-preview?capital=${capital}`); const el=$(`risk-${id}`); el.textContent=`Con ${capital}: posición máxima ${r.max_position_value.toFixed(2)} · pérdida configurada por operación ${r.configured_loss_per_trade.toFixed(2)} · pérdida diaria ${r.configured_daily_loss.toFixed(2)}`; } catch(e) { console.error(e); }
}

$('chat-form').addEventListener('submit', async e=>{
  e.preventDefault(); const input=$('chat-input'); const text=input.value.trim(); if(!text)return;
  appendMessage(text,'user'); input.value='';
  try { const r=await getJSON('/api/v1/ai/chat',{method:'POST',body:JSON.stringify({message:text,language:lang})}); appendMessage(r.reply,'ai'); }
  catch(e) { appendMessage('La capa ChatGPT aún no está configurada en el servidor. La interfaz está preparada; configura OPENAI_API_KEY para activarla.','ai'); }
});
function appendMessage(text,type){const el=document.createElement('div');el.className=`message ${type}`;el.textContent=text;$('chat-messages').appendChild(el);el.scrollIntoView({behavior:'smooth'});}

$('run-backtest').addEventListener('click', async()=>{
  const out=$('backtest-result'); out.textContent='Ejecutando simulación SMA sobre una serie de prueba…';
  const capital=Number($('bt-capital').value)||10000;
  const prices=Array.from({length:240},(_,i)=>100 + i*0.035 + Math.sin(i/7)*1.8 + Math.sin(i/19)*0.9);
  try {
    const r=await getJSON('/api/v1/backtest',{method:'POST',body:JSON.stringify({prices,initial_capital:capital,fast_window:10,slow_window:30,fee_pct:0.001})});
    out.textContent=`SMA Crossover · capital inicial ${capital.toFixed(2)} · resultado: ${JSON.stringify(r)}`;
  } catch(e) { out.textContent='No fue posible ejecutar el backtest. Verifica que el backend esté disponible.'; }
});
function escapeHTML(s){return String(s).replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));}
loadSystem(); loadProfiles();
