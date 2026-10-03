import Shell.ModelInterface.Corpus

namespace ModelInterfaceCorpusSpec

open Core.ModelInterface Shell.ModelInterface.Corpus

private def raw : String :=
  "{\"#meta\":{\"format\":\"ITF\",\"varTypes\":{\"nk\":\"(Int -> Int)\",\"action_taken\":\"Str\"}}," ++
  "\"vars\":[\"nk\",\"action_taken\"],\"states\":[" ++
  "{\"action_taken\":\"init\",\"nk\":{\"#map\":[[{\"#bigint\":\"0\"},{\"#bigint\":\"0\"}]]}}," ++
  "{\"action_taken\":\"step\",\"nk\":{\"#map\":[[{\"#bigint\":\"0\"},{\"#bigint\":\"1\"}]]}}]}"

private def plan : TraceProjectionPlan := {
  exactCopyVariables := ["action_taken"]
  zipIntFunctions := [{
    outputWireName := "nodes"
    domain := { lowerInclusive := "0", upperInclusive := "0" }
    fields := [{ name := "key", sourceVariable := "nk" }] }] }

private def rejected (result : Except ε α) : Bool :=
  match result with | .error _ => true | .ok _ => false

private def check (failures : IO.Ref (List String)) (count : IO.Ref Nat)
    (name : String) (condition : Bool) : IO Unit := do
  count.modify (· + 1)
  if !condition then failures.modify (· ++ [name])

private def noStage (root : System.FilePath) : IO Bool := do
  let leftovers := (← root.readDir).filter fun entry =>
    entry.fileName.contains ".model-interface-stage-" ||
      entry.fileName.endsWith ".model-interface-directory.lock"
  if !leftovers.isEmpty then IO.eprintln s!"staging leftovers: {leftovers.map (·.fileName)}"
  return leftovers.isEmpty

private def run (root : System.FilePath) (failures : IO.Ref (List String))
    (count : IO.Ref Nat) : IO Unit := do
  let ck := check failures count
  IO.FS.writeFile (root / "Imported.tla") "---- MODULE Imported ----\nK == 1\n====\n"
  IO.FS.writeFile (root / "MiniCorpus.tla")
    "---- MODULE MiniCorpus ----\nEXTENDS Imported\nVARIABLES nk, action_taken\n====\n"
  IO.FS.writeFile (root / "a.json") raw
  IO.FS.writeFile (root / "b.json") (raw ++ "\n")
  IO.FS.writeBinFile (root / "plan.json")
    (Codec.ModelInterfaceTraceProjectionJson.canonicalPlanFileBytes plan)
  let paths : ProjectCorpusPaths := {
    spec := (root / "MiniCorpus.tla").toString
    evidence := [(root / "a.json").toString, (root / "b.json").toString]
    projection := (root / "plan.json").toString
    out := (root / "published").toString }
  let .ok compiled ← compileProjectCorpus paths
    | throw (IO.userError "happy corpus compilation failed")
  let .ok reversed ← compileProjectCorpus { paths with evidence := paths.evidence.reverse }
    | throw (IO.userError "reversed corpus compilation failed")
  ck "input permutation preserves complete publication bytes"
    (compiled.files == reversed.files && compiled.manifestSha256 == reversed.manifestSha256)
  ck "compilation creates no output directory" (!(← (root / "published").pathExists))
  ck "complete imported source closure is retained" (compiled.manifest.sources.length == 2)
  ck "distinct raw inputs retain both pairs despite identical projected output"
    (compiled.manifest.members.length == 2 &&
      (compiled.manifest.members.map (·.trace.sha256)).eraseDups.length == 1 &&
      compiled.files.length == 6)
  ck "manifest hash includes canonical final LF"
    (compiled.manifestSha256 == Sha256.digestHex compiled.manifestBytes &&
      compiled.manifestSha256 != Sha256.digestHex
        (Codec.ModelInterfaceJson.canonicalBytes
          (Codec.ModelInterfaceCorpusJson.encodeManifest compiled.manifest)))
  ck "output domain hash differs from ordinary LF-inclusive trace hash"
    (compiled.manifest.members.all fun m => m.outputSha256 != m.trace.sha256)
  ck "workflow member retains domain receipt identity separately from file hash"
    (compiled.members.zip compiled.manifest.members |>.all fun (a,b) =>
      a.workflowEvidence.projection.any fun p => p.receiptSha256 != b.receipt.sha256)
  let .ok _ ← projectCorpus paths | throw (IO.userError "happy corpus publication failed")
  ck "complete corpus verifies" (!(rejected (← checkCorpus paths.out compiled.manifestSha256)))
  ck "wrong expected manifest identity rejects"
    (rejected (← checkCorpus paths.out (String.ofList (List.replicate 64 '0'))))
  ck "existing output refuses replacement" (rejected (← projectCorpus paths))
  ck "existing manifest unchanged" ((← IO.FS.readBinFile (root / "published" / "manifest.json")) == compiled.manifestBytes)
  for name in ["manifest.json", "projection.json"] ++
      compiled.manifest.members.flatMap (fun m => [m.trace.path,m.receipt.path]) do
    let target := root / "published" / name
    let original ← IO.FS.readBinFile target
    IO.FS.writeBinFile target (original.push 32)
    ck s!"tampered {name} rejects" (rejected (← checkCorpus paths.out compiled.manifestSha256))
    IO.FS.writeBinFile target original
  IO.FS.writeFile (root / "published" / "extra.json") "{}\n"
  ck "extra unmanifested member rejects" (rejected (← checkCorpus paths.out compiled.manifestSha256))
  IO.FS.removeFile (root / "published" / "extra.json")
  for failAt in [0,1,compiled.files.length] do
    let target := (root / s!"injected-{failAt}").toString
    let result ← Shell.ModelInterface.Publication.publishDirectory target compiled.files (some failAt)
    ck s!"injected staging failure {failAt} rejects" (rejected result)
    ck s!"injected staging failure {failAt} leaves no destination" (!(← (target : System.FilePath).pathExists))
    ck s!"injected staging failure {failAt} cleans all owned staging and lock" (← noStage root)
  let invalidOut := root / "invalid"
  IO.FS.writeFile (root / "bad.json") "{"
  let invalid ← projectCorpus { paths with evidence := paths.evidence ++ [(root / "bad.json").toString], out := invalidOut.toString }
  ck "bad later input rejects without any publication" (rejected invalid && !(← invalidOut.pathExists) && (← noStage root))
  let duplicate ← projectCorpus { paths with evidence := paths.evidence ++ [paths.evidence.head!], out := invalidOut.toString }
  ck "duplicate raw input rejects without publication" (rejected duplicate && !(← invalidOut.pathExists))
  IO.FS.writeFile (root / "conflict.json") (raw.replace "(Int -> Int)" "(Int -> Bool)")
  let conflict ← projectCorpus { paths with evidence := paths.evidence ++ [(root / "conflict.json").toString], out := invalidOut.toString }
  ck "conflicting structural facts reject without publication" (rejected conflict && !(← invalidOut.pathExists))
  IO.FS.writeFile (root / "overlap.json") (raw.replace "\"init\"" "\"step\"")
  let overlap ← projectCorpus { paths with evidence := paths.evidence ++ [(root / "overlap.json").toString], out := invalidOut.toString }
  ck "cross-phase labels reject without publication" (rejected overlap && !(← invalidOut.pathExists))
  let excess ← compileProjectCorpus { paths with evidence := List.replicate (maxCorpusMembersV1 + 1) paths.evidence.head! }
  ck "member count bound rejects before reading" (rejected excess)
  IO.FS.writeFile (root / "locked.model-interface-directory.lock") "OTHER-OWNER\n"
  let locked ← Shell.ModelInterface.Publication.publishDirectory (root / "locked").toString compiled.files
  ck "cooperating publisher lock refuses and preserves owner"
    (rejected locked && (← IO.FS.readFile (root / "locked.model-interface-directory.lock")) == "OTHER-OWNER\n")
  IO.FS.removeFile (root / "locked.model-interface-directory.lock")
  let unsafeResult ← Shell.ModelInterface.Publication.publishDirectory (root / "unsafe").toString [("../escape", "no".toUTF8)]
  ck "unsafe member path rejects before staging" (rejected unsafeResult && (← noStage root))
  let aliasResult ← Shell.ModelInterface.Publication.publishDirectory (root / "alias").toString [("A", ByteArray.empty),("a", ByteArray.empty)]
  ck "portable filename collisions reject before staging" (rejected aliasResult && (← noStage root))
  IO.FS.createDir (root / "empty")
  let empty ← Shell.ModelInterface.Publication.publishDirectory (root / "empty").toString compiled.files
  ck "pre-existing empty destination refuses replacement" (rejected empty && (← (root / "empty").readDir).isEmpty)
  if !System.Platform.isWindows then
    let link ← IO.Process.output { cmd := "ln", args := #["-s", (root / "published").toString, (root / "link").toString] }
    if link.exitCode != 0 then throw (IO.userError link.stderr)
    ck "symlink corpus root rejects" (rejected (← checkCorpus (root / "link").toString compiled.manifestSha256))
    IO.FS.removeFile (root / "link")
  ck "successful and refused publications leave no owned staging" (← noStage root)

def main : IO UInt32 := do
  let failures ← IO.mkRef ([] : List String)
  let count ← IO.mkRef 0
  let nonce ← IO.monoNanosNow
  let root : System.FilePath := s!"/tmp/mirrors-corpus-spec-{nonce}"
  IO.FS.createDir root
  try
    run root failures count
  catch error => failures.modify (· ++ [s!"unexpected exception: {error}"])
  finally IO.FS.removeDirAll root
  let errors ← failures.get
  for error in errors do IO.eprintln s!"FAIL: {error}"
  IO.println s!"model-interface corpus: {(← count.get) - errors.length}/{← count.get} checks passed"
  return if errors.isEmpty then 0 else 1

end ModelInterfaceCorpusSpec

def main : IO UInt32 := ModelInterfaceCorpusSpec.main
