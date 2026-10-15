#!/usr/bin/env python3
"""Bounded actual-CLI JSONL framing checks; no model checker is started."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import socket
import ssl
import struct
import subprocess
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[1]
LIMIT = 65535
DEADLINE = 8
VALID = {"proto_step": "spec_validated", "result": "valid"}
TRACE = {"vars": ["x"], "params": [], "states": [{"x": {"#bigint": "0"}}]}
DONE = {"proto_step": "gen_traces_done", "itfTracePaths": [], "itfTraces": [TRACE]}


def encode(value: dict) -> bytes:
    return json.dumps(value, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def padded(size: int, *, multibyte: bool = False) -> bytes:
    value = {**VALID, "padding": "界" if multibyte else ""}
    value["padding"] += "x" * (size - len(encode(value)))
    payload = encode(value)
    assert len(payload) == size
    return payload


def make_pki(root: Path) -> tuple[ssl.SSLContext, str]:
    def openssl(*args: str) -> bytes:
        return subprocess.run(["openssl", *args], check=True, capture_output=True,
                              timeout=15).stdout
    openssl("req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "2",
            "-subj", "/CN=Framing CA", "-addext", "basicConstraints=critical,CA:TRUE",
            "-keyout", str(root / "ca.key"), "-out", str(root / "ca.crt"))
    for name, usage in (("server", "serverAuth"), ("client", "clientAuth")):
        openssl("req", "-newkey", "rsa:2048", "-nodes", "-subj", f"/CN={name}",
                "-keyout", str(root / f"{name}.key"), "-out", str(root / f"{name}.csr"))
        ext = root / f"{name}.ext"
        ext.write_text(f"extendedKeyUsage={usage}\n" +
                       ("subjectAltName=DNS:localhost\n" if name == "server" else ""))
        openssl("x509", "-req", "-in", str(root / f"{name}.csr"), "-CA", str(root / "ca.crt"),
                "-CAkey", str(root / "ca.key"), "-CAcreateserial", "-days", "2",
                "-extfile", str(ext), "-out", str(root / f"{name}.crt"))
        os.chmod(root / f"{name}.key", 0o600)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = context.maximum_version = ssl.TLSVersion.TLSv1_3
    context.verify_mode = ssl.CERT_REQUIRED
    context.load_verify_locations(root / "ca.crt")
    context.load_cert_chain(root / "server.crt", root / "server.key")
    der = openssl("x509", "-in", str(root / "server.crt"), "-outform", "DER")
    return context, hashlib.sha256(der).hexdigest()


def run_case(binary: Path, root: Path, label: str, chunks: list[bytes], expected: int,
             diagnostic: str = "", *, context: ssl.SSLContext | None = None,
             pin: str = "", close: str = "clean", capture: bool = False,
             wrong_host: bool = False) -> None:
    errors: list[str] = []
    connections: list[socket.socket] = []
    requests: list[dict] = []
    output = root / label
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        listener.listen(1)
        listener.settimeout(DEADLINE)

        def serve() -> None:
            connection = None
            try:
                raw, _ = listener.accept()
                raw.settimeout(DEADLINE)
                connections.append(raw)
                connection = raw
                if context:
                    try:
                        connection = context.wrap_socket(raw, server_side=True)
                    except ssl.SSLError:
                        if wrong_host:
                            return
                        raise
                    connections.append(connection)
                    assert connection.version() == "TLSv1.3"
                    assert connection.getpeercert(), "mTLS peer did not authenticate"
                packet = bytearray()
                while not packet.endswith(b"\n") and len(packet) <= LIMIT + 1:
                    part = connection.recv(1)
                    assert part, "client closed before registration"
                    packet.extend(part)
                assert packet.endswith(b"\n") and len(packet) <= LIMIT + 1
                request = json.loads(packet)
                requests.append(request)
                assert request["proto_step"] == ("register_trace_gen" if capture else "register_validate")
                for chunk in chunks:
                    if chunk:
                        connection.sendall(chunk)
                        time.sleep(.01)
                if close == "abrupt":
                    # Detach bypasses SSLSocket's close_notify path.
                    # socket.close handles Winsock SOCKETs as well as POSIX fds.
                    socket.close(connection.detach())
                elif close == "reset":
                    linger = struct.pack("hh" if os.name == "nt" else "ii", 1, 0)
                    connection.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, linger)
                    connection.close()
                elif context:
                    # unwrap sends an actual close_notify before waiting for the
                    # client's reply. The CLI may close its process socket first.
                    try:
                        connection.settimeout(3)
                        unwrapped = connection.unwrap()
                        unwrapped.close()
                    except OSError:
                        pass
                else:
                    try:
                        connection.shutdown(socket.SHUT_WR)
                    except OSError:
                        pass
                    try:
                        assert connection.recv(1) == b"", "unexpected follow-up flow write"
                    except ConnectionResetError:
                        pass  # An oversized/unread tail may cause a TCP reset on exit.
            except Exception as error:
                errors.append(repr(error))
            finally:
                if connection is not None:
                    connection.close()

        thread = threading.Thread(target=serve, name=f"framing-{label}", daemon=True)
        thread.start()
        command = [str(binary), "trace-gen" if capture else "validate", "--host",
                   "127.0.0.1" if not context or wrong_host else "localhost",
                   "--port", str(listener.getsockname()[1]), "--spec", str(root / "Main.tla")]
        if capture:
            command += ["--out", str(output)]
        if context:
            command += ["--tls", "--cert", str(root / "client.crt"), "--key", str(root / "client.key"),
                        "--ca", str(root / "ca.crt"), "--pin", pin]
        try:
            completed = subprocess.run(command, capture_output=True, text=True, timeout=15)
            thread.join(DEADLINE + 1)
        finally:
            for connection in connections:
                try:
                    connection.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass
                connection.close()
            listener.close()
            thread.join(DEADLINE + 1)
        assert not thread.is_alive() and not errors, (label, errors)
        assert completed.returncode == expected, (label, completed)
        assert diagnostic in completed.stderr, (label, completed)
        if expected == 0:
            if capture:
                assert json.loads((output / "trace-0.itf.json").read_text()) == TRACE
            else:
                assert completed.stdout == "VALID\n", (label, completed)
        else:
            assert "VALID" not in completed.stdout, (label, completed)
            assert not output.exists(), (label, "failed capture was published")
        assert len(requests) == (0 if wrong_host else 1), (label, requests)
        print(f"ok: {label}")


def stdio_cases(binary: Path) -> None:
    # An unexpected first message produces a protocol_error without model work.
    message = encode({"proto_step": "report_state", "state": {}})
    for suffix in (b"\n", b"\r\n"):
        completed = subprocess.run([str(binary)], input=message + suffix, capture_output=True, timeout=10)
        assert completed.returncode == 0 and b'"protocol_error"' in completed.stdout, completed
    for fragment in (message, message + b"\r", b"{\"proto_step\":"):
        completed = subprocess.run([str(binary)], input=fragment, capture_output=True, timeout=10)
        assert completed.returncode != 0 and b"unterminated" in completed.stderr, completed
        assert not completed.stdout, completed
    completed = subprocess.run([str(binary)], input=b"", capture_output=True, timeout=10)
    assert completed.returncode == 0 and not completed.stdout, completed
    print("ok: stdio LF/CRLF, partial EOF, bare CR and empty EOF")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mirror", type=Path, default=ROOT / ".lake/build/bin/mirror")
    args = parser.parse_args()
    binary = args.mirror.resolve(strict=True)
    with tempfile.TemporaryDirectory(prefix="mirrors-client-framing-") as directory:
        root = Path(directory)
        (root / "Main.tla").write_text("---- MODULE Main ----\n====\n")
        context, pin = make_pki(root)
        valid = encode(VALID)
        for transport, tls in (("tcp", None), ("tls", context)):
            def case(name: str, chunks: list[bytes], expected: int = 0, diagnostic: str = "", **kwargs) -> None:
                run_case(binary, root, f"{transport}-{name}", chunks, expected, diagnostic,
                         context=tls, pin=pin, **kwargs)
            case("lf", [valid + b"\n"])
            case("split-lf", [valid, b"\n"])
            case("crlf", [valid + b"\r", b"\n"])
            case("coalesced-next-fragment", [valid + b"\n" + b"x" * LIMIT])
            case("empty-eof", [], 2, "connection closed")
            case("complete-json-eof", [valid], 2, "unterminated")
            case("partial-json-eof", [valid[:12]], 2, "unterminated")
            case("bare-cr-eof", [valid + b"\r"], 2, "unterminated")
            for size in (LIMIT - 1, LIMIT):
                case(f"boundary-{size}", [padded(size) + b"\n"])
            utf8 = padded(LIMIT, multibyte=True)
            split = utf8.index("界".encode()) + 1
            case("split-multibyte-boundary", [utf8[:split], utf8[split:], b"\n"])
            case("oversize", [padded(LIMIT + 1) + b"\n"], 2, "65535")
            case("invalid-utf8", [b"\xff\n"], 2, "UTF-8")
            case("trace-lf", [encode(DONE) + b"\n"], capture=True)
            case("trace-eof", [encode(DONE)], 2, "unterminated", capture=True)
            case("read-failure-fragment", [valid], 2, f"{transport.upper()} read failed",
                 close="abrupt" if tls else "reset")
            if tls:
                case("read-failure-empty", [], 2, "TLS read failed", close="abrupt")
                case("san-mismatch", [], 2, wrong_host=True)
        stdio_cases(binary)
    print("CLIENT FRAMING CLI GREEN (TCP, authenticated TLS 1.3 and stdio; owned peers stopped)")


if __name__ == "__main__":
    main()
