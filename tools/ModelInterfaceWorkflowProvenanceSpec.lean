import Shell.ModelInterface.Compiler

/-! Reviewed workflow identities are build metadata. These tests exercise exact
legacy bytes, strict v2 admission, semantic independence, captured source closure,
and the public read-only preflight path. No model checker is invoked. -/
namespace ModelInterfaceWorkflowProvenanceSpec

open Core.ModelInterface
open Shell.ModelInterface.Compiler

abbrev Failures := IO.Ref (Nat × List String)

private def check (failures : Failures) (name : String) (condition : Bool) : IO Unit := do
  failures.modify fun (count, found) =>
    (count + 1, if condition then found else found ++ [name])

private def digest (value : String) : String := Sha256.digestHex value.toUTF8

private def unwrap {α : Type} [ToString ε] (result : Except ε α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw (IO.userError (toString error))

private def unwrapCompiler (result : Except CompilerError α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw (IO.userError error.message)

private def replaceField (json : Lean.Json) (name : String) (value : Lean.Json) : Lean.Json :=
  match json with
  | .obj fields => Lean.Json.mkObj ((name, value) :: fields.toList.filter (·.1 != name))
  | other => other

private def asCompilation (lock : LockedModelInterface) : Compilation := {
  resolved := {
    toSemanticDescriptor := lock.semanticDescriptor
    contract := lock.contract
    provenance := lock.provenance }
  lock
  descriptorBytes := Codec.ModelInterfaceJson.canonicalSemanticDescriptorBytes lock.semanticDescriptor
  provenanceBytes := Codec.ModelInterfaceJson.canonicalProvenanceBytes lock.provenance
  lockBytes := Codec.ModelInterfaceJson.canonicalFileBytes (Codec.ModelInterfaceJson.encodeLock lock)
  diagnostics := []
}

private def testIdentity (failures : Failures) (legacy : Compilation)
    (workflow : WorkflowProvenance) : IO Compilation := do
  let compilation ← unwrapCompiler (attachWorkflow legacy workflow)
  check failures "workflow uses v2 schema"
    ((Codec.ModelInterfaceJson.encodeLock compilation.lock).getObjValAs? String "schema" == .ok lockSchemaV2)
  check failures "workflow leaves semantic bytes and digest unchanged"
    (compilation.descriptorBytes == legacy.descriptorBytes &&
      compilation.lock.semanticDigest == legacy.lock.semanticDigest)
  check failures "workflow changes provenance"
    (compilation.lock.provenanceDigest != legacy.lock.provenanceDigest)
  let roundtrip ← unwrap (Codec.ModelInterfaceJson.parseLockBytes compilation.lockBytes)
  check failures "workflow roundtrips canonical bytes"
    (Codec.ModelInterfaceJson.canonicalFileBytes (Codec.ModelInterfaceJson.encodeLock roundtrip) == compilation.lockBytes)
  check failures "workflow lock verifies" (verifyLock roundtrip).isOk
  for (label, changed) in [
      ("proposal", { workflow with proposalSha256 := digest "other proposal" }),
      ("review", { workflow with reviewSha256 := digest "other review" }),
      ("raw bytes", { workflow with members := workflow.members.map fun member =>
        { member with rawFileSha256 := digest "other raw bytes" } }),
      ("structural evidence", { workflow with members := workflow.members.map fun member =>
        { member with evidenceSha256 := digest "other structural evidence" } })] do
    let updated ← unwrapCompiler (attachWorkflow legacy changed)
    check failures (label ++ " changes provenance only")
      (updated.lock.provenanceDigest != compilation.lock.provenanceDigest &&
        updated.lock.semanticDigest == compilation.lock.semanticDigest)
  let lockJson := Codec.ModelInterfaceJson.encodeLock compilation.lock
  check failures "v1 rejects workflow metadata"
    (Codec.ModelInterfaceJson.decodeLock (replaceField lockJson "schema" (.str lockSchemaV1))).isOk.not
  check failures "v2 requires workflow metadata"
    (Codec.ModelInterfaceJson.decodeLock (replaceField (Codec.ModelInterfaceJson.encodeLock legacy.lock) "schema" (.str lockSchemaV2))).isOk.not
  let some member := workflow.members.head?
    | throw (IO.userError "missing workflow member")
  for (label, changed) in [
      ("empty", { workflow with members := [] }),
      ("duplicate", { workflow with members := [member, member] }),
      ("bound", { workflow with members := List.replicate (maxWorkflowMembersV1 + 1) member }),
      ("invalid hex", { workflow with reviewSha256 := String.ofList (List.replicate 64 'A') }),
      ("partial projection", { workflow with projectionPlanSha256 := some (digest "plan") }),
      ("unprojected corpus", { workflow with corpusManifestSha256 := some (digest "manifest") })] do
    check failures (label ++ " workflow rejects") (attachWorkflow legacy changed).isOk.not
  let first := { member with rawFileSha256 := String.ofList (List.replicate 64 '0') }
  let second := { member with rawFileSha256 := String.ofList (List.replicate 64 '1') }
  let ordered := { workflow with members := [first, second] }
  check failures "in-memory unsorted members reject"
    (attachWorkflow legacy { ordered with members := [second, first] }).isOk.not
  let unsortedJson := replaceField (Codec.ModelInterfaceJson.encodeWorkflowProvenance ordered) "members"
    (.arr #[Codec.ModelInterfaceJson.encodeWorkflowEvidenceMember second, Codec.ModelInterfaceJson.encodeWorkflowEvidenceMember first])
  check failures "decoded unsorted members reject" (Codec.ModelInterfaceJson.decodeWorkflowProvenance unsortedJson).isOk.not
  check failures "unknown workflow field rejects"
    (Codec.ModelInterfaceJson.decodeWorkflowProvenance (replaceField (Codec.ModelInterfaceJson.encodeWorkflowProvenance workflow)
      "unknown" (.bool true))).isOk.not
  check failures "null optional digest rejects"
    (Codec.ModelInterfaceJson.decodeWorkflowProvenance (replaceField (Codec.ModelInterfaceJson.encodeWorkflowProvenance workflow)
      "projectionPlanSha256" .null)).isOk.not
  let projection : WorkflowProjectionMember := {
    outputSha256 := digest "output"
    evidenceSha256 := member.evidenceSha256
    fileSha256 := member.rawFileSha256
    receiptSha256 := digest "receipt"
  }
  let projected := { workflow with
    projectionPlanSha256 := some (digest "plan")
    corpusManifestSha256 := some (digest "manifest")
    members := [{ member with projection := some projection }] }
  let projectedCompilation ← unwrapCompiler (attachWorkflow legacy projected)
  let changeProjection (value : WorkflowProjectionMember) :=
    { projected with members := [{ member with projection := some value }] }
  for (label, changed) in [
      ("plan", { projected with projectionPlanSha256 := some (digest "other plan") }),
      ("corpus", { projected with corpusManifestSha256 := some (digest "other corpus") }),
      ("projected canonical output", changeProjection { projection with outputSha256 := digest "other output" }),
      ("receipt", changeProjection { projection with receiptSha256 := digest "other receipt" }),
      ("projected bytes", changeProjection { projection with fileSha256 := digest "other bytes" }),
      ("projected structural evidence", changeProjection { projection with evidenceSha256 := digest "other projected evidence" })] do
    let updated ← unwrapCompiler (attachWorkflow legacy changed)
    check failures (label ++ " changes provenance only")
      (updated.lock.provenanceDigest != projectedCompilation.lock.provenanceDigest &&
        updated.lock.semanticDigest == projectedCompilation.lock.semanticDigest)
  check failures "projected membership accepts declared file and structure"
    (workflowAdmitsTrace projected projection.fileSha256 projection.evidenceSha256)
  check failures "projected membership rejects changed bytes"
    (!workflowAdmitsTrace projected (digest "mutation") projection.evidenceSha256)
  check failures "projected membership rejects changed structure"
    (!workflowAdmitsTrace projected projection.fileSha256 (digest "mutation"))
  let oldTree ← unwrap (Shell.ModelInterface.Emit.SuiteBundle.emit legacy.lock |>.mapError reprStr)
  let newTree ← unwrap (Shell.ModelInterface.Emit.SuiteBundle.emit compilation.lock |>.mapError reprStr)
  let companion (tree : Shell.ModelInterface.Emit.TypeScript.GeneratedTree) :=
    tree.files.find? (·.relativePath.endsWith ".suite.ts") |>.map (fun file =>
      String.fromUTF8! file.bytes) |>.getD ""
  check failures "v1 suite handle keeps legacy fields"
    (!(companion oldTree).contains "provenanceDigest:")
  check failures "workflow suite handle binds provenance"
    ((companion newTree).contains ("provenanceDigest: \"" ++ compilation.lock.provenanceDigest ++ "\""))
  return projectedCompilation

private def testCapturedSources (failures : Failures) (root : System.FilePath)
    (raw : ByteArray) : IO Unit := do
  let spec := root / "Captured.tla"
  let helper := root / "Helper.tla"
  IO.FS.writeFile spec "---- MODULE Captured ----\nEXTENDS Helper\nVARIABLES count, parameters, action_taken\n====\n"
  IO.FS.writeFile helper "---- MODULE Helper ----\nHelperValue == 1\n====\n"
  let captured ← unwrapCompiler (← analyzeSource spec.toString)
  let base ← unwrapCompiler (loadProjectionBaseFromCapture captured spec.toString "trace.itf.json" raw)
  check failures "projection base retains imported source closure"
    (base.sources.length == 2 && base.sources.any (·.moduleName == "Helper"))
  IO.FS.writeFile helper "---- MODULE Helper ----\nHelperValue == 2\n====\n"
  let same ← unwrapCompiler (loadProjectionBaseFromCapture captured spec.toString "trace.itf.json" raw)
  check failures "captured base never rereads imported sources" (base.sources == same.sources)
  let fresh ← unwrapCompiler (← loadProjectionBase spec.toString
    (root / "trace.itf.json").toString)
  check failures "fresh capture identifies changed import" (base.sources != fresh.sources)

def run : IO UInt32 := do
  let failures ← IO.mkRef (0, ([] : List String))
  let fixture := "test/fixtures/model-interface/counter/"
  let lockBytes ← IO.FS.readBinFile (fixture ++ "Counter.mirror-interface.lock.json")
  let lock ← unwrap (Codec.ModelInterfaceJson.parseLockBytes lockBytes)
  check failures "v1 golden bytes unchanged" (Codec.ModelInterfaceJson.canonicalFileBytes (Codec.ModelInterfaceJson.encodeLock lock) == lockBytes)
  let raw ← IO.FS.readBinFile (fixture ++ "counter.itf.json")
  let evidence ← unwrap (Shell.ModelInterface.Evidence.fromString (String.fromUTF8! raw) "counter")
  let workflow : WorkflowProvenance := {
    proposalSha256 := digest "proposal"
    reviewSha256 := digest "review"
    members := [{rawFileSha256 := Sha256.digestHex raw, evidenceSha256 := evidence.evidenceSha256}]
  }
  let compilation ← testIdentity failures (asCompilation lock) workflow
  let root ← IO.FS.createTempDir
  try
    let tracePath := root / "trace.itf.json"
    let lockPath := root / "lock.json"
    IO.FS.writeBinFile tracePath raw
    IO.FS.writeBinFile lockPath compilation.lockBytes
    let accepted ← runPreflight lockPath.toString tracePath.toString true
    check failures "public workflow preflight accepts member"
      (match accepted with | .ok result => result.result.diagnostics.isEmpty | .error _ => false)
    IO.FS.writeBinFile tracePath (raw.append " ".toUTF8)
    check failures "public workflow preflight rejects same-shape changed bytes"
      (← runPreflight lockPath.toString tracePath.toString).isOk.not
    IO.FS.writeBinFile tracePath raw
    testCapturedSources failures root raw
  finally
    IO.FS.removeDirAll root
  let (count, found) ← failures.get
  for failure in found do IO.eprintln s!"FAIL: {failure}"
  if found.isEmpty then
    IO.println s!"PASS: {count}/{count} workflow provenance checks (identities, strict locks, source capture, member preflight)"
    return 0
  return 1

end ModelInterfaceWorkflowProvenanceSpec

def main : IO UInt32 := ModelInterfaceWorkflowProvenanceSpec.run
