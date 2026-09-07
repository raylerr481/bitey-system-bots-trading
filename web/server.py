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
  <span class="bitey-ia-arrow" aria-hidden="true">↗</span>
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
    event.preventDefault();
    event.stopImmediatePropagation();
    const base = (window.SBT_API_URL || localStorage.getItem('sbt_api_base') || '').replace(/\\/$/, '');
    const result = document.getElementById('testResult');
    const set = (id, value) => { const el = document.getElementById(id); if (el) el.textContent = value; };
    run.disabled = true;
    run.textContent = 'Ejecutando…';
    if (result) { result.style.display = 'block'; result.textContent = 'Ejecutando validación virtual reproducible…'; }
    try {
      const response = await fetch(base + '/api/v1/validation/virtual', { method: 'GET', headers: { 'Accept': 'application/json' } });
      if (!response.ok) throw new Error('API HTTP ' + response.status);
      const data = await response.json();
      set('testPnl', 'R$ ' + Number(data.realized_pnl).toFixed(2));
      set('testDd', Number(data.max_drawdown_pct).toFixed(2) + '%');
      set('testTrades', data.accepted_operations + ' aceptadas');
      set('testRejected', String(data.rejected_operations));
      if (result) {
        result.textContent = 'VALIDACIÓN COMPLETADA · ' + data.strategy + ' · ' + data.fixture + '. P/L R$ ' + Number(data.realized_pnl).toFixed(2) + ', drawdown ' + Number(data.max_drawdown_pct).toFixed(2) + '%, ' + data.accepted_operations + ' operaciones aceptadas y ' + data.rejected_operations + ' rechazadas. Dinero real: ' + data.real_money + '. Broker orders: ' + data.broker_orders + '.';
      }
      const status = document.getElementById('apiStatus');
      if (status) status.textContent = 'Virtual validation connected · live trading disabled';
    } catch (error) {
      if (result) result.textContent = 'No se pudo ejecutar la validación: ' + error.message + '. No se muestran métricas inventadas.';
      const status = document.getElementById('apiStatus');
      if (status) status.textContent = 'API validation unavailable · live trading disabled';
    } finally {
      run.disabled = false;
      run.textContent = 'Ejecutar prueba local';
    }
  }, true);
})();
</script>'''

MARKET_WIRING = '''<script>
(function () {
  const refresh = document.getElementById('refreshMarket');
  if (!refresh) return;
  refresh.addEventListener('click', async function (event) {
    event.preventDefault();
    event.stopImmediatePropagation();
    const base = (window.SBT_API_URL || localStorage.getItem('sbt_api_base') || '').replace(/\\/$/, '');
    const status = document.getElementById('apiStatus');
    const set = (id, value) => { const el = document.getElementById(id); if (el) el.textContent = value; };
    const chart = document.getElementById('marketChart');
    refresh.disabled = true;
    refresh.textContent = 'Analizando…';
    if (status) status.textContent = 'Consultando market data real…';
    try {
      const [quoteResponse, candlesResponse] = await Promise.all([
        fetch(base + '/api/v1/market/quote/EURUSD', { headers: { 'Accept': 'application/json' } }),
        fetch(base + '/api/v1/market/candles/EURUSD?timeframe=M5&limit=100', { headers: { 'Accept': 'application/json' } })
      ]);
      if (!quoteResponse.ok) throw new Error('Quote HTTP ' + quoteResponse.status);
      if (!candlesResponse.ok) throw new Error('Candles HTTP ' + candlesResponse.status);
      const quote = await quoteResponse.json();
      const candleData = await candlesResponse.json();
      const candles = Array.isArray(candleData) ? candleData : (Array.isArray(candleData.candles) ? candleData.candles : []);
      if (candles.length < 35) throw new Error('Solo hay ' + candles.length + ' velas; se requieren al menos 35');
      const analysisResponse = await fetch(base + '/api/v1/sbt/market-intelligence/analyze', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
        body: JSON.stringify({ symbol: 'EURUSD', timeframe: 'M5', candles, capital: 10000, language: 'es', event: 'market_structure', evidence: [] })
      });
      if (!analysisResponse.ok) throw new Error('Analysis HTTP ' + analysisResponse.status);
      const analysis = await analysisResponse.json();
      const price = quote.last ?? quote.bid ?? quote.ask;
      set('miPrice', price != null ? Number(price).toFixed(5) : '—');
      set('miBias', analysis.bias || 'NEUTRAL');
      const atr = analysis.technical && analysis.technical.atr ? analysis.technical.atr.value : null;
      set('miVol', atr != null ? Number(atr).toFixed(6) : '—');
      set('miConfidence', analysis.confidence != null ? (Number(analysis.confidence) * 100).toFixed(1) + '%' : '—');
      if (chart) {
        chart.innerHTML = '';
        const closes = candles.slice(-30).map(c => Number(c.close)).filter(Number.isFinite);
        if (closes.length) {
          const min = Math.min(...closes), max = Math.max(...closes), span = max - min || 1;
          closes.forEach(value => {
            const bar = document.createElement('div');
            bar.className = 'bar';
            bar.style.height = Math.max(8, ((value - min) / span) * 92 + 8) + '%';
            chart.appendChild(bar);
          });
        }
      }
      if (status) status.textContent = 'Market Intelligence connected · real MT5 data';
    } catch (error) {
      set('miPrice', '—');
      set('miBias', 'UNAVAILABLE');
      set('miVol', '—');
      set('miConfidence', '—');
      if (chart) chart.innerHTML = '';
      if (status) status.textContent = 'Market data unavailable · no invented metrics';
    } finally {
      refresh.disabled = false;
      refresh.textContent = 'Actualizar análisis';
    }
  }, true);
})();
</script>'''

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
        if self.path.split("?", 1)[0] == "/" and (self.headers.get("Accept", "").find("text/html") >= 0 or self.path == "/"):
            index = (ROOT / "index.html").read_text(encoding="utf-8")
            if "window.SBT_API_URL" not in index:
                index = index.replace("<head>", "<head>" + API_BOOTSTRAP, 1)
            marker = '<section class="page" id="risk">'
            if marker in index and "bitey-ia-shortcut" not in index:
                index = index.replace(marker, marker + BITEY_IA_WIDGET, 1)
            if "validation/virtual" not in index:
                index = index.replace("</body>", VALIDATION_WIRING + "</body>", 1)
            if "sbt/market-intelligence/analyze" not in index:
                index = index.replace("</body>", MARKET_WIRING + "</body>", 1)
            body = index.encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        super().do_GET()

ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
