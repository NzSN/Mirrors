#!/usr/bin/env python3
"""Loopback test peer for the t14 HTTP spike: one process serving
Content-Length echo, chunked echo, and a silent (timeout) endpoint."""
import socket, sys, time

srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", 0))
srv.listen(8)
sys.stdout.write(f"{srv.getsockname()[1]}\n")
sys.stdout.flush()

def read_request(conn):
    data = b""
    while b"\r\n\r\n" not in data:
        chunk = conn.recv(65536)
        if not chunk:
            return None, b""
        data += chunk
    head, rest = data.split(b"\r\n\r\n", 1)
    clen = 0
    for line in head.split(b"\r\n"):
        if line.lower().startswith(b"content-length:"):
            clen = int(line.split(b":")[1].strip())
    while len(rest) < clen:
        chunk = conn.recv(65536)
        if not chunk:
            break
        rest += chunk
    path = head.split(b"\r\n")[0].split(b" ")[1].decode()
    return path, rest

while True:
    conn, _ = srv.accept()
    conn.settimeout(5)
    path, body = read_request(conn)
    if path is None:
        conn.close()
        continue
    if path == "/silent":
        time.sleep(2.0)
        conn.close()
        continue
    if path == "/chunked":
        head = b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n"
        mid = max(1, len(body) // 2)
        payload = head
        for part in (body[:mid], body[mid:]):
            payload += ("%x\r\n" % len(part)).encode() + part + b"\r\n"
        payload += b"0\r\n\r\n"
    else:
        head = b"HTTP/1.1 200 OK\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % len(body)
        payload = head + body
    conn.sendall(payload)
    conn.close()
