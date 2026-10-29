#!/usr/bin/env python3
"""Bounded loopback fixtures for HTTP framing and concurrent connection tests."""
import socketserver
import threading
import time


race = threading.Barrier(8, timeout=10)


class Handler(socketserver.StreamRequestHandler):
    def handle(self):
        self.request.settimeout(15)
        while True:
            first = self.rfile.readline()
            if not first:
                return
            headers = {}
            while (line := self.rfile.readline()) != b"\r\n":
                if not line:
                    return
                key, value = line.split(b":", 1)
                headers[key.lower()] = value.strip().lower()
            # Consume exactly the advertised bytes. Echoing all bytes from the
            # first recv would mask an incorrect Content-Length.
            length = int(headers.get(b"content-length", b"0"))
            if length > 65536:
                return
            body = self.rfile.read(length)
            path = first.split(b" ")[1]
            if path == b"/silent":
                time.sleep(2)
                return
            if path == b"/race":
                try:
                    race.wait()
                except threading.BrokenBarrierError:
                    return
            close = headers.get(b"connection") == b"close"
            connection = b"close" if close else b"keep-alive"
            head = b"HTTP/1.1 200 OK\r\nConnection: " + connection + b"\r\n"
            if path == b"/chunked":
                head += b"Transfer-Encoding: chunked\r\n\r\n"
                mid = max(1, len(body) // 2)
                payload = head
                for part in (body[:mid], body[mid:]):
                    payload += ("%x\r\n" % len(part)).encode() + part + b"\r\n"
                payload += b"0\r\n\r\n"
            else:
                payload = head + b"Content-Length: %d\r\n\r\n" % len(body) + body
            self.wfile.write(payload)
            self.wfile.flush()
            if close:
                return


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


if __name__ == "__main__":
    with Server(("127.0.0.1", 0), Handler) as server:
        print(server.server_address[1], flush=True)
        server.serve_forever()
