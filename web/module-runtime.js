(function(){
'use strict';

const API=()=>((window.SBT_API_URL||localStorage.getItem('sbt_api_base')||'https://bitey-system-bots-trading-api.onrender.com').replace(/\/$/,''));
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
async function request(path,options){
  const r=await fetch(API()+path,Object.assign({headers:{Accept:'application/json'}},options||{}));
  const text=await r.text();
  let data={}; try{data=text?JSON.parse(text):{};}catch(_){data={raw:text};}
  if(!r.ok) throw new Error('HTTP '+r.status+' · '+(data.detail||data.error||data.message||text.slice(0,160)));
  return data;
}
function page(id){if(typeof window.page==='function')window.page(id);}
function set(id,v){const e=document.getElementById(id);if(e)e.textContent=v??'—';}

function addAction(id,title,description,buttonText,fn){
  const p=document.getElementById(id); if(!p||p.querySelector('[data-sbt-action]'))return;
  const c=document.createElement('div');c.className='card sbt-action-surface';c.dataset.sbtAction='1';c.style.marginTop='14px';
  c.innerHTML='<h3>'+esc(title)+'</h3><p class="sub">'+esc(description)+'</p><button class="btn primary" type="button">'+esc(buttonText)+'</button><div class="result" style="display:none;white-space:pre-wrap"></div>';
  p.appendChild(c);
  const b=c.querySelector('button'),o=c.querySelector('.result');
  b.onclick=async()=>{b.disabled=true;b.textContent='Ejecutando…';o.style.display='block';o.textContent='Conectando con '+API()+' …';try{const r=await fn();o.textContent=typeof r==='string'?r:JSON.stringify(r,null,2);}catch(e){o.textContent='ERROR REAL · '+e.message+'\nNo se muestran resultados inventados.';}finally{b.disabled=false;b.textContent=buttonText;}};
}

function stats(candles){
  const closes=candles.map(c=>Number(c.close)).filter(Number.isFinite);
  if(closes.length<2)return null;
  const n=Math.min(14,closes.length-1);
  let tr=0;for(let i=closes.length-n;i<closes.length;i++){const h=Number(candles[i].high),l=Number(candles[i].low),pc=closes[i-1];tr+=Math.max(h-l,Math.abs(h-pc),Math.abs(l-pc));}
  const atr=tr/n, last=closes.at(-1), prev=closes.at(-Math.min(15,closes.length));
  const fast=closes.slice(-Math.min(9,closes.length)).reduce((a,b)=>a+b,0)/Math.min(9,closes.length);
  const slow=closes.slice(-Math.min(21,closes.length)).reduce((a,b)=>a+b,0)/Math.min(21,closes.length);
  return {last,atr,bias:fast>slow?'BUY':fast<slow?'SELL':'NEUTRAL',change:(last-prev)/prev};
}

function ensureNav(){
  const nav=document.querySelector('.nav');if(!nav)return;
  if(!nav.querySelector('[data-page="web-trader"]')){
    const b=document.createElement('button');b.type='button';b.dataset.page='web-trader';b.textContent='▣ Web Trader';
    const marker=nav.querySelector('[data-page="bots"]');marker?marker.insertAdjacentElement('afterend',b):nav.appendChild(b);
    b.onclick=()=>page('web-trader');
  }
}

function ensureWebTrader(){
  if(document.getElementById('web-trader'))return;
  const main=document.querySelector('.main');if(!main)return;
  const s=document.createElement('section');s.className='page';s.id='web-trader';
  s.innerHTML='<div class="hero"><span class="eyebrow">Web Trader · Market Terminal</span><h2>Web Trader</h2><p>Datos de mercado reales desde el backend. Las previsualizaciones no envían órdenes al broker.</p><div class="toolbar"><button class="btn primary" id="wtRefresh">Actualizar mercado</button><button class="btn blue" id="wtAnalyze">Analizar con SBT</button><button class="btn" id="wtPreviewBuy">Previsualizar BUY</button><button class="btn" id="wtPreviewSell">Previsualizar SELL</button></div></div><div class="form"><label>Activo<select id="wtSymbol"><option>EURUSD</option><option>GBPUSD</option><option>USDJPY</option><option>XAUUSD</option><option>BTCUSD</option><option>SPX500</option><option>NAS100</option><option>AAPL</option><option>NVDA</option></select></label><label>Timeframe<select id="wtTf"><option>M5</option><option>M15</option><option>H1</option><option>H4</option><option>D1</option></select></label></div><div class="grid" style="margin-top:14px"><div class="card metric"><span class="label">Precio</span><div class="value" id="wtPrice">—</div><span class="muted" id="wtQuoteState">Sin consulta</span></div><div class="card metric"><span class="label">Sesgo</span><div class="value" id="wtBias">—</div><span class="muted" id="wtConfidence">—</span></div><div class="card metric"><span class="label">ATR</span><div class="value" id="wtAtr">—</div><span class="muted">calculado</span></div><div class="card metric"><span class="label">Velas</span><div class="value" id="wtCandles">0</div><span class="muted">backend</span></div></div><div class="layout"><div class="card"><h3>Market chart</h3><canvas id="wtChart" height="300" style="width:100%;background:#070c12;border:1px solid #202c39;border-radius:10px"></canvas></div><div class="card"><h3>Trade preview</h3><div id="wtPreview" class="notice">Actualiza el mercado.</div></div></div><div class="card"><h3>SBT analysis</h3><div id="wtAnalysis" class="sub">Sin análisis.</div></div>';
  main.appendChild(s);
  async function load(){
    const sym=document.getElementById('wtSymbol').value,tf=document.getElementById('wtTf').value;set('wtQuoteState','Consultando…');
    try{const[q,c]=await Promise.all([request('/api/v1/market/quote/'+encodeURIComponent(sym)+'?timeframe='+tf),request('/api/v1/market/candles/'+encodeURIComponent(sym)+'?timeframe='+tf+'&limit=120')]);const candles=c.candles||[];window.__wt={symbol:sym,timeframe:tf,quote:q,candles};const st=stats(candles);set('wtPrice',Number(q.last??q.price??q.bid).toFixed(5));set('wtCandles',candles.length);set('wtAtr',st?st.atr.toFixed(6):'—');set('wtBias',st?st.bias:'—');set('wtQuoteState','OK · '+(q.exchange||'market'));draw();}catch(e){set('wtQuoteState','ERROR · '+e.message);}
  }
  async function analyze(){try{if(!window.__wt||window.__wt.candles.length<35)await load();const x=window.__wt,a=await request('/api/v1/sbt/market-intelligence/analyze',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({symbol:x.symbol,timeframe:x.timeframe,candles:x.candles,capital:500,language:'es',event:'web_trader_analysis'})});set('wtBias',a.bias||'NEUTRAL');set('wtConfidence',a.confidence!=null?(Number(a.confidence)*100).toFixed(1)+'%':'—');set('wtAnalysis',a.summary||a.explanation||JSON.stringify(a));}catch(e){set('wtAnalysis','ERROR REAL · '+e.message);}}
  function preview(side){const x=window.__wt;if(!x){set('wtPreview','Actualiza el mercado primero.');return;}const st=stats(x.candles),entry=Number(x.quote.last??x.candles.at(-1).close),atr=st?.atr||0,sl=side==='BUY'?entry-1.3*atr:entry+1.3*atr,tp=side==='BUY'?entry+2.6*atr:entry-2.6*atr;set('wtPreview',side+' · DEMO PREVIEW\nEntrada '+entry.toFixed(5)+'\nSL '+sl.toFixed(5)+'\nTP '+tp.toFixed(5)+'\nRiesgo lógico US$1.25 · RR 2.00\nSin OrderSend.');}
  function draw(){const can=document.getElementById('wtChart'),x=window.__wt;if(!can||!x)return;const v=x.candles.slice(-80),w=can.clientWidth||700,h=300,dpr=devicePixelRatio||1;can.width=w*dpr;can.height=h*dpr;const ctx=can.getContext('2d');ctx.scale(dpr,dpr);const hi=Math.max(...v.map(z=>+z.high)),lo=Math.min(...v.map(z=>+z.low)),span=hi-lo||1;ctx.clearRect(0,0,w,h);ctx.strokeStyle='#18222d';for(let i=0;i<6;i++){const y=20+i*(h-45)/5;ctx.beginPath();ctx.moveTo(0,y);ctx.lineTo(w,y);ctx.stroke();}ctx.strokeStyle='#52e6a2';ctx.lineWidth=2;ctx.beginPath();v.forEach((z,i)=>{const xx=i*(w-20)/(v.length-1)+10,yy=20+(hi-z.close)/span*(h-45);i?ctx.lineTo(xx,yy):ctx.moveTo(xx,yy);});ctx.stroke();}
  document.getElementById('wtRefresh').onclick=load;document.getElementById('wtAnalyze').onclick=analyze;document.getElementById('wtPreviewBuy').onclick=()=>preview('BUY');document.getElementById('wtPreviewSell').onclick=()=>preview('SELL');load();
}

async function botRun(id){
  const [p,c]=await Promise.all([request('/api/v1/bot-profiles/'+id),request('/api/v1/market/candles/EURUSD?timeframe=M5&limit=100')]);
  const candles=c.candles||[],prices=candles.map(x=>Number(x.close)).filter(Number.isFinite);
  if(prices.length<30)throw Error('Insuficientes velas reales');
  const [sig,bt,risk]=await Promise.all([
    request('/api/v1/strategy/signal',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({symbol:'EURUSD',prices})}),
    request('/api/v1/backtest',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({prices,initial_capital:10000,fast_window:10,slow_window:30,fee_pct:0.001})}),
    request('/api/v1/bot-profiles/'+id+'/risk-preview?capital=10000')
  ]);
  window.__sbtLastBacktest=bt;
  return 'BOT '+p.name+' · señal '+String(sig.action).toUpperCase()+' · confianza '+(Number(sig.confidence)*100).toFixed(1)+'% · P/L '+Number(bt.total_pnl??bt.realized_pnl??0).toFixed(2)+' · riesgo/trade '+Number(risk.configured_loss_per_trade??0).toFixed(2)+' · '+prices.length+' cierres M5 reales.';
}

function wireBotObserver(){
  addAction('bot-observer','Bot Observer · smoke test','Carga un perfil real, mercado real, señal, backtest y risk-preview.','Probar Bot Observer',async()=>{
    const p=await request('/api/v1/bot-profiles');if(!p.length)throw Error('No hay bot profiles');return botRun(p[0].id);
  });
}
function wireMatrix(){
  addAction('matrix','SBT Market Matrix · smoke test','Consulta velas reales de varios instrumentos y calcula un sesgo transparente con los datos recibidos.','Escanear mercado',async()=>{
    const syms=['EURUSD','GBPUSD','USDJPY','XAUUSD','BTCUSD'];const rows=[];
    for(const s of syms){try{const d=await request('/api/v1/market/candles/'+s+'?timeframe=H1&limit=80');const st=stats(d.candles||[]);rows.push(s+': '+(st?st.bias:'NO DATA')+' · ATR '+(st?st.atr.toFixed(6):'—'));}catch(e){rows.push(s+': ERROR '+e.message);}}
    return rows.join('\n');
  });
}
function wireMarket(){
  addAction('market','Market Intelligence · smoke test','Ejecuta quote + velas + análisis SBT con el contrato real.','Probar Market Intelligence',async()=>{
    const q=await request('/api/v1/market/quote/EURUSD');const c=await request('/api/v1/market/candles/EURUSD?timeframe=H1&limit=120');const candles=c.candles||[];
    const a=await request('/api/v1/sbt/market-intelligence/analyze',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({symbol:'EURUSD',timeframe:'H1',candles,capital:500,language:'es',event:'ui_smoke_test'})});
    return 'EURUSD H1 · price '+Number(q.last??q.bid).toFixed(5)+' · candles '+candles.length+' · bias '+(a.bias||'NEUTRAL')+' · confidence '+(a.confidence!=null?(Number(a.confidence)*100).toFixed(1)+'%':'—');
  });
}
function wireResearch(){addAction('research','Research Lab · smoke test','Ejecuta el contrato research-only real.','Probar Research',async()=>{const d=await request('/api/v1/capabilities/delegate',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({contract:'sbt-v1',capability:'sbt',message:'Smoke test: analiza EURUSD H1 y devuelve evidencia y siguiente prueba.',source:'sbt-web-smoke',mode:'research-only'})});return 'RESEARCH OK · '+JSON.stringify(d.research||d);});}
function wireValidation(){addAction('validation','Virtual Validation · smoke test','Ejecuta la validación virtual real.','Probar Validation',async()=>{const d=await request('/api/v1/validation/virtual');return 'VALIDATION OK · P/L '+Number(d.realized_pnl||0).toFixed(2)+' · DD '+Number(d.max_drawdown_pct||0).toFixed(2)+'% · accepted '+(d.accepted_operations??0)+' · rejected '+(d.rejected_operations??0)+' · real_money='+d.real_money+' · broker_orders='+(d.broker_orders??0);});}
function wireAI(){addAction('ai-bot-lab','AI Bot Lab · smoke test','Usa únicamente endpoints reales ya presentes: perfiles, market data, señal, backtest y riesgo.','Probar AI Bot Lab',async()=>{const p=await request('/api/v1/bot-profiles');if(!p.length)throw Error('No hay bot profiles');return botRun(p[0].id);});}
function wireEvolution(){addAction('evolution','Evolution Engine · smoke test','Compara dos configuraciones de estrategia mediante el endpoint real de backtest; no inventa una API de evolución.','Comparar experimentos',async()=>{const c=await request('/api/v1/market/candles/EURUSD?timeframe=H1&limit=200'),prices=(c.candles||[]).map(x=>Number(x.close)).filter(Number.isFinite);if(prices.length<60)throw Error('Insuficientes velas');const [a,b]=await Promise.all([request('/api/v1/backtest',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({prices,initial_capital:10000,fast_window:8,slow_window:21,fee_pct:0.001})}),request('/api/v1/backtest',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({prices,initial_capital:10000,fast_window:10,slow_window:30,fee_pct:0.001})})]);return 'EXPERIMENT A 8/21 P/L '+Number(a.total_pnl??a.realized_pnl??0).toFixed(2)+' · EXPERIMENT B 10/30 P/L '+Number(b.total_pnl??b.realized_pnl??0).toFixed(2)+' · selección basada solo en resultados devueltos por backtest.';});}
function wireEV(){addAction('expected-value','Expected Value · smoke test','Comprueba que el módulo puede consumir el último backtest disponible.','Probar Expected Value',async()=>{if(!window.__sbtLastBacktest)await botRun((await request('/api/v1/bot-profiles'))[0].id);const b=window.__sbtLastBacktest;return 'EV input OK · trades='+(b.trades_detail||b.trades||[]).length+' · P/L '+Number(b.total_pnl??b.realized_pnl??0).toFixed(2);});}
function boot(){ensureNav();ensureWebTrader();wireBotObserver();wireMatrix();wireMarket();wireResearch();wireValidation();wireAI();wireEvolution();wireEV();}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else setTimeout(boot,0);
})();