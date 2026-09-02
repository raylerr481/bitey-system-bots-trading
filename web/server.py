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
try { if (!localStorage.getItem('sbt_api_base')) localStorage.setItem('sbt_api_base', window.SBT_API_URL); } catch (_) {}
</script>'''

SBT_PROFILE_SCRIPT = '<script src="/sbt-profile.js" defer></script>'

class Handler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-cache")
        self.send_header("X-Content-Type-Options", "nosniff")
        super().end_headers()

    def do_GET(self):
        if self.path.split("?", 1)[0] == "/" and (self.headers.get("Accept", "").find("text/html") >= 0 or self.path == "/"):
            index = (ROOT / "index.html").read_text(encoding="utf-8")
            if "window.SBT_API_URL" not in index:
                index = index.replace("<head>", "<head>" + API_BOOTSTRAP, 1)
            if "/sbt-profile.js" not in index:
                index = index.replace("</head>", SBT_PROFILE_SCRIPT + "</head>", 1)
            marker = '<section class="page" id="risk">'
            if marker in index and "bitey-ia-shortcut" not in index:
                index = index.replace(marker, marker + BITEY_IA_WIDGET, 1)
            body = index.encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        super().do_GET()

ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
