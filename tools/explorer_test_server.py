#!/usr/bin/env python3
"""Scripted loopback RPC fixture. Never invokes a model checker."""
import json
import socketserver
import sys


class Handler(socketserver.StreamRequestHandler):
    def handle(self):
        self.request.settimeout(10)
        while self.rfile.readline():
            headers = {}
            while (line := self.rfile.readline()) != b"\r\n":
                if not line:
                    return
                key, value = line.split(b":", 1)
                headers[key.lower()] = value.strip()
            size = int(headers.get(b"content-length", b"0"))
            if not 0 < size <= 65535:
                return
            request = json.loads(self.rfile.read(size))
            method, params = request["method"], request["params"]
            with open(self.server.audit, "a", encoding="utf-8") as audit:
                audit.write(json.dumps(request) + "\n")
            mode = self.server.mode
            result = {"sessionId": "fixture", "snapshotId": self.server.steps}
            error = None
            if method == "health":
                self.server.health_calls += 1
                if mode == "drop-health" and self.server.health_calls == 1:
                    return
                result = {"status": "OK"}
            elif method == "loadSpec":
                # Noncontiguous IDs detect accidental index-zero assumptions.
                result["specParameters"] = {
                    "initTransitions": [{"index": 5, "labels": ["Init"]}],
                    "nextTransitions": [{"index": 9, "labels": ["Next"]}],
                    "stateInvariants": [{"index": 3, "labels": ["InvA"]},
                                        {"index": 7, "labels": ["InvB"]}],
                    "actionInvariants": [{"index": 11, "labels": ["ActionInv"]}],
                }
            elif method == "assumeTransition":
                initial = params["transitionId"] == 5
                status = ("DISABLED" if initial and mode == "disabled-init" else
                          "UNKNOWN" if initial and mode == "unknown-init" else
                          "UNKNOWN" if not initial and mode == "unknown-next" else "ENABLED")
                result.update(transitionId=params["transitionId"], status=status)
            elif method == "nextStep":
                self.server.steps += 1
                result.update(snapshotId=self.server.steps, newStepNo=self.server.steps)
                if mode == "drop-mutation" and self.server.steps == 1:
                    # Commit the mutation, then lose its response.
                    return
            elif method == "query":
                result["state"] = {"action_taken": "Init" if self.server.steps <= 1 else "Next", "x": 1}
                result["appliedSteps"] = self.server.steps
            elif method == "assumeState":
                result["status"] = ("DISABLED" if mode == "disabled-state" else
                                    "UNKNOWN" if mode == "unknown-state" else "ENABLED")
            elif method == "checkInvariant":
                iid = params["invariantId"]
                if mode == "rpc-error":
                    error = {"code": -32000, "message": "fixture solver timeout"}
                result["invariantStatus"] = (
                    "UNKNOWN" if mode == "unknown" else
                    "VIOLATED" if mode == "later-violated" and iid == 7 else
                    "VIOLATED" if mode == "action-violated" and iid == 11 else "SATISFIED")
            response = {"jsonrpc": "2.0", "id": request["id"]}
            response.update({"error": error} if error else {"result": result})
            body = json.dumps(response).encode()
            self.wfile.write(b"HTTP/1.1 200 OK\r\nContent-Length: %d\r\n\r\n" % len(body) + body)
            self.wfile.flush()


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


if __name__ == "__main__":
    with Server(("127.0.0.1", 0), Handler) as server:
        server.mode, server.audit = sys.argv[1:]
        server.steps = server.health_calls = 0
        print(server.server_address[1], flush=True)
        server.serve_forever()
