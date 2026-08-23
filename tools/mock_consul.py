#!/usr/bin/env python3
"""Mock Consul agent for the t16 registry spec.

Records every request line ("METHOD path") to <log>, answers:
  * PUT /v1/agent/service/register        -> 200 {}
  * PUT /v1/agent/check/pass/service:*    -> 200 {}
  * PUT /v1/agent/service/deregister/*    -> 200 {}
  * GET/PUT /v1/health/service/modelmirrors?passing=true -> 200, body
    read fresh from <discover> (so tests can flip discovery results).

Usage: mock_consul.py <portfile> <log> <discover>
Prints nothing; writes the bound port to <portfile> first line.
"""
import http.server
import json
import socket
import sys
import threading


def main():
    portfile, log, discover = sys.argv[1], sys.argv[2], sys.argv[3]

    class H(http.server.BaseHTTPRequestHandler):
        # HTTP/1.0-style: close the connection after each response so
        # the Lean one-shot client (read-to-EOF) completes promptly

        def _record(self):
            with open(log, "a") as f:
                f.write("%s %s\n" % (self.command, self.path))

        def _read_body(self):
            n = int(self.headers.get("Content-Length", "0"))
            return self.rfile.read(n) if n else b""

        def _reply(self, body=b"{}"):
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_PUT(self):
            self._record()
            self._read_body()
            self._reply()

        def do_GET(self):
            self._record()
            if self.path.startswith("/v1/health/service/"):
                try:
                    with open(discover) as f:
                        body = f.read().encode()
                except OSError:
                    body = b"[]"
                self._reply(body)
            else:
                self._reply()

        def log_message(self, *a):
            pass

    class T(http.server.ThreadingHTTPServer):
        daemon_threads = True
        allow_reuse_address = True

    httpd = T(("127.0.0.1", 0), H)
    port = httpd.server_address[1]
    with open(portfile, "w") as f:
        f.write(str(port))
    sys.stderr.write("mock consul on %d\n" % port)
    httpd.serve_forever()


if __name__ == "__main__":
    main()