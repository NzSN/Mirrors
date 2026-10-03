import Codec.ModelInterfaceScaffoldJson

/-! Command dispatch and immutable/read-only workflow CLI boundary checks. -/

namespace ModelInterfaceWorkflowCliSpec

private def invoke (args : Array String) : IO IO.Process.Output :=
  IO.Process.output { cmd := ".lake/build/bin/model_interface_gen", args }

def run : IO UInt32 := do
  let failures ← IO.mkRef ([] : List String)
  let checks ← IO.mkRef (0 : Nat)
  let check := fun (name : String) (condition : Bool) (detail : String) => do
    checks.modify (· + 1)
    unless condition do failures.modify (· ++ [s!"{name}: {detail}"])
  let root ← IO.FS.createTempDir
  try
    let first := root / "first.itf.json"
    let second := root / "second.itf.json"
    let original ← IO.FS.readBinFile "test/fixtures/model-interface/counter/counter.itf.json"
    IO.FS.writeBinFile first original
    IO.FS.writeBinFile second (original.push 10)
    let base := #["--spec", "specs/Counter.tla", "--param-var", "parameters"]
    let proposal := root / "proposal.json"
    let swapped := root / "swapped.json"
    let legacy := root / "legacy.json"
    let single ← invoke (#["scaffold"] ++ base ++
      #["--evidence", first.toString, "--proposal", legacy.toString])
    check "legacy single-input CLI remains available" (single.exitCode == 0) single.stderr
    if single.exitCode == 0 then
      check "legacy proposal retains v1 decoding"
        (Codec.ModelInterfaceScaffoldJson.parseProposalBytes (← IO.FS.readBinFile legacy)).isOk ""
    let many ← invoke (#["scaffold"] ++ base ++ #["--evidence", first.toString,
      "--evidence", second.toString, "--proposal", proposal.toString, "--diagnostics", "json"])
    let reversed ← invoke (#["scaffold", "--reviewable"] ++ base ++ #["--evidence", second.toString,
      "--evidence", first.toString, "--proposal", swapped.toString])
    check "repeated evidence selects reviewable workflow" (many.exitCode == 0) many.stderr
    check "explicit reviewable command succeeds" (reversed.exitCode == 0) reversed.stderr
    if many.exitCode == 0 && reversed.exitCode == 0 then
      check "CLI evidence order is canonical"
        ((← IO.FS.readBinFile proposal) == (← IO.FS.readBinFile swapped)) ""
      let before ← IO.FS.readBinFile proposal
      let collision ← invoke (#["scaffold", "--reviewable"] ++ base ++
        #["--evidence", first.toString, "--proposal", proposal.toString])
      check "workflow scaffold refuses replacement by default"
        (collision.exitCode == 1 && (← IO.FS.readBinFile proposal) == before) collision.stderr
    let duplicate := root / "duplicate.json"
    let duplicateResult ← invoke (#["scaffold"] ++ base ++ #["--evidence", first.toString,
      "--evidence", first.toString, "--proposal", duplicate.toString])
    check "duplicate evidence publishes nothing"
      (duplicateResult.exitCode == 1 && !(← duplicate.pathExists)) duplicateResult.stderr
    let untouched := root / "untouched"
    let malformed : List (String × Array String) := [
      ("missing seal review", #["seal-scaffold", "--spec", "missing", "--evidence", "missing",
        "--proposal", "missing", "--out", untouched.toString]),
      ("missing seal evidence", #["seal-scaffold", "--spec", "missing", "--proposal", "missing",
        "--review", "missing", "--out", untouched.toString]),
      ("seal replacement forbidden", #["seal-scaffold", "--replace"]),
      ("corpus replacement forbidden", #["project-corpus", "--replace"]),
      ("check replacement forbidden", #["check-corpus", "--replace"]),
      ("reviewable only scaffold", #["resolve-sealed", "--reviewable"]),
      ("duplicate reviewable", #["scaffold", "--reviewable", "--reviewable"]),
      ("legacy resolve forbids repeated evidence", #["resolve", "--evidence", "a", "--evidence", "b"]),
      ("legacy projection forbids repeated evidence", #["project-trace", "--evidence", "a", "--evidence", "b"]),
      ("legacy scaffold forbids review", #["scaffold", "--review", "a"]),
      ("legacy generate forbids sealed", #["generate", "--sealed", "a"]),
      ("legacy check forbids corpus", #["check", "--corpus-manifest", "a"]),
      ("seal forbids contract override", #["seal-scaffold", "--contract", "a"]),
      ("resolve sealed forbids contract override", #["resolve-sealed", "--contract", "a"]),
      ("corpus forbids parameter override", #["project-corpus", "--param-var", "parameters"]),
      ("corpus check forbids input override", #["check-corpus", "--spec", "a"]),
      ("corpus check requires expected hash", #["check-corpus", "--out", untouched.toString]),
      ("duplicate seal source", #["seal-scaffold", "--spec", "a", "--spec", "b"]),
      ("unknown workflow flag", #["resolve-sealed", "--trust-me", "yes"]),
      ("empty expected hash", #["check-corpus", "--out", untouched.toString, "--manifest-sha256", ""]),
      ("unsupported diagnostics", #["project-corpus", "--diagnostics", "yaml"]),
      ("check sealed requires output", #["check-sealed"]),
      ("check sealed bundle requires output", #["check-sealed-bundle"])
    ]
    for (name, args) in malformed do
      let result ← invoke args
      check name (result.exitCode == 2 && !(← untouched.pathExists)) result.stderr
  finally
    IO.FS.removeDirAll root
  let errors ← failures.get
  for error in errors do IO.eprintln error
  IO.println s!"Workflow CLI: {(← checks.get) - errors.length}/{← checks.get} passed"
  return if errors.isEmpty then 0 else 1

end ModelInterfaceWorkflowCliSpec

def main : IO UInt32 := ModelInterfaceWorkflowCliSpec.run
