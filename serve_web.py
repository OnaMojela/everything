#!/usr/bin/env python3
"""Serve the built web app locally with the headers a real host would send.

    flutter build web --release
    python serve_web.py            # then open http://localhost:8099

Cross-origin isolation headers let the database use OPFS instead of falling
back to IndexedDB. Everything still works without them, just a little slower.
"""

import functools
import http.server
import socketserver
import sys
from pathlib import Path

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8099
ROOT = Path(__file__).parent / "build" / "web"


class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        if self.path.endswith((".html", "/", "flutter_bootstrap.js",
                               "flutter_service_worker.js")):
            self.send_header("Cache-Control", "no-cache")
        super().end_headers()

    def log_message(self, fmt, *args):  # quieter output
        pass


def main():
    if not ROOT.exists():
        sys.exit("build/web not found — run: flutter build web --release")
    handler = functools.partial(Handler, directory=str(ROOT))
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("", PORT), handler) as httpd:
        print(f"Everything is running at http://localhost:{PORT}")
        print("Press Ctrl+C to stop.")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nStopped.")


if __name__ == "__main__":
    main()
