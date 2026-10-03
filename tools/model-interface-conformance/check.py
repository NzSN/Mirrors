#!/usr/bin/env python3
"""Execute common fixtures through six fresh generated profiles.

No model checker is started. A selected subset is explicitly reported as a
subset; missing prerequisites fail. Native outputs are checked against reviewed
fixtures and then compared across the common representable recording cases.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tomllib

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
FIXTURES = ROOT / "test/fixtures/model-interface/language"
TARGETS = ("ts", "async", "cpp", "cpp-v2", "rust", "lean")


def rows(name):
    return [json.loads(line) for line in (FIXTURES / name).read_text().splitlines() if line]


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def norm(value):
    """Presentation normalization only; generated codecs decide admissibility."""
    if value is None: return ("null",)
    if isinstance(value, bool): return ("bool", value)
    if isinstance(value, str): return ("str", value)
    if isinstance(value, list): return ("seq", tuple(map(norm, value)))
    if not isinstance(value, dict): raise AssertionError(f"non-ITF fixture value {value!r}")
    if set(value) == {"#bigint"} and isinstance(value["#bigint"], str): return ("int", int(value["#bigint"]))
    if set(value) == {"#tup"} and isinstance(value["#tup"], list): return ("tuple", tuple(map(norm, value["#tup"])))
    if set(value) == {"#set"} and isinstance(value["#set"], list): return ("set", tuple(sorted(map(norm, value["#set"]), key=repr)))
    if set(value) == {"#map"} and isinstance(value["#map"], list): return ("map", tuple(sorted(((norm(k), norm(v)) for k, v in value["#map"]), key=repr)))
    if set(value) == {"tag", "value"} and isinstance(value["tag"], str): return ("variant", value["tag"], norm(value["value"]))
    return ("record", tuple((k, norm(v)) for k, v in sorted(value.items())))


def verify_roundtrip(actual, value, accepted, label):
    require(actual.get("accepted") is accepted, (label, actual))
    require(actual.get("effects") == (4 if accepted else 0), (label, "effect boundary", actual))
    if accepted:
        require(norm(actual["output"]) == norm(value), (label, "codec law", actual))
        require(norm(actual["again"]) == norm(value), (label, "native encode/decode law", actual))
    else:
        require(actual.get("error") == "input_shape_mismatch", (label, actual))
        require(actual.get("poisoned") is True, (label, "permanent poisoning", actual))


def canonical_report_frame(frame):
    """Validate an actual SDK encoder payload; never synthesize it from a state."""
    require(isinstance(frame, str) and frame and "\n" not in frame and "\r" not in frame, "report_state must be one unterminated JSONL payload")
    def object_pairs(pairs):
        result = {}
        for key, value in pairs:
            if key in result: raise ValueError(f"duplicate report_state field: {key}")
            result[key] = value
        return result
    def invalid_constant(value): raise ValueError(f"invalid JSON number: {value}")
    value = json.loads(frame, object_pairs_hook=object_pairs, parse_constant=invalid_constant)
    require(isinstance(value, dict) and set(value) == {"proto_step", "state"}, "report_state envelope fields")
    require(value["proto_step"] == "report_state" and isinstance(value["state"], dict), "report_state envelope shape")
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def verify_recording(actual, expected, label):
    frames = actual.get("wireFrames")
    require(isinstance(frames, list), (label, "missing SDK report_state encoder frames"))
    require(len(frames) == len(expected["wireFrames"]), (label, "report_state frame count"))
    for index, (frame, wanted) in enumerate(zip(frames, expected["wireFrames"])):
        canonical = canonical_report_frame(frame)
        # Count-only recording frames have a completely specified ordering and
        # ASCII values, so the actual SDK bytes must already be canonical.
        require(frame.encode("utf-8") == canonical, (label, index, "noncanonical SDK report_state bytes"))
        require(canonical == wanted.encode("utf-8"), (label, index, "wrong SDK report_state bytes", frame, wanted))
    require(actual == expected, (label, actual, expected))


def verify(target, output, generated):
    result = {}
    for line in output.splitlines():
        value = json.loads(line)
        key = (value.pop("family"), value.pop("id"))
        require(key not in result, (target, "duplicate output", key))
        result[key] = value
    expected = set()
    def take(family, row):
        key = (family, row["id"]); expected.add(key)
        require(key in result, (target, "missing fixture", key))
        return result[key]
    for name in ("Portable", "Recording"):
        lock = json.loads((generated / "ts" / name / "synthetic.lock.json").read_text())
        actual = take("identity", {"id": name})
        require(actual == {"semanticDigest": lock["semanticDigest"], "contract": lock["contract"]}, (target, "runtime identity", name, actual))
    for row in rows("mitl-values.jsonl"):
        verify_roundtrip(take("value", row), row["value"], row["accepted"], (target, row["id"]))
    for row in rows("mitl-equivalence.jsonl"):
        actual = take("equivalence", row)
        for side in ("left", "right"):
            verify_roundtrip(actual[side], row[side], row[side + "Accepted"], (target, row["id"], side))
        equivalent = (actual["left"]["accepted"] and actual["right"]["accepted"]
                      and norm(actual["left"]["output"]) == norm(actual["right"]["output"]))
        require(equivalent is row["equivalent"], (target, row["id"], actual))
    for row in rows("native-encoding.jsonl"):
        actual = take("encode", row)
        require(actual == {"accepted": False, "error": row["error"], "effects": 2, "poisoned": True}, (target, row["id"], actual))
    for row in rows("mitl-paths.jsonl"):
        if row.get("static") is False or row.get("generatedPortable") is False: continue
        actual = take("path", row); accepted = row.get("dynamic", True)
        require(actual["accepted"] is accepted and actual["effects"] == (2 if accepted else 0), (target, row["id"], actual))
        if accepted: require(norm(actual["output"]) == norm(row["result"]), (target, row["id"], actual))
        else: require(actual["error"] == "input_shape_mismatch", (target, row["id"], actual))
    for row in rows("counter-binding-events.jsonl"):
        if target not in row.get("targets", TARGETS): continue
        actual = take("recording", row)
        verify_recording(actual, row["expected"], (target, row["id"]))
    require(set(result) == expected, (target, "unexpected fixtures", set(result) - expected))
    return result


def run(argv, *, cwd=ROOT, env=None, timeout=300):
    completed = subprocess.run(list(map(str, argv)), cwd=cwd, env=env, text=True,
                               capture_output=True, timeout=timeout)
    if completed.returncode:
        raise RuntimeError(f"command failed ({completed.returncode}): {argv}\n{completed.stdout}{completed.stderr}")
    return completed.stdout


def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    # Reject a comparison oracle that loses ordinary fields next to ITF markers.
    marker = {"#set": [], "ordinary": False}
    require(norm(marker) != norm({"#set": [], "ordinary": True}), "comparison oracle regression")
    require(norm(marker) != norm({"#set": []}), "comparison oracle regression")
    require(norm({"#set": False}) == ("record", (("#set", ("bool", False)),)), "comparison oracle regression")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--targets", nargs="+", choices=TARGETS, default=list(TARGETS))
    parser.add_argument("--work", type=Path, default=ROOT / ".golden-build/model-interface-conformance")
    parser.add_argument("--generator", type=Path, default=ROOT / ".lake/build/bin/model_interface_language_spec")
    parser.add_argument("--node", default="node")
    parser.add_argument("--ecma", type=Path, default=ROOT.parent / "MirrorECMA")
    parser.add_argument("--rust", type=Path, default=ROOT.parent / "MirrorRust")
    parser.add_argument("--lean", type=Path, default=ROOT.parent / "MirrorLean")
    parser.add_argument("--cpp-prefix", type=Path, default=os.environ.get("MIRRORCPP_PREFIX"))
    parser.add_argument("--reuse-generated", action="store_true", help="focused development only; receipt records this")
    args = parser.parse_args()
    work = args.work.resolve(); work.mkdir(parents=True, exist_ok=True)
    generated = work / "generated"
    run([sys.executable, HERE / "test_check.py"])
    if not args.reuse_generated:
        print(run([args.generator.resolve(), generated]).strip(), flush=True)
    outputs = {}
    typechecked = False
    if any(target in args.targets for target in ("ts", "async")):
        # The runtime gate erases types only after the actual generated sources
        # and typed fixture ports compile against the current SDK public API.
        types = work / "typescript-types"; types.mkdir(exist_ok=True)
        (types / "package.json").write_text('{"type":"module"}\n')
        typed = '''import type {InitializeInput as SyncInput, PortablePort} from "../generated/ts/Portable/PortableMirror.generated.js";
import type {InitializeInput as AsyncInput, PortableAsyncPort} from "../generated/async/Portable/PortableMirror.generated.js";
let saved: SyncInput | undefined;
const port: PortablePort = { initialize(input) { saved=input; }, observe() { if (!saved) throw new Error("uninitialized"); return saved; } };
let asyncSaved: AsyncInput | undefined;
const asyncPort: PortableAsyncPort = { async initialize(input) { asyncSaved=input; }, async observe() { if (!asyncSaved) throw new Error("uninitialized"); return asyncSaved; } };
void port; void asyncPort;
'''
        (types / "Ports.ts").write_text(typed)
        (types / "tsconfig.json").write_text(json.dumps({
            "compilerOptions":{"target":"ES2022", "module":"NodeNext", "moduleResolution":"NodeNext",
                               "strict":True, "skipLibCheck":True, "noEmit":True,
                               "baseUrl":str(args.ecma.resolve()),
                               "paths":{"mirrorecma":[str(args.ecma.resolve() / "src/index.ts")]},
                               "typeRoots":[str(args.ecma.resolve() / "node_modules/@types")]},
            "include":[str(generated / "ts/**/*.ts"), str(generated / "async/**/*.ts"), str(types / "Ports.ts")],
        }, indent=2)+"\n")
        run([args.node, args.ecma.resolve() / "node_modules/typescript/bin/tsc", "--project", types / "tsconfig.json"])
        typechecked = True
    def execute(target, command, **kwargs):
        output = run(command, **kwargs)
        (work / f"{target}.jsonl").write_text(output)
        outputs[target] = verify(target, output, generated)
        print(f"{target}: {len(outputs[target])} shared native cases passed", flush=True)
    for target in args.targets:
        if target in ("ts", "async"):
            execute(target, [args.node, HERE / "typescript.mjs", FIXTURES, generated, args.ecma.resolve(), target])
        elif target in ("cpp", "cpp-v2"):
            if args.cpp_prefix is None:
                raise ValueError("C++ requires --cpp-prefix or MIRRORCPP_PREFIX containing the prepared MirrorCPP package")
            cpp = work / target; cpp.mkdir(exist_ok=True)
            includes = sorted(str(path) for path in (generated / target).iterdir() if path.is_dir())
            profile = "mirrorcpp-v2" if target == "cpp-v2" else "mirrorcpp-v1"
            for directory in includes:
                manifest = json.loads((Path(directory) / ".model-interface-generated.json").read_text())
                require(manifest["targetProfile"] == profile, (target, "wrong emitter profile", directory))
            (cpp / "CMakeLists.txt").write_text(
                'cmake_minimum_required(VERSION 3.24)\nproject(mitl_cpp LANGUAGES CXX)\n'
                'find_package(mirrorcpp CONFIG REQUIRED)\n'
                f'add_executable(mitl_cpp "{HERE / "native.cpp"}")\n'
                'target_compile_features(mitl_cpp PRIVATE cxx_std_23)\n'
                'target_link_libraries(mitl_cpp PRIVATE mirrorcpp::mirrorcpp)\n'
                'target_include_directories(mitl_cpp PRIVATE ' + " ".join(f'"{path}"' for path in includes) + ')\n')
            run(["cmake", "-S", cpp, "-B", cpp / "build", f"-DCMAKE_PREFIX_PATH={args.cpp_prefix.resolve()}"])
            run(["cmake", "--build", cpp / "build", "-j2"])
            execute(target, [cpp / "build/mitl_cpp", FIXTURES])
        elif target == "rust":
            rust = work / "rust"; rust.mkdir(exist_ok=True)
            manifest = (
                '[package]\nname = "mitl-generated-conformance"\nversion = "0.0.0"\nedition = "2021"\n'
                '[dependencies]\nnum-bigint = "0.4"\nserde_json = "1"\n'
                f'mirrorrust = {{path = {json.dumps(str(args.rust.resolve()))}}}\n'
                '[[bin]]\nname = "mitl_rust"\n' + f'path = {json.dumps(str(HERE / "native.rs"))}\n')
            negatives = [("missing", "", "E0063"), ("extra", "count: 0.into(), extra: true", "E0560"),
                         ("mistyped", "count: true", "E0308")]
            for name, fields, _ in negatives:
                source = rust / (name + ".rs")
                source.write_text('mod recording { include!(concat!(env!("MITL_GENERATED"), "/rust/Recording/RecordingMirror.generated.rs")); }\n'
                                  'fn main() { let _ = recording::RecordingObservation {' + fields + '}; }\n')
                manifest += f'[[bin]]\nname = "shape_{name}"\npath = {json.dumps(str(source))}\n'
            (rust / "Cargo.toml").write_text(manifest)
            shutil.copyfile(args.rust / "Cargo.lock", rust / "Cargo.lock")
            env = {**os.environ, "MITL_GENERATED": str(generated), "CARGO_TARGET_DIR": str(work / "rust-target")}
            run(["cargo", "build", "--offline", "--manifest-path", rust / "Cargo.toml", "--bin", "mitl_rust"], env=env)
            sdk_packages = tomllib.loads((args.rust / "Cargo.lock").read_text())["package"]
            actual_packages = tomllib.loads((rust / "Cargo.lock").read_text())["package"]
            identity = lambda package: (package["name"], package["version"], package.get("source"), package.get("checksum"))
            pinned = {identity(package) for package in sdk_packages}
            require(all(identity(package) in pinned for package in actual_packages if "source" in package), "Rust dependency selection drifted from SDK lock")
            execute(target, [work / "rust-target/debug/mitl_rust", FIXTURES])
            for name, _, code in negatives:
                result = subprocess.run(["cargo", "check", "--offline", "--manifest-path", str(rust / "Cargo.toml"),
                                         "--bin", "shape_" + name], env=env, capture_output=True, text=True, timeout=300)
                (rust / (name + ".log")).write_text(result.stdout + result.stderr)
                require(result.returncode != 0 and f"error[{code}]" in result.stderr, ("Rust native shape rejection", name, result.stderr))
        else:
            from lean_driver import prepare
            command, env = prepare(work, generated, args.lean.resolve(), run)
            execute(target, [*command, FIXTURES], cwd=work / "lean", env=env)
    common = [row for row in rows("counter-binding-events.jsonl") if "targets" not in row]
    for row in common:
        reports = [outputs[target][("recording", row["id"])] for target in args.targets]
        require(all(report == reports[0] for report in reports), ("cross-language recording mismatch", row["id"]))
    recording = {row["id"]:outputs[args.targets[0]][("recording", row["id"])] for row in common}
    recording_bytes = (json.dumps(recording,sort_keys=True,separators=(",",":"))+"\n").encode()
    (work / "common-recording.json").write_bytes(recording_bytes)
    for target in args.targets:
        raw_frames = {row["id"]:outputs[target][("recording", row["id"])]["wireFrames"] for row in common}
        (work / f"{target}-report-state-frames.json").write_text(json.dumps(raw_frames,sort_keys=True,indent=2)+"\n")
    common_frames = {row["id"]:recording[row["id"]]["wireFrames"] for row in common}
    frame_bytes = (json.dumps(common_frames,sort_keys=True,separators=(",",":"))+"\n").encode()
    (work / "common-report-state-frames.json").write_bytes(frame_bytes)
    jsonl_bytes = b"".join(canonical_report_frame(frame)+b"\n" for row in common for frame in common_frames[row["id"]])
    (work / "canonical-report-state.jsonl").write_bytes(jsonl_bytes)
    fixture_hashes = {path.name:digest(path) for path in sorted(FIXTURES.glob("*.jsonl"))}
    receipt = {"schema":"mirrors.generated-conformance/v1", "targets":args.targets,
               "freshGeneration":not args.reuse_generated,
               "completeTargetSet":set(args.targets)==set(TARGETS),
               "cases":{target:len(result) for target,result in outputs.items()},
               "commonRecordingCases":len(common), "fixtureSha256":fixture_hashes,
               "commonRecordingSha256":hashlib.sha256(recording_bytes).hexdigest(),
               "commonReportStateFramesSha256":hashlib.sha256(frame_bytes).hexdigest(),
               "canonicalReportStateJsonlSha256":hashlib.sha256(jsonl_bytes).hexdigest(),
               "reportStateFrames":sum(len(frames) for frames in common_frames.values()),
               "reportStateEncoding":"Actual SDK encoder payloads; strict envelope/duplicate-key checks and exact canonical payload bytes. The JSONL artifact adds one LF per payload.",
               "wireFrameVerifier":"passed",
               "typescriptTypecheck":typechecked,
               "nativeObservationCompileRejections":{target:3 for target in args.targets if target in ("rust", "lean")},
               "leanToolchain":json.loads((work / "lean/selected-toolchain.json").read_text()) if "lean" in args.targets else None,
               "generatedSha256":{str(path.relative_to(generated)):digest(path) for path in sorted(generated.rglob("*")) if path.is_file()},
               "adapterSha256":{path.name:digest(path) for path in sorted(HERE.iterdir()) if path.is_file()},
               "nativeObservationShape":"Native observation records are typed complete values; the three malformed-native-record cases execute in ts/async only. Raw closed-record value negatives execute in all five targets.",
               "scope":"Generated codecs, mechanical bindings and path projections; no live model checking or transport acceptance."}
    (work / "receipt.json").write_text(json.dumps(receipt,indent=2)+"\n")
    print(f"Shared conformance passed for {', '.join(args.targets)}; receipt: {work / 'receipt.json'}")


if __name__ == "__main__":
    try: main()
    except (AssertionError, ValueError, RuntimeError) as error:
        print(str(error), file=sys.stderr); raise SystemExit(1)
