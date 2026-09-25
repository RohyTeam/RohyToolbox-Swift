#!/usr/bin/env python3
"""Minimal static file server with HTTP Range support and throttled output.

Used by DownloadResumeTests to exercise segmented download, pause and resume
against a real HTTP server. Serves ./test.bin (generated on first run).
"""

import http.server
import os
import re
import socketserver
import time

PORT = 18743
FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "test.bin")
CHUNK = 64 * 1024
THROTTLE_SECONDS = 0.05

if not os.path.exists(FILE):
    with open(FILE, "wb") as f:
        f.write(os.urandom(12 * 1024 * 1024))

SIZE = os.path.getsize(FILE)


class Handler(http.server.BaseHTTPRequestHandler):
    def do_HEAD(self):
        self.send_response(200)
        self.send_header("Content-Length", str(SIZE))
        self.send_header("Accept-Ranges", "bytes")
        self.end_headers()

    def _send_json(self, name):
        with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), name), "rb") as f:
            body = f.read()
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_page(self):
        body = (
            "<html><body style='font-size:48px'>"
            "<p><a id='dl' href='/test.bin' download>下载文件</a></p>"
            "<p><a id='dlblank' href='/protected.bin' target='_blank'>新标签下载</a></p>"
            "</body></html>"
        ).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path in ("/", "/index.html"):
            self._send_page()
            return
        if self.path == "/apps.json":
            with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "apps.json"), "rb") as f:
                body = f.read()
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        # /app/{id}/versions.json -> full version list fixture
        if re.fullmatch(r"/app/[^/]+/versions\.json", self.path):
            self._send_json("app_versions.json")
            return
        # /app/{id}/official/{version}.json and /app/{id}/{source}/{version}.json
        if re.fullmatch(r"/app/[^/]+/[^/]+/[^/]+\.json", self.path):
            self._send_json("version.json")
            return
        if self.path == "/protected.bin" and not self.headers.get("Referer"):
            # Anti-leech: no Referer -> redirect to the homepage.
            self.send_response(302)
            self.send_header("Location", "/")
            self.end_headers()
            return
        start, end = 0, SIZE - 1
        range_header = self.headers.get("Range")
        if range_header:
            bounds = range_header.split("=", 1)[1].split("-", 1)
            start = int(bounds[0])
            end = int(bounds[1]) if bounds[1] else SIZE - 1
            self.send_response(206)
            self.send_header("Content-Range", f"bytes {start}-{end}/{SIZE}")
        else:
            self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(end - start + 1))
        self.send_header("Accept-Ranges", "bytes")
        self.end_headers()

        with open(FILE, "rb") as f:
            f.seek(start)
            remaining = end - start + 1
            while remaining > 0:
                chunk = f.read(min(CHUNK, remaining))
                if not chunk:
                    break
                try:
                    self.wfile.write(chunk)
                except (BrokenPipeError, ConnectionResetError):
                    return
                remaining -= len(chunk)
                time.sleep(THROTTLE_SECONDS)

    def log_message(self, *args):
        print(f"[server] {self.command} {self.path} referer={self.headers.get('Referer')}", flush=True)


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


if __name__ == "__main__":
    print(f"Serving {FILE} ({SIZE} bytes) on http://127.0.0.1:{PORT}")
    Server(("127.0.0.1", PORT), Handler).serve_forever()
