import os
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path

ROOT = Path(__file__).resolve().parent
os.chdir(ROOT)
port = int(os.environ.get("PORT", "8080"))

class Handler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-cache")
        self.send_header("X-Content-Type-Options", "nosniff")
        super().end_headers()

ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
