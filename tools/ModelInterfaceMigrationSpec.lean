import Shell.ModelInterface.Migration
import Core.ModelInterface.Sha256

namespace ModelInterfaceMigrationSpec
open Core.ModelInterface Shell.ModelInterface.Compiler Lean

private def domainDigest := Core.ModelInterface.Sha256.digestDomainHex

private def resign (lock : LockedModelInterface) : LockedModelInterface :=
  let provenance := { lock.provenance with
    contractSha256 := domainDigest contractDigestDomain
      (Codec.ModelInterfaceJson.canonicalBytes (Codec.ModelInterfaceJson.encodeContract lock.contract)) }
  { lock with
    semanticDigest := domainDigest descriptorDigestDomain
      (Codec.ModelInterfaceJson.canonicalSemanticDescriptorBytes lock.semanticDescriptor)
    provenance := provenance
    provenanceDigest := domainDigest provenanceDigestDomain
      (Codec.ModelInterfaceJson.canonicalProvenanceBytes provenance) }

private def invoke (old new : String) (extra : Array String := #[]) : IO IO.Process.Output :=
  IO.Process.output {
    cmd := ".lake/build/bin/model_interface_gen"
    args := #["compare-locks", "--from-lock", old, "--to-lock", new] ++ extra }

private def kind (output : IO.Process.Output) : String :=
  ((Json.parse output.stdout).toOption.bind fun json =>
    (json.getObjValAs? String "kind").toOption).getD "invalid"

def run : IO UInt32 := do
  let failures ← IO.mkRef ([] : List String)
  let checks ← IO.mkRef (0 : Nat)
  let check := fun (name : String) (condition : Bool) => do
    checks.modify (· + 1)
    unless condition do failures.modify (· ++ [name])
  let root ← IO.FS.createTempDir
  try
    let originalPath := "test/fixtures/model-interface/counter/Counter.mirror-interface.lock.json"
    let lock ← match ← loadVerifiedLock originalPath with
      | .ok lock => pure lock
      | .error error => throw (IO.userError s!"fixture: {repr error}")
    let originalBytes ← IO.FS.readBinFile originalPath
    let write := fun (name : String) (value : LockedModelInterface) => do
      let path := root / name
      IO.FS.writeBinFile path (Codec.ModelInterfaceJson.canonicalFileBytes
        (Codec.ModelInterfaceJson.encodeLock value))
      return path.toString
    let equal ← write "equal.json" lock
    let same ← invoke originalPath equal
    check "equal validated locks compare" (same.exitCode == 0 && kind same == "unchanged")
    let changedProvenance := resign { lock with provenance :=
      { lock.provenance with compilerVersion := "migration-test/2" } }
    let provenance ← write "provenance.json" changedProvenance
    let metadata ← invoke originalPath provenance
    check "provenance change preserves semantic identity"
      (metadata.exitCode == 0 && kind metadata == "provenance_only")
    if let .ok report := Json.parse metadata.stdout then
      check "provenance-only migration keeps exact semantic identity"
        ((report.getObjValAs? Bool "semanticIdentityMatches").toOption == some true)
      check "provenance-only migration refreshes artifacts without semantic regeneration"
        ((report.getObjValAs? Bool "requiresArtifactRefresh").toOption == some true &&
          (report.getObjValAs? Bool "requiresRegeneration").toOption == some false)
    else check "provenance report JSON" false
    let reviewed := resign { lock with provenance := { lock.provenance with
      workflow := some {
        proposalSha256 := lock.provenance.contractSha256
        reviewSha256 := lock.provenance.evidenceSha256
        members := [{ rawFileSha256 := lock.provenance.contractSha256
                      evidenceSha256 := lock.provenance.evidenceSha256 }] } } }
    let reviewedPath ← write "reviewed-v2.json" reviewed
    let reviewedResult ← invoke originalPath reviewedPath
    check "v1-to-reviewed-v2 migration stays provenance-only"
      (reviewedResult.exitCode == 0 && kind reviewedResult == "provenance_only")
    let semantic := resign { lock with
      interfaceVersion := "2.0.0"
      contract := { lock.contract with interfaceVersion := "2.0.0" } }
    let changed ← write "changed.json" semantic
    let difference ← invoke originalPath changed
    check "semantic change requires inspection" (difference.exitCode == 0 && kind difference == "semantic_change")
    if let .ok json := Json.parse difference.stdout then
      check "semantic report requires regeneration"
        ((json.getObjValAs? Bool "requiresRegeneration").toOption == some true)
      check "semantic report refuses runtime compatibility claim"
        ((json.getObjValAs? Bool "runtimeCompatibilityVerified").toOption == some false)
      check "semantic section delta is exact"
        ((json.getObjValAs? (List String) "changedSemanticSections").toOption == some ["interfaceVersion"])
    else check "semantic report JSON" false
    let reordered ← write "reordered.json" { lock with
      actions := lock.actions.reverse
      observations := lock.observations.reverse }
    let normalized ← invoke originalPath reordered
    check "canonical ordering does not create semantic change"
      (normalized.exitCode == 0 && kind normalized == "unchanged")
    if let first :: rest := lock.actions then
      let actionLock := resign { lock with actions := { first with wireAction := "migrationAction" } :: rest }
      let actionPath ← write "action-change.json" actionLock
      let actionResult ← invoke originalPath actionPath
      let sections := (Json.parse actionResult.stdout).toOption.bind fun json =>
        (json.getObjValAs? (List String) "changedSemanticSections").toOption
      check "action change is reported" (actionResult.exitCode == 0 && sections == some ["actions"])
    else check "action fixture exists" false
    if let first :: rest := lock.observations then
      let observationLock := resign { lock with observations := { first with type := .str } :: rest }
      let observationPath ← write "observation-change.json" observationLock
      let observationResult ← invoke originalPath observationPath
      let sections := (Json.parse observationResult.stdout).toOption.bind fun json =>
        (json.getObjValAs? (List String) "changedSemanticSections").toOption
      check "observation type change is reported"
        (observationResult.exitCode == 0 && sections == some ["observations"])
    else check "observation fixture exists" false
    let unknown := root / "unknown.json"
    let duplicate := root / "duplicate.json"
    let raw := (Codec.ModelInterfaceJson.canonicalFileBytes
      (Codec.ModelInterfaceJson.encodeLock lock))
    let text := String.fromUTF8! raw
    IO.FS.writeFile unknown ("{\"unknownMigrationField\":true," ++ (text.drop 1).toString)
    IO.FS.writeFile duplicate ("{\"schema\":\"mirrors.model-interface-lock/v1\"," ++ (text.drop 1).toString)
    check "unknown input fields rejected" ((← invoke originalPath unknown.toString).exitCode != 0)
    check "duplicate input fields rejected" ((← invoke originalPath duplicate.toString).exitCode != 0)
    let tampered ← write "tampered.json" { lock with semanticDigest := String.ofList (List.replicate 64 'f') }
    let invalid ← invoke originalPath tampered
    check "tampered semantic digest refuses comparison" (invalid.exitCode != 0)
    let badProvenance ← write "tampered-provenance.json"
      { lock with provenanceDigest := String.ofList (List.replicate 64 'f') }
    check "tampered provenance digest refuses comparison"
      ((← invoke originalPath badProvenance).exitCode != 0)
    let missing ← invoke originalPath (root / "missing.json").toString
    check "missing input rejected" (missing.exitCode != 0)
    let wrongFlag ← invoke originalPath equal #["--out", (root / "forbidden").toString]
    check "foreign output option rejected without writes"
      (wrongFlag.exitCode == 2 && !(← (root / "forbidden").pathExists))
    check "duplicate option rejected"
      ((← invoke originalPath equal #["--from-lock", originalPath]).exitCode == 2)
    check "other commands reject migration flags"
      ((← IO.Process.output {
        cmd := ".lake/build/bin/model_interface_gen"
        args := #["generate", "--from-lock", equal]}).exitCode == 2)
    let jsonMode ← invoke originalPath provenance #["--diagnostics", "json"]
    check "JSON diagnostics success stays one parseable report"
      (jsonMode.exitCode == 0 && (Json.parse jsonMode.stdout).isOk)
    check "original input remains byte-identical"
      ((← IO.FS.readBinFile originalPath) == originalBytes)
    check "candidate input remains byte-identical"
      ((← IO.FS.readBinFile equal) == Codec.ModelInterfaceJson.canonicalFileBytes
        (Codec.ModelInterfaceJson.encodeLock lock))
  finally IO.FS.removeDirAll root
  let errors ← failures.get
  for error in errors do IO.eprintln s!"FAIL migration: {error}"
  IO.println s!"MODEL INTERFACE MIGRATION {← checks.get} checks, {errors.length} failures"
  return if errors.isEmpty then 0 else 1

end ModelInterfaceMigrationSpec

def main : IO UInt32 := ModelInterfaceMigrationSpec.run
