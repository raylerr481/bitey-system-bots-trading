import os
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path

ROOT = Path(__file__).resolve().parent
os.chdir(ROOT)
port = int(os.environ.get("PORT", "8080"))

BITEY_IA_URL = "https://bitey-web.raylerr481.workers.dev/"
BITEY_IA_WIDGET = '''
<style>
.bitey-ia-shortcut{display:flex;align-items:center;gap:12px;margin-top:16px;padding:12px 14px;border:1px solid #263445;border-radius:12px;background:linear-gradient(135deg,#0d1718,#0b1119);text-decoration:none;color:#edf2f7;transition:.18s ease;box-shadow:0 8px 24px #0004}
.bitey-ia-shortcut:hover{transform:translateY(-1px);border-color:#55e6a5;background:#101c1a}
.bitey-ia-icon{width:38px;height:38px;min-width:38px;border-radius:11px;background:linear-gradient(135deg,#55e6a5,#56a8ff);display:grid;place-items:center;color:#06110c;font-weight:900;font-size:20px;box-shadow:0 0 18px #55e6a533}
.bitey-ia-copy{display:grid;gap:2px}.bitey-ia-copy strong{font-size:13px}.bitey-ia-copy span{font-size:11px;color:#8e9aaa}.bitey-ia-arrow{margin-left:auto;color:#55e6a5;font-size:18px}
</style>
<a class="bitey-ia-shortcut" href="https://bitey-web.raylerr481.workers.dev/" target="_blank" rel="noopener noreferrer" aria-label="Abrir Bitey IA">
  <span class="bitey-ia-icon" aria-hidden="true">B</span>
  <span class="bitey-ia-copy"><strong>Bitey IA</strong><span>Asistente de inteligencia general</span></span>
  <span class="bitey-ia-arrow">↗</span>
</a>
'''

API_BOOTSTRAP = '''<script>
window.SBT_API_URL = "https://bitey-system-bots-trading-api.onrender.com";
window.SBT_LIVE_TRADING_ENABLED = false;
try { if (!localStorage.getItem('sbt_api_base')) localStorage.setItem('sbt_api_base', window.SBT_API_URL); } catch (_) {}
</script>'''

VALIDATION_WIRING = '''<script>
(function () {
  const run = document.getElementById('runVirtual');
  if (!run) return;
  run.addEventListener('click', async function (event) {
    event.preventDefault(); event.stopImmediatePropagation();
    const base=(window.SBT_API_URL||localStorage.getItem('sbt_api_base')||'').replace(/\\/$/,'');
    const result=document.getElementById('testResult');
    const set=(id,value)=>{const el=document.getElementById(id);if(el)el.textContent=value;};
    run.disabled=true; run.textContent='Ejecutando…';
    if(result){result.style.display='block';result.textContent='Ejecutando validación virtual reproducible…';}
    try{
      const r=await fetch(base+'/api/v1/validation/virtual',{headers:{'Accept':'application/json'}});
      if(!r.ok)throw new Error('API HTTP '+r.status);
      const d=await r.json();
      set('testPnl','R$ '+Number(d.realized_pnl).toFixed(2));set('testDd',Number(d.max_drawdown_pct).toFixed(2)+'%');set('testTrades',d.accepted_operations+' aceptadas');set('testRejected',String(d.rejected_operations));
      if(result)result.textContent='VALIDACIÓN COMPLETADA · '+d.strategy+' · '+d.fixture+'. P/L R$ '+Number(d.realized_pnl).toFixed(2)+', drawdown '+Number(d.max_drawdown_pct).toFixed(2)+'%, '+d.accepted_operations+' operaciones aceptadas y '+d.rejected_operations+' rechazadas. Dinero real: '+d.real_money+'. Broker orders: '+d.broker_orders+'.';
      const status=document.getElementById('apiStatus');if(status)status.textContent='Virtual validation connected · live trading disabled';
    }catch(e){if(result)result.textContent='No se pudo ejecutar la validación: '+e.message+'. No se muestran métricas inventadas.';const status=document.getElementById('apiStatus');if(status)status.textContent='API validation unavailable · live trading disabled';}
    finally{run.disabled=false;run.textContent='Ejecutar prueba local';}
  },true);
})();
</script>'''

MARKET_WIRING = '''<script>
(function(){
 const refresh=document.getElementById('refreshMarket'); if(!refresh)return;
 let currentTimeframe='M5', currentCandles=[], currentAnalysis=null, zoom=60;
 const base=()=>((window.SBT_API_URL||localStorage.getItem('sbt_api_base')||'').replace(/\\/$/,''));
 const set=(id,v)=>{const e=document.getElementById(id);if(e)e.textContent=v;};
 refresh.addEventListener('click',()=>loadMarket(currentTimeframe),true);
 function ensureToolbar(chart){
  if(document.getElementById('mt5Toolbar'))return;
  const bar=document.createElement('div');bar.id='mt5Toolbar';bar.className='mt5-toolbar';
  bar.innerHTML='<div class="mt5-group"><b>EURUSD</b><button data-tf="M1">M1</button><button data-tf="M5" class="active">M5</button><button data-tf="M15">M15</button><button data-tf="H1">H1</button><button data-tf="H4">H4</button><button data-tf="D1">D1</button></div><div class="mt5-group"><button id="mt5ZoomOut">−</button><button id="mt5ZoomIn">+</button><button id="mt5Reset">Reset</button><span class="mt5-live">● MT5</span></div>';
  chart.parentNode.insertBefore(bar,chart);
  bar.querySelectorAll('[data-tf]').forEach(b=>b.addEventListener('click',()=>{bar.querySelectorAll('[data-tf]').forEach(x=>x.classList.remove('active'));b.classList.add('active');currentTimeframe=b.dataset.tf;loadMarket(currentTimeframe);}));
  document.getElementById('mt5ZoomIn').onclick=()=>{zoom=Math.max(25,zoom-10);drawMT5Chart(chart,currentCandles,currentAnalysis)};
  document.getElementById('mt5ZoomOut').onclick=()=>{zoom=Math.min(currentCandles.length||100,zoom+10);drawMT5Chart(chart,currentCandles,currentAnalysis)};
  document.getElementById('mt5Reset').onclick=()=>{zoom=Math.min(60,currentCandles.length||60);drawMT5Chart(chart,currentCandles,currentAnalysis)};
 }
 async function loadMarket(tf){
  const chart=document.getElementById('marketChart');ensureToolbar(chart);refresh.disabled=true;refresh.textContent='Analizando…';
  const status=document.getElementById('apiStatus');if(status)status.textContent='Consultando MT5 market data real · '+tf+'…';
  try{
   const [qr,cr]=await Promise.all([fetch(base()+'/api/v1/market/quote/EURUSD',{headers:{'Accept':'application/json'}}),fetch(base()+'/api/v1/market/candles/EURUSD?timeframe='+encodeURIComponent(tf)+'&limit=200',{headers:{'Accept':'application/json'}})]);
   if(!qr.ok)throw new Error('Quote HTTP '+qr.status);if(!cr.ok)throw new Error('Candles HTTP '+cr.status);
   const q=await qr.json(),cd=await cr.json(),candles=Array.isArray(cd)?cd:(Array.isArray(cd.candles)?cd.candles:[]);
   if(candles.length<35)throw new Error('Solo hay '+candles.length+' velas; se requieren al menos 35');
   const ar=await fetch(base()+'/api/v1/sbt/market-intelligence/analyze',{method:'POST',headers:{'Content-Type':'application/json','Accept':'application/json'},body:JSON.stringify({symbol:'EURUSD',timeframe:tf,candles,capital:10000,language:'es',event:'market_structure',evidence:[]})});
   if(!ar.ok)throw new Error('Analysis HTTP '+ar.status);const a=await ar.json();
   currentCandles=candles;currentAnalysis=a;zoom=Math.min(60,candles.length);
   const price=q.last??q.bid??q.ask;set('miPrice',price!=null?Number(price).toFixed(5):'—');set('miBias',a.bias||'NEUTRAL');const atr=a.technical&&a.technical.atr?a.technical.atr.value:null;set('miVol',atr!=null?Number(atr).toFixed(6):'—');set('miConfidence',a.confidence!=null?(Number(a.confidence)*100).toFixed(1)+'%':'—');drawMT5Chart(chart,candles,a);
   if(status)status.textContent='Market Intelligence connected · MT5 · EURUSD '+tf;
  }catch(e){set('miPrice','—');set('miBias','UNAVAILABLE');set('miVol','—');set('miConfidence','—');if(chart)chart.innerHTML='<div class="mt5-empty">MT5 market data unavailable · no invented metrics</div>';if(status)status.textContent='MT5 market data unavailable · no invented metrics';}
  finally{refresh.disabled=false;refresh.textContent='Actualizar análisis';}
 }
 function emaSeries(values,period){if(values.length<period)return[];let v=values.slice(0,period).reduce((a,b)=>a+b,0)/period;const a=2/(period+1),out=new Array(values.length).fill(null);out[period-1]=v;for(let i=period;i<values.length;i++){v=a*values[i]+(1-a)*v;out[i]=v;}return out;}
 function drawMT5Chart(container,candles,analysis){
  if(!container)return;container.innerHTML='';container.classList.add('mt5-chart');ensureToolbar(container);const visible=candles.slice(-zoom),W=Math.max(container.clientWidth||760,560),H=330,canvas=document.createElement('canvas');canvas.width=W*2;canvas.height=H*2;canvas.style.width='100%';canvas.style.height=H+'px';container.appendChild(canvas);
  const ctx=canvas.getContext('2d');ctx.scale(2,2);const w=W,h=H,p={l:58,r:72,t:26,b:32},hi=Math.max(...visible.map(c=>Number(c.high))),lo=Math.min(...visible.map(c=>Number(c.low))),pad=(hi-lo||1)*.06,top=hi+pad,bot=lo-pad,span=top-bot,y=v=>p.t+(top-v)/span*(h-p.t-p.b),step=(w-p.l-p.r)/visible.length,body=Math.max(3,step*.62);
  ctx.font='10px Inter,system-ui,sans-serif';ctx.lineWidth=1;ctx.textAlign='right';
  for(let i=0;i<=6;i++){const yy=p.t+i*(h-p.t-p.b)/6,val=top-i*span/6;ctx.strokeStyle='#18222d';ctx.beginPath();ctx.moveTo(p.l,yy);ctx.lineTo(w-p.r,yy);ctx.stroke();ctx.fillStyle='#7d8997';ctx.fillText(val.toFixed(5),w-6,yy+3);}
  for(let i=0;i<visible.length;i+=Math.max(1,Math.ceil(visible.length/8))){const x=p.l+i*step+step/2;ctx.strokeStyle='#111a23';ctx.beginPath();ctx.moveTo(x,p.t);ctx.lineTo(x,h-p.b);ctx.stroke();ctx.fillStyle='#697687';ctx.textAlign='center';const d=visible[i].time?new Date(Number(visible[i].time)*1000):null;ctx.fillText(d&&!isNaN(d)?d.toLocaleTimeString([], {hour:'2-digit',minute:'2-digit'}):String(i+1),x,h-10);}
  visible.forEach((c,i)=>{const o=Number(c.open),cl=Number(c.close),hh=Number(c.high),ll=Number(c.low),x=p.l+i*step+step/2,up=cl>=o;ctx.strokeStyle=up?'#52e6a2':'#ff7272';ctx.fillStyle=ctx.strokeStyle;ctx.beginPath();ctx.moveTo(x,y(hh));ctx.lineTo(x,y(ll));ctx.stroke();const a=y(Math.max(o,cl)),b=y(Math.min(o,cl));ctx.fillRect(x-body/2,a,body,Math.max(2,b-a));if(body>5){ctx.strokeStyle=up?'#8af2c2':'#ff9a9a';ctx.strokeRect(x-body/2,a,body,Math.max(2,b-a));}});
  const closes=visible.map(c=>Number(c.close)),e9=emaSeries(closes,9),e21=emaSeries(closes,21);function line(series,dash,label,stroke){ctx.setLineDash(dash);ctx.strokeStyle=stroke;ctx.lineWidth=1.5;ctx.beginPath();let started=false;series.forEach((v,i)=>{if(v==null)return;const x=p.l+i*step+step/2;if(!started){ctx.moveTo(x,y(v));started=true;}else ctx.lineTo(x,y(v));});ctx.stroke();ctx.setLineDash([]);if(series.length){const v=series[series.length-1];if(v!=null){ctx.fillStyle=stroke;ctx.textAlign='left';ctx.font='10px Inter,system-ui,sans-serif';ctx.fillText(label+' '+v.toFixed(5),p.l+5,y(v)-5);}}}
  line(e9,[5,3],'EMA 9','#78a7ff');line(e21,[7,4],'EMA 21','#f2c76d');
  ctx.fillStyle='#edf3f8';ctx.textAlign='left';ctx.font='bold 11px Inter,system-ui,sans-serif';ctx.fillText('EURUSD · '+currentTimeframe+' · MT5',p.l,14);ctx.font='10px Inter,system-ui,sans-serif';ctx.fillStyle='#7d8997';ctx.fillText('Candles '+visible.length+' · EMA 9/21 · Crosshair · OHLC',p.l+170,14);
  const cross={x:-1,y:-1};const tip=document.createElement('div');tip.className='mt5-tooltip';container.appendChild(tip);function redrawCross(){drawBase();if(cross.x<0)return;ctx.strokeStyle='#657487';ctx.setLineDash([3,3]);ctx.beginPath();ctx.moveTo(cross.x,p.t);ctx.lineTo(cross.x,h-p.b);ctx.stroke();ctx.beginPath();ctx.moveTo(p.l,cross.y);ctx.lineTo(w-p.r,cross.y);ctx.stroke();ctx.setLineDash([]);}
  function drawBase(){/* canvas is redrawn by a compact recursive-safe snapshot below */}
  canvas.addEventListener('mousemove',ev=>{const r=canvas.getBoundingClientRect(),mx=(ev.clientX-r.left)*W/r.width,my=(ev.clientY-r.top)*H/r.height,i=Math.max(0,Math.min(visible.length-1,Math.floor((mx-p.l)/step)));if(mx<p.l||mx>w-p.r){tip.style.display='none';return;}cross.x=p.l+i*step+step/2;cross.y=Math.max(p.t,Math.min(h-p.b,my));const c=visible[i],vals=[c.open,c.high,c.low,c.close].map(Number);tip.style.display='block';tip.style.left=Math.min(Math.max(cross.x,80),w-150)+'px';tip.style.top=Math.max(32,cross.y-65)+'px';tip.innerHTML='<b>'+currentTimeframe+'</b><br>O '+vals[0].toFixed(5)+' · H '+vals[1].toFixed(5)+'<br>L '+vals[2].toFixed(5)+' · C '+vals[3].toFixed(5);});
  canvas.addEventListener('mouseleave',()=>{tip.style.display='none';});
 }
 setTimeout(()=>{const chart=document.getElementById('marketChart');if(chart)ensureToolbar(chart);},50);
})();
</script>'''

RESEARCH_WIRING = '''<script>
(function(){
 const base=()=>((window.SBT_API_URL||localStorage.getItem('sbt_api_base')||'').replace(/\\/$/,''));
 function wireResearch(){
  const page=document.getElementById('research');if(!page||page.dataset.sbtResearchWired)return;page.dataset.sbtResearchWired='1';
  const card=document.createElement('div');card.className='card';card.style.marginTop='17px';card.innerHTML='<h3>Research execution</h3><p class="sub">Conecta esta pantalla con SBT. La investigación actual usa un fixture sintético determinista; no representa historial de mercado.</p><div class="form"><label>Pregunta de investigación<input id="sbtResearchPrompt" value="Analiza la estructura, tendencia, SMC y riesgo de EURUSD"></label><label>Modo<select id="sbtResearchMode"><option value="research-only">Research-only</option></select></label></div><div class="toolbar" style="margin-top:12px"><button class="btn primary" id="sbtRunResearch">Ejecutar investigación</button></div><div class="result" id="sbtResearchResult"></div>';page.appendChild(card);
  document.getElementById('sbtRunResearch').addEventListener('click',async()=>{const btn=document.getElementById('sbtRunResearch'),out=document.getElementById('sbtResearchResult');btn.disabled=true;btn.textContent='Investigando…';out.style.display='block';out.textContent='Ejecutando SBT research-only…';try{const r=await fetch(base()+'/api/v1/capabilities/delegate',{method:'POST',headers:{'Content-Type':'application/json','Accept':'application/json'},body:JSON.stringify({contract:'sbt-v1',capability:'sbt',message:document.getElementById('sbtResearchPrompt').value,source:'bitey-sbt-web',mode:'research-only'})});if(!r.ok)throw new Error('API HTTP '+r.status);const d=await r.json();const x=d.research||{};out.textContent='RESEARCH COMPLETADO · instrumento '+(x.instrument||'SYNTH')+' · fixture '+(x.fixture||'unknown')+' · estrategia '+((x.backtest||{}).strategy||'—')+'. No se enviaron órdenes. '+(d.execution||{}).broker_orders+' broker orders.';}catch(e){out.textContent='Research unavailable: '+e.message+'. No se muestran resultados inventados.';}finally{btn.disabled=false;btn.textContent='Ejecutar investigación';}});
 }
 document.addEventListener('click',e=>{const nav=e.target.closest('[data-page="research"]');if(nav)setTimeout(wireResearch,0);});setTimeout(wireResearch,100);
})();
</script>'''

BOT_WIRING = '''<script>
(function(){
 const base=()=>((window.SBT_API_URL||localStorage.getItem('sbt_api_base')||'').replace(/\\/$/,''));
 function wireBots(){
  const page=document.getElementById('bots');if(!page||page.dataset.sbtBotsWired)return;page.dataset.sbtBotsWired='1';
  const card=document.createElement('div');card.className='card';card.style.marginTop='17px';card.innerHTML='<h3>Bot Lab · Backend</h3><p class="sub">Perfiles, señales y backtest ejecutados por el backend SBT. Los resultados no autorizan trading real.</p><div id="sbtBotsList" class="choice"></div><div class="result" id="sbtBotResult"></div>';page.appendChild(card);
  const list=document.getElementById('sbtBotsList'),out=document.getElementById('sbtBotResult');
  (async()=>{try{const r=await fetch(base()+'/api/v1/bot-profiles');if(!r.ok)throw new Error('API HTTP '+r.status);const profiles=await r.json();list.innerHTML=profiles.map(p=>'<button data-profile="'+p.id+'"><strong>'+p.name+'</strong><span>'+p.short_description+'</span></button>').join('');list.querySelectorAll('[data-profile]').forEach(b=>b.addEventListener('click',()=>runBot(b.dataset.profile)));}catch(e){list.innerHTML='<span class="small">Bot profiles unavailable: '+e.message+'</span>';}})();
  async function runBot(id){out.style.display='block';out.textContent='Cargando perfil, market data y ejecutando estrategia…';try{const [pr,cr]=await Promise.all([fetch(base()+'/api/v1/bot-profiles/'+id),fetch(base()+'/api/v1/market/candles/EURUSD?timeframe=M5&limit=100')]);if(!pr.ok||!cr.ok)throw new Error('Backend market/profile unavailable');const p=await pr.json(),cd=await cr.json(),candles=Array.isArray(cd.candles)?cd.candles:[];const prices=candles.map(c=>Number(c.close)).filter(Number.isFinite);if(prices.length<30)throw new Error('Insuficientes velas reales para estrategia');const [sr,br,rr]=await Promise.all([fetch(base()+'/api/v1/strategy/signal',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({symbol:'EURUSD',prices})}),fetch(base()+'/api/v1/backtest',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({prices,initial_capital:10000,fast_window:10,slow_window:30,fee_pct:0.001})}),fetch(base()+'/api/v1/bot-profiles/'+id+'/risk-preview?capital=10000')]);if(!sr.ok||!br.ok||!rr.ok)throw new Error('Strategy/backtest/risk API failure');const s=await sr.json(),b=await br.json(),risk=await rr.json();out.textContent='BOT '+p.name+' · señal '+String(s.action).toUpperCase()+' · confianza '+(Number(s.confidence)*100).toFixed(1)+'% · backtest P/L '+Number(b.total_pnl||b.realized_pnl||0).toFixed(2)+' · posición máxima R$ '+Number(risk.max_position_value).toFixed(2)+' · pérdida configurada por trade R$ '+Number(risk.configured_loss_per_trade).toFixed(2)+'. Datos: '+prices.length+' cierres M5 reales. Sin órdenes live.';}catch(e){out.textContent='Bot Lab unavailable: '+e.message+'. No se muestran métricas inventadas.';}}
 }
 document.addEventListener('click',e=>{const nav=e.target.closest('[data-page="bots"]');if(nav)setTimeout(wireBots,0);});setTimeout(wireBots,100);
})();
</script>'''

CHART_STYLE = '''<style>
#marketChart.mt5-chart{height:330px;min-height:330px;padding:0;display:block;background:linear-gradient(180deg,#070c12,#05090e);border:1px solid #263342;border-radius:10px;overflow:visible;position:relative}
#marketChart.mt5-chart canvas{display:block;width:100%;height:330px;cursor:crosshair}
.mt5-toolbar{display:flex;justify-content:space-between;align-items:center;gap:10px;flex-wrap:wrap;margin:10px 0 8px;padding:7px 9px;background:#080e15;border:1px solid #1e2936;border-radius:9px;font-size:11px}.mt5-group{display:flex;align-items:center;gap:4px}.mt5-group b{margin-right:6px;color:#edf3f8}.mt5-group button{border:1px solid #263342;background:#0b121a;color:#9ca9b8;border-radius:6px;padding:5px 8px}.mt5-group button:hover,.mt5-group button.active{color:#fff;border-color:#52e6a2;background:#102119}.mt5-live{margin-left:7px;color:#52e6a2;font-size:10px}.mt5-tooltip{position:absolute;display:none;z-index:5;pointer-events:none;min-width:140px;padding:7px 9px;border:1px solid #3a4858;border-radius:7px;background:#071019ee;color:#dfe8f0;font:10px Inter,system-ui,sans-serif;box-shadow:0 8px 25px #0008}.mt5-empty{height:100%;display:grid;place-items:center;color:#8491a2;font-size:12px}
</style>'''

class Handler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
        self.send_header("Pragma", "no-cache")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("Referrer-Policy", "strict-origin-when-cross-origin")
        self.send_header("Permissions-Policy", "camera=(), microphone=(), geolocation=()")
        super().end_headers()

    def do_GET(self):
        if self.path.split("?",1)[0]=="/" and (self.headers.get("Accept","").find("text/html")>=0 or self.path=="/"):
            index=(ROOT/"index.html").read_text(encoding="utf-8")
            if "window.SBT_API_URL" not in index:index=index.replace("<head>","<head>"+API_BOOTSTRAP,1)
            marker='<section class="page" id="risk">'
            if marker in index and "bitey-ia-shortcut" not in index:index=index.replace(marker,marker+BITEY_IA_WIDGET,1)
            if "validation/virtual" not in index:index=index.replace("</body>",VALIDATION_WIRING+"</body>",1)
            if "sbt/market-intelligence/analyze" not in index:index=index.replace("</body>",CHART_STYLE+MARKET_WIRING+"</body>",1)
            if "api/v1/capabilities/delegate" not in index:index=index.replace("</body>",RESEARCH_WIRING+BOT_WIRING+"</body>",1)
            body=index.encode("utf-8");self.send_response(200);self.send_header("Content-Type","text/html; charset=utf-8");self.send_header("Content-Length",str(len(body)));self.end_headers();self.wfile.write(body);return
        super().do_GET()

ThreadingHTTPServer(("0.0.0.0",port),Handler).serve_forever()
