#!/usr/bin/env python3
"""Isolated public-health contract fixture. Never contacts production."""

import json
import os
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def start_server(status, body):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path != "/api/v1/public/health":
                self.send_error(404)
                return
            self.send_response(status)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *_args):
            return

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


def main():
    cases = {
        "plain": (200, b"OK"),
        "whitespace": (200, b" \nOK\r\n "),
        "wrong_status": (503, b"OK"),
        "wrong_body": (200, b"NOT OK"),
    }
    servers = {name: start_server(*response) for name, response in cases.items()}
    ready_file = os.environ["HEALTH_FIXTURE_READY_FILE"]
    with open(ready_file, "w", encoding="utf-8") as handle:
        json.dump({name: "http://127.0.0.1:%d" % server.server_port
                   for name, server in servers.items()}, handle)
    try:
        time.sleep(30)
    finally:
        for server in servers.values():
            server.shutdown()


if __name__ == "__main__":
    main()
