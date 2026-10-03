"""Prepare an isolated native Lean consumer of the generated corpus."""
import json
import os
from pathlib import Path
import shutil

HERE = Path(__file__).resolve().parent
PATHS = ["RootRecord", "RecordField", "TupleIndex", "SequenceIndex", "SequenceOutOfRange",
         "VariantProjection", "VariantWrongTag", "NestedProjection"]

PATH = r'''
def pathNAME (value : Json) : IO Json := do
  let saved ← IO.mkRef (none : Option PathNAMEMirror.InitializeInput)
  let effects ← IO.mkRef (0 : Nat)
  let port : PathNAMEMirror.Port := {
    «initialize» := fun input => do
      effects.modify (· + 1)
      saved.set (some input)
      pure (.ok ())
    observe := do
      effects.modify (· + 1)
      match ← saved.get with
      | some input => pure do return { value := ← NativeCodec.decode (← NativeCodec.encode input.value) }
      | none => pure (.error shape) }
  let binding ← unwrap (← PathNAMEMirror.bind port config)
  let payload ← IO.ofExcept (State.ofJson? (if "NAME" == "RootRecord" then value else Json.mkObj [("root", value)]))
  match ← binding.computer "init" payload empty with
  | .ok result =>
      pure (Json.mkObj [("accepted", .bool true), ("output", ← get result.toJson "value"), ("effects", toJson (← effects.get))])
  | .error error =>
      pure (Json.mkObj [("accepted", .bool false), ("error", .str error.code), ("effects", toJson (← effects.get))])
'''


def prepare(work, generated, sdk, run):
    lean = work / "lean"; lean.mkdir(exist_ok=True)
    toolchain = (sdk / "lean-toolchain").read_text().strip()
    if not toolchain or "\n" in toolchain:
        raise ValueError("MirrorLean requires one explicit Lean toolchain pin")
    # A relocated consumer must not inherit the machine's global Lean version.
    shutil.copyfile(sdk / "lean-toolchain", lean / "lean-toolchain")
    lean_command = ["elan", "run", toolchain, "lean"]
    copied = lean / "sdk"; copied.mkdir(exist_ok=True)
    shutil.copytree(sdk / "MirrorLean", copied / "MirrorLean", dirs_exist_ok=True)
    for name in ("MirrorLean.lean", "lean-toolchain"):
        shutil.copyfile(sdk / name, copied / name)
    (copied / "lakefile.toml").write_text('name = "mirrorlean"\ndefaultTargets = ["MirrorLean"]\n[[lean_lib]]\nname = "MirrorLean"\n')
    run(["elan", "run", toolchain, "lake", "-d", copied, "build", "MirrorLean"], cwd=lean)
    modules = sorted((generated / "lean").glob("*/*.lean"))
    for source in modules: shutil.copyfile(source, lean / source.name)
    env = {**os.environ, "LEAN_PATH": str(copied / ".lake/build/lib/lean") + os.pathsep + str(lean)}
    version = run([*lean_command, "--version"], cwd=lean, env=env).strip()
    (lean / "selected-toolchain.json").write_text(json.dumps({"toolchain": toolchain, "version": version}, indent=2)+"\n")
    for source in modules: run([*lean_command, "-o", source.stem + ".olean", source.name], cwd=lean, env=env)
    imports = "\n".join("import Path" + name + "Mirror" for name in PATHS)
    definitions = "\n".join(PATH.replace("NAME", name) for name in PATHS)
    definitions += '\ndef runPath (id : String) (value : Json) : IO Json :=\n  match id with\n'
    definitions += "\n".join('  | "' + name + '" => path' + name + ' value' for name in PATHS)
    definitions += '\n  | _ => throw (IO.userError ("unknown path fixture: " ++ id))\n'
    source = (HERE / "native.lean.in").read_text().replace("-- PATH_IMPORTS", imports).replace("-- PATH_DEFINITIONS", definitions)
    (lean / "Native.lean").write_text(source)
    # A separate native constructor check substantiates why raw JSON observation
    # shape negatives are not counted as runtime passes for this typed target.
    for name, expression in [
        ("Missing", "{}"), ("Extra", '{ count := 0, extra := true }'),
        ("Mistyped", '{ count := "wrong" }'),
    ]:
        (lean / (name + ".lean")).write_text('import RecordingMirror\nexample : RecordingMirror.Observation := ' + expression + '\n')
        import subprocess
        result = subprocess.run([*lean_command, name + ".lean"], cwd=lean, env=env, text=True, capture_output=True)
        (lean / (name + ".log")).write_text(result.stdout + result.stderr)
        if result.returncode == 0 or "error:" not in result.stdout:
            raise AssertionError("Lean native observation shape was not rejected: " + name)
    return [*lean_command, "--run", "Native.lean"], env
