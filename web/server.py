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
 refresh.addEventListener('click',async function(event){
  event.preventDefault();event.stopImmediatePropagation();
  const base=(window.SBT_API_URL||localStorage.getItem('sbt_api_base')||'').replace(/\\/$/,'');
  const status=document.getElementById('apiStatus'); const set=(id,v)=>{const e=document.getElementById(id);if(e)e.textContent=v;};
  const chart=document.getElementById('marketChart'); refresh.disabled=true;refresh.textContent='Analizando…';
  if(status)status.textContent='Consultando MT5 market data real…';
  try{
   const [qr,cr]=await Promise.all([
    fetch(base+'/api/v1/market/quote/EURUSD',{headers:{'Accept':'application/json'}}),
    fetch(base+'/api/v1/market/candles/EURUSD?timeframe=M5&limit=100',{headers:{'Accept':'application/json'}})
   ]);
   if(!qr.ok)throw new Error('Quote HTTP '+qr.status);if(!cr.ok)throw new Error('Candles HTTP '+cr.status);
   const q=await qr.json(),cd=await cr.json();const candles=Array.isArray(cd)?cd:(Array.isArray(cd.candles)?cd.candles:[]);
   if(candles.length<35)throw new Error('Solo hay '+candles.length+' velas; se requieren al menos 35');
   const ar=await fetch(base+'/api/v1/sbt/market-intelligence/analyze',{method:'POST',headers:{'Content-Type':'application/json','Accept':'application/json'},body:JSON.stringify({symbol:'EURUSD',timeframe:'M5',candles,capital:10000,language:'es',event:'market_structure',evidence:[]})});
   if(!ar.ok)throw new Error('Analysis HTTP '+ar.status); const a=await ar.json();
   const price=q.last??q.bid??q.ask;set('miPrice',price!=null?Number(price).toFixed(5):'—');set('miBias',a.bias||'NEUTRAL');
   const atr=a.technical&&a.technical.atr?a.technical.atr.value:null;set('miVol',atr!=null?Number(atr).toFixed(6):'—');set('miConfidence',a.confidence!=null?(Number(a.confidence)*100).toFixed(1)+'%':'—');
   drawMT5Chart(chart,candles,a);
   if(status)status.textContent='Market Intelligence connected · MT5 · EURUSD M5';
  }catch(e){set('miPrice','—');set('miBias','UNAVAILABLE');set('miVol','—');set('miConfidence','—');if(chart)chart.innerHTML='';if(status)status.textContent='MT5 market data unavailable · no invented metrics';}
  finally{refresh.disabled=false;refresh.textContent='Actualizar análisis';}
 },true);
 function drawMT5Chart(container,candles,analysis){
  if(!container)return;container.innerHTML='';container.classList.add('mt5-chart');
  const visible=candles.slice(-60);const W=Math.max(container.clientWidth||700,480),H=250;
  const canvas=document.createElement('canvas');canvas.width=W*2;canvas.height=H*2;canvas.style.width='100%';canvas.style.height=H+'px';canvas.setAttribute('aria-label','Gráfico de velas EURUSD M5');container.appendChild(canvas);
  const ctx=canvas.getContext('2d');ctx.scale(2,2);const w=W,h=H,p={l:48,r:54,t:18,b:28};
  const hi=Math.max(...visible.map(c=>Number(c.high))),lo=Math.min(...visible.map(c=>Number(c.low))),span=hi-lo||1;
  const y=v=>p.t+(hi-v)/span*(h-p.t-p.b), step=(w-p.l-p.r)/visible.length, body=Math.max(3,step*.58);
  ctx.font='10px Inter,system-ui,sans-serif';ctx.lineWidth=1;
  ctx.strokeStyle='#1e2936';ctx.fillStyle='#8491a2';ctx.textAlign='right';
  for(let i=0;i<=5;i++){const yy=p.t+i*(h-p.t-p.b)/5;const val=hi-i*span/5;ctx.beginPath();ctx.moveTo(p.l,yy);ctx.lineTo(w-p.r,yy);ctx.stroke();ctx.fillText(val.toFixed(5),w-5,yy+3);}
  visible.forEach((c,i)=>{const o=Number(c.open),cl=Number(c.close),hh=Number(c.high),ll=Number(c.low),x=p.l+i*step+step/2,up=cl>=o;ctx.strokeStyle=up?'#52e6a2':'#ff7272';ctx.fillStyle=ctx.strokeStyle;ctx.beginPath();ctx.moveTo(x,y(hh));ctx.lineTo(x,y(ll));ctx.stroke();const top=y(Math.max(o,cl)),bot=y(Math.min(o,cl));ctx.fillRect(x-body/2,top,body,Math.max(1,bot-top));});
  const ema=analysis&&analysis.technical&&analysis.technical.ema; if(ema&&ema.fast!=null&&ema.slow!=null){ctx.setLineDash([5,4]);ctx.strokeStyle='#78a7ff';ctx.beginPath();ctx.moveTo(p.l,y(ema.fast));ctx.lineTo(w-p.r,y(ema.fast));ctx.stroke();ctx.strokeStyle='#f2c76d';ctx.beginPath();ctx.moveTo(p.l,y(ema.slow));ctx.lineTo(w-p.r,y(ema.slow));ctx.stroke();ctx.setLineDash([]);}
  ctx.textAlign='left';ctx.fillStyle='#edf3f8';ctx.font='11px Inter,system-ui,sans-serif';ctx.fillText('EURUSD · M5 · MT5',p.l,12);ctx.fillStyle='#52e6a2';ctx.fillText('● BUY/UP',p.l+118,12);ctx.fillStyle='#ff7272';ctx.fillText('● SELL/DOWN',p.l+188,12);
  ctx.fillStyle='#8491a2';ctx.textAlign='center';ctx.fillText('Últimas '+visible.length+' velas · datos reales cuando MT5 está disponible',w/2,h-8);
 }
})();
</script>'''

CHART_STYLE = '''<style>
#marketChart.mt5-chart{height:250px;min-height:250px;padding:0;display:block;background:linear-gradient(180deg,#080d13,#060a0f);border:1px solid #1e2936;border-radius:10px;overflow:hidden;position:relative}
#marketChart.mt5-chart canvas{display:block;width:100%;height:250px}
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
            body=index.encode("utf-8");self.send_response(200);self.send_header("Content-Type","text/html; charset=utf-8");self.send_header("Content-Length",str(len(body)));self.end_headers();self.wfile.write(body);return
        super().do_GET()

ThreadingHTTPServer(("0.0.0.0",port),Handler).serve_forever()
