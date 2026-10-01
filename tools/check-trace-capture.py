#!/usr/bin/env python3
"""Exercise remote trace capture through the actual CLI without a model checker."""
from __future__ import annotations

import json
from pathlib import Path
import socket
import subprocess
import tempfile
import threading

ROOT = Path(__file__).resolve().parents[1]
BINARY = ROOT / ".lake/build/bin/mirror"
TRACE = {"#meta": {"seed": 7}, "vars": ["action_taken", "count", "parameters"],
         "params": [], "param_vars": ["parameters"], "states": [
             {"#meta": {"index": 0}, "action_taken": "init", "count": {"#bigint": "0"},
              "parameters": {"stride": {"#bigint": "0"}}}]}
DONE = {"proto_step": "gen_traces_done", "itfTracePaths": ["/server-only/trace.json"], "itfTraces": [TRACE]}
ACCEPTED = {"proto_step": "job_accepted", "jobId": "owned", "kind": "gen_traces"}


def job_result(job: str = "owned", outcome: dict | None = None) -> dict:
    return {"proto_step": "job_result", "jobId": job, "outcome": outcome or {
        "genTraces": {"itfTracePaths": DONE["itfTracePaths"], "itfTraces": [TRACE]}}}


def run_case(root: Path, label: str, replies: list, expected: int, *, asynchronous: bool = False,
             text: str = "", extra: list[str] | None = None, cancellation: bool = False) -> None:
    failures, requests = [], []
    output = root / label
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0)); listener.listen(); listener.settimeout(8)
        def serve() -> None:
            try:
                with listener.accept()[0] as connection:
                    connection.settimeout(8)
                    with connection.makefile("rb") as stream:
                        for index, reply in enumerate(replies):
                            packet = stream.readline(65537)
                            assert packet, (label, index)
                            request = json.loads(packet); requests.append(request)
                            if index == 0:
                                assert request["proto_step"] == ("register_trace_gen_async" if asynchronous else "register_trace_gen")
                                assert request.get("destPath") is None
                                assert request["spec"]["sources"] == [(root / name).read_text() for name in ("Main.tla", "Child.tla")]
                                assert str(root) not in json.dumps(request)
                            else:
                                assert request == {"proto_step": "await_job", "jobId": "owned", "timeoutSecs": 30}
                            if reply is None: break
                            payload = reply if isinstance(reply, str) else json.dumps(reply)
                            connection.sendall((payload + "\n").encode())
                        if cancellation:
                            packet = stream.readline(65537)
                            assert json.loads(packet) == {"proto_step": "cancel_job", "jobId": "owned"}
            except Exception as error:
                failures.append(repr(error))
        thread = threading.Thread(target=serve, daemon=True); thread.start()
        command = [str(BINARY), "trace-gen", "--host", "127.0.0.1", "--port", str(listener.getsockname()[1]),
                   "--spec", str(root / "Main.tla"), "--out", str(output), "--param-var", "parameters"]
        if asynchronous: command += ["--async"]
        result = subprocess.run(command + (extra or []), capture_output=True, text=True, timeout=15)
        thread.join(9)
        assert not thread.is_alive() and not failures, (label, result, failures)
        assert result.returncode == expected, (label, result)
        assert text in result.stderr, (label, result)
        if expected == 0:
            assert json.loads((output / "trace-0.itf.json").read_text()) == TRACE
            receipt = json.loads((output / "capture.json").read_text())
            assert receipt["schema"] == "mirrors.remote-trace-capture/v1"
            assert receipt["traceCount"] == 1
            assert str(root) not in (output / "request.json").read_text()
            assert (output / "replies.jsonl").is_file()
            assert "--key" not in (output / "capture.json").read_text()
        else:
            assert not output.exists(), (label, "failed capture published output")


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="mirrors-trace-capture-") as directory:
        root = Path(directory)
        (root / "Main.tla").write_text("---- MODULE Main ----\nEXTENDS Child, Integers\n====\n")
        (root / "Child.tla").write_text("---- MODULE Child ----\nValue == 1\n====\n")
        run_case(root, "sync", [DONE], 0)
        run_case(root, "async", [ACCEPTED, {"proto_step": "job_status", "jobId": "owned", "phase": "pending"}, job_result()], 0, asynchronous=True)
        run_case(root, "path-only", [{**DONE, "itfTraces": []}], 2, text="inline ITF")
        run_case(root, "invalid-trace", [{**DONE, "itfTraces": [{}]}], 2, text="invalid ITF")
        run_case(root, "artifact-count", [{**DONE, "itfTraces": [TRACE] * 65}], 2, text="64-artifact")
        run_case(root, "backend-error", [{"proto_step": "register_error", "error": "TRACE_RESULT_TOO_LARGE"}], 2, text="TRACE_RESULT_TOO_LARGE")
        run_case(root, "duplicate-field", ['{"proto_step":"gen_traces_done","itfTracePaths":[],"itfTraces":[],"itfTraces":[]}'], 2, text="bad json")
        run_case(root, "wrong-kind", [{**ACCEPTED, "kind": "validate"}], 2, asynchronous=True, text="trace-generation job_accepted")
        run_case(root, "empty-job", [{**ACCEPTED, "jobId": ""}], 2, asynchronous=True, text="empty")
        run_case(root, "wrong-job", [ACCEPTED, job_result("other")], 2, asynchronous=True, text="job id mismatch", cancellation=True)
        run_case(root, "wrong-result", [ACCEPTED, job_result(outcome={"validate": "valid"})], 2, asynchronous=True, text="validation result", cancellation=True)
        run_case(root, "poll-budget", [ACCEPTED, {"proto_step": "job_status", "jobId": "owned", "phase": "running"}], 2,
                 asynchronous=True, text="poll budget", extra=["--max-polls", "1"], cancellation=True)
        run_case(root, "cancelled", [ACCEPTED, {"proto_step": "job_status", "jobId": "owned", "phase": "cancelled"}], 2,
                 asynchronous=True, text="cancelled", cancellation=True)
        # Refuse local failures before opening a connection.
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0)); listener.listen(); listener.settimeout(.1)
            output = root / "existing"; output.mkdir(); (output / "unrelated").write_text("preserve")
            command = [str(BINARY), "trace-gen", "--host", "127.0.0.1", "--port", str(listener.getsockname()[1]),
                       "--spec", str(root / "Main.tla"), "--out", str(output)]
            failed = subprocess.run(command, capture_output=True, text=True, timeout=10)
            assert failed.returncode == 2 and "exists" in failed.stderr
            assert (output / "unrelated").read_text() == "preserve"
            (root / "Child.tla").write_text("---- MODULE Child ----\n(*" + "x" * 66000 + "*)\n====\n")
            failed = subprocess.run(command[:-1] + [str(root / "too-large")], capture_output=True, text=True, timeout=10)
            assert failed.returncode == 2 and "65535" in failed.stderr
            try: connection, _ = listener.accept()
            except TimeoutError: pass
            else:
                connection.close(); raise AssertionError("local failure opened a connection")
    print("TRACE CAPTURE CLI GREEN (15 protocol/publication cases)")


if __name__ == "__main__":
    main()
