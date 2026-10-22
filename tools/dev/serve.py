#!/usr/bin/env python3
"""Tiny static server for the Ninja Saga preservation arcade.

Serves the workspace root so that SWFs keep their original relative paths
(the game panels load their shared libraries by relative URL).
"""
import http.server
import socketserver
import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
PORT = int(os.environ.get("PORT", "8123"))


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".swf": "application/x-shockwave-flash",
        ".wasm": "application/wasm",
        ".mjs": "text/javascript",
    }

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        self.send_header("Access-Control-Allow-Origin", "*")
        super().end_headers()

    def log_message(self, fmt, *args):
        if os.environ.get("QUIET") != "1":
            sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))


if __name__ == "__main__":
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("127.0.0.1", PORT), Handler) as httpd:
        print(f"Ninja Saga arcade running at http://127.0.0.1:{PORT}/arcade/", flush=True)
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            pass
