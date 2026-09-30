#!/usr/bin/env python3
"""Native v2 map/lookup regression with recorded replay, using a prepared package."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prefix", type=Path, required=True, help="installed pinned MirrorCPP package")
    args = parser.parse_args()
    compiler = ROOT / ".lake/build/bin/model_interface_gen"
    types = {"action_taken": "Str", "parameters": "{ integers: (Int -> Int), strings: (Str -> Int) }",
             "reg": "(Int -> Int)", "dr": "(Str -> (Int -> Bool))", "tls": "(Str -> (Int -> Str))"}
    bigint = lambda n: {"#bigint": str(n)}
    mapping = lambda entries: {"#map": entries}
    large = -999999999999999999999999999999999999999
    string_key = '1\0"\\\n'
    parameter = {"integers": mapping([[bigint(large), bigint(7)], [bigint(1), bigint(11)]]),
                 "strings": mapping([[string_key, bigint(3)]])}
    def state(action: str, number: int) -> dict:
        return {"action_taken": action, "parameters": parameter,
                "reg": mapping([[bigint(-1), bigint(number)], [bigint(-large), bigint(2)]]),
                "dr": mapping([["t1", mapping([[bigint(1), True], [bigint(2), False]])], ["t2", mapping([])]]),
                "tls": mapping([["t1", mapping([[bigint(1), "ready"], [bigint(2), "idle"]])], ["t2", mapping([])]])}
    evidence = {"#meta": {"varTypes": types}, "vars": list(types), "params": [],
                "param_vars": ["parameters"], "states": [state("init", 0), state("put", 10)]}
    contract = {"schema": "mirrors.model-interface/v1", "interfaceVersion": "1.0.0",
                "model": {"module": "IntegerTables", "source": "IntegerTables.tla"},
                "wire": {"actionVariable": "action_taken", "parameterVariable": "parameters"},
                "initializers": [{"id": "Initialize", "wireAction": "init", "wireAliases": [], "inputs": []}],
                "actions": [{"id": "Put", "wireAction": "put", "wireAliases": [], "inputs": [
                    {"id": "IntegerItem", "from": {"root": "stepParameters", "path": [
                        {"field": "parameters"}, {"field": "integers"}, {"mapKey": {"kind": "int", "value": str(large)}}]}},
                    {"id": "StringItem", "from": {"root": "stepParameters", "path": [
                        {"field": "parameters"}, {"field": "strings"}, {"mapKey": {"kind": "str", "value": string_key}}]}}]}],
                "observations": [{"id": name.title(), "wireName": name, "provenance": "implementation"}
                                 for name in ("reg", "dr", "tls")]}
    with tempfile.TemporaryDirectory(prefix="mirrors integer maps ") as directory:
        scratch = Path(directory)
        def run(command: list[str], ok: bool = True) -> str:
            result = subprocess.run(command, cwd=scratch, text=True, capture_output=True, timeout=180)
            output = result.stdout + result.stderr
            if (result.returncode == 0) != ok:
                raise AssertionError(f"{command}: exit {result.returncode}\n{output}")
            return output
        (scratch / "IntegerTables.tla").write_text(
            "---- MODULE IntegerTables ----\nEXTENDS Integers\nVARIABLES " + ", ".join(types) +
            "\nInit == TRUE\nNext == TRUE\n====\n")
        (scratch / "contract.json").write_text(json.dumps(contract))
        (scratch / "trace.json").write_text(json.dumps(evidence))
        inputs = ["--spec", "IntegerTables.tla", "--contract", "contract.json", "--evidence", "trace.json",
                  "--param-var", "parameters", "--lock", "lock.json"]
        run([str(compiler), "resolve", *inputs])
        rejected = run([str(compiler), "generate", "--lock", "lock.json", "--target", "mirrorcpp-v1",
                        "--out", "unsupported", "--diagnostics", "json"], False)
        assert "MIC-E-TYPE-001" in rejected and "MIC-E-PATH-001" in rejected
        diagnostics = json.loads(rejected)
        findings = [diagnostic for diagnostic in diagnostics if diagnostic["stage"] == "emit"]
        assert len(findings) == 5, "independent target findings were dropped"
        human = run([str(compiler), "generate", "--lock", "lock.json", "--target", "mirrorcpp-v1",
                     "--out", "unsupported"], False)
        for diagnostic in findings:
            assert diagnostic["code"] in human and diagnostic["primary"]["pointer"] in human
            assert diagnostic["subject"]["stableId"] in human
        assert any(argument["value"] == "type.value.key" for diagnostic in diagnostics
                   for argument in diagnostic["arguments"]), "nested integer-key location is absent"
        assert not (scratch / "unsupported").exists()
        # Invalid IDs are rejected by resolution; both diagnostic formats must
        # retain their data without breaking human lines.
        quoted = json.loads(json.dumps(contract))
        quoted_id = 'Quoted"Reg\\Line\nEnd'
        quoted["observations"][0]["id"] = quoted_id
        (scratch / "quoted-contract.json").write_text(json.dumps(quoted))
        quoted_inputs = ["quoted-contract.json" if value == "contract.json" else
                         "quoted-lock.json" if value == "lock.json" else value for value in inputs]
        quoted_json = json.loads(run([str(compiler), "resolve", *quoted_inputs,
                                     "--diagnostics", "json"], False))
        assert any(diagnostic["subject"].get("stableId") == quoted_id for diagnostic in quoted_json)
        quoted_human = run([str(compiler), "resolve", *quoted_inputs], False)
        assert json.dumps(quoted_id)[1:-1] in quoted_human, "human diagnostics do not escape identifiers"
        assert not (scratch / "quoted-lock.json").exists()
        keyword = json.loads(json.dumps(contract))
        keyword["observations"][0]["id"] = "Class"
        (scratch / "keyword-contract.json").write_text(json.dumps(keyword))
        keyword_inputs = ["keyword-contract.json" if value == "contract.json" else
                          "keyword-lock.json" if value == "lock.json" else value for value in inputs]
        run([str(compiler), "resolve", *keyword_inputs])
        keyword_error = run([str(compiler), "generate", "--lock", "keyword-lock.json",
                             "--target", "mirrorcpp-v2", "--out", "keyword-output"], False)
        assert "mirrorcpp-v2" in keyword_error and "C++ keyword: Class" in keyword_error
        assert not (scratch / "keyword-output").exists()
        run([str(compiler), "generate-cmake", *inputs, "--target", "mirrorcpp-v2", "--out", "generated"])
        (scratch / "CMakeLists.txt").write_text(
            'cmake_minimum_required(VERSION 3.24)\nproject(integer_maps LANGUAGES CXX)\n'
            'find_package(mirrorcpp CONFIG REQUIRED)\ninclude(generated/MirrorInterface.cmake)\n'
            'mirrors_add_model_interface(binding "${CMAKE_CURRENT_SOURCE_DIR}")\n'
            f'add_executable(integer_maps "{ROOT}/tools/model-interface-cpp/integer_maps.cpp")\n'
            'target_link_libraries(integer_maps PRIVATE binding mirrorcpp::mirrorcpp)\n')
        run(["cmake", "-S", str(scratch), "-B", "build", f"-DCMAKE_PREFIX_PATH={args.prefix.resolve()}"])
        run(["cmake", "--build", "build", "-j", "2"])
        print(run([str(scratch / "build/integer_maps"), str(ROOT / ".lake/build/bin/mirror"),
                   str(scratch / "trace.json")]).strip())


if __name__ == "__main__":
    main()
