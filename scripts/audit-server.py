import base64
import json
import io
import wave
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

counts = {}
lock = threading.Lock()
icon = base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=')

class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def do_GET(self):
        path = self.path.split('?')[0]
        with lock:
            counts[path] = counts.get(path, 0) + 1
        if path == '/counts':
            with lock:
                payload = json.dumps(counts).encode()
            return self.respond(payload, 'application/json')
        if path == '/redirect':
            self.send_response(302)
            self.send_header('Location', '/redirect-target')
            self.end_headers()
            return
        if path == '/icon.png':
            return self.respond(icon, 'image/png')
        if path == '/oversized.png':
            return self.respond(b'x' * (600 * 1024), 'image/png')
        if path == '/bad-icon':
            return self.respond(b'<html>not an image</html>', 'text/html')
        if path == '/tone.wav':
            buffer = io.BytesIO()
            with wave.open(buffer, 'wb') as audio:
                audio.setnchannels(1)
                audio.setsampwidth(2)
                audio.setframerate(8000)
                audio.writeframes(b'\0' * 16000)
            return self.respond(buffer.getvalue(), 'audio/wav')
        if path == '/download':
            return self.respond(b'audit download', 'application/octet-stream', {'Content-Disposition': 'attachment; filename="../../audit-download.txt"'})
        body = '''<!doctype html><html><head><title>Parsec audit fixture</title></head><body>
        <h1>Parsec: verificación local</h1><p>Seguridad, aislamiento y rendimiento.</p>
        <form action="/submitted"><input id="username" autocomplete="username"><input id="password" type="password" value="fixture-secret"><input id="card" autocomplete="cc-number" value="fixture-card"><input id="otp" autocomplete="one-time-code" value="fixture-code"><button id="submit">Enviar</button></form>
        <a id="link" href="/next">Siguiente</a><button id="custom" type="button">Acción de sitio</button>
        </body></html>'''
        self.respond(body.encode(), 'text/html; charset=utf-8')

    def do_POST(self):
        self.do_GET()

    def respond(self, data, content_type, headers=None):
        self.send_response(200)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(data)))
        for name, value in (headers or {}).items():
            self.send_header(name, value)
        self.end_headers()
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            return

server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
Path(sys.argv[1]).write_text(str(server.server_port))
server.serve_forever()
