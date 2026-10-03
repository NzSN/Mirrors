import Shell.ModelInterface.Compiler

/-! Always-on source and deterministic-publication tests for mirrorlean-v1.
Native execution is tools/model-interface-lean/check.sh against MirrorLean. -/
namespace ModelInterfaceLeanSpec
open Core.ModelInterface
open Shell.ModelInterface

private def require (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)

private def expectCode (lock : LockedModelInterface) (code : String) : IO Unit :=
  match Emit.Lean.emitLean lock with
  | .ok _ => throw (IO.userError s!"expected rejection {code}")
  | .error ds => require (ds.any (·.code == code)) s!"missing rejection {code}"

def structuralType : ModelType := .record [
  { wireName := "bool", type := .bool },
  { wireName := "integer", type := .int },
  { wireName := "map", type := .map .str (.seq .int) },
  { wireName := "null", type := .null },
  { wireName := "record", type := .record [{ wireName := "tag", type := .str }] },
  { wireName := "seq", type := .seq .int },
  { wireName := "set", type := .set (.set .int) },
  { wireName := "tuple", type := .tuple [.bool, .str] },
  { wireName := "variant", type := .variant [
    { tag := "none", payload := .null }, { tag := "some", payload := .int }] }]

def run : IO Unit := do
  let lock ← match ← Compiler.loadVerifiedLock
      "test/fixtures/model-interface/counter/Counter.mirror-interface.lock.json" with
    | .ok lock => pure lock
    | .error e => throw (IO.userError e.message)
  require (Compiler.supportedTarget "mirrorlean-v1") "Lean target unregistered"
  let generated ← match Compiler.emitTarget "mirrorlean-v1" lock with
    | .ok tree => pure tree
    | .error e => throw (IO.userError e.message)
  require (generated.files.length == 2) "expected Lean module and manifest"
  for file in generated.files do
    let actual ← IO.FS.readBinFile
      ("test/fixtures/model-interface/counter/generated-lean/" ++ file.relativePath)
    require (actual == file.bytes) s!"stale generated Lean fixture: {file.relativePath}"
  let reordered := { lock with
    initializers := lock.initializers.reverse, actions := lock.actions.reverse,
    observations := lock.observations.reverse }
  let other ← match Emit.Lean.emitLean reordered with
    | .ok tree => pure tree
    | .error _ => throw (IO.userError "reordered emission failed")
  require ((generated.files.map (·.bytes)) == (other.files.map (·.bytes)))
    "emission depends on source declaration order"
  expectCode { lock with actions := lock.actions ++ [
    { id := "Observe", phase := .transition, wireAction := "observe" }] } "MIC-E-NAME-001"
  expectCode { lock with observations := [{ id := "End", wireName := "x", type := .int }] }
    "MIC-E-NAME-001"
  expectCode { lock with observations := [
    { id := "Value", wireName := "x", type := .map .int .str }] } "MIC-E-TYPE-001"
  expectCode { lock with observations := [
    { id := "Value", wireName := "x", type := .opaqueItf "unknown" }] } "MIC-E-TYPE-001"
  let badAction : ResolvedAction := {
    id := "Read", phase := .transition, wireAction := "read"
    inputs := [{ id := "Value", projection := {
      root := .stepParameters, path := [.mapKey (.str "key")], type := .int } }] }
  expectCode { lock with actions := [badAction] } "MIC-E-PATH-001"
  let initializer : ResolvedAction := {
    id := "Initialize", phase := .initialize, wireAction := "init", wireAliases := ["reset"]
    inputs := [{ id := "Payload", projection := {
      root := .initialState, path := [.field "payload"], type := structuralType } }] }
  let structural := { lock with
    modelModule := "Types", actions := [], initializers := [initializer]
    observations := [{ id := "Payload", wireName := "payload", type := structuralType }] }
  let tree ← match Emit.Lean.emitLean structural with
    | .ok tree => pure tree
    | .error _ => throw (IO.userError "structural Lean emission failed")
  IO.FS.createDirAll ".golden-build/model-interface-lean"
  for file in tree.files do
    IO.FS.writeBinFile (".golden-build/model-interface-lean/" ++ file.relativePath) file.bytes
  let emptyVariantType := ModelType.seq (.variant [])
  let emptyVariantInitializer := { initializer with inputs := [{ id := "Payload", projection := {
    root := .initialState, path := [.field "payload"], type := emptyVariantType } }] }
  let emptyVariantLock := { structural with
    modelModule := "EmptyVariants", initializers := [emptyVariantInitializer]
    observations := [{ id := "Payload", wireName := "payload", type := emptyVariantType }] }
  let emptyVariantTree ← match Emit.Lean.emitLean emptyVariantLock with
    | .ok tree => pure tree
    | .error _ => throw (IO.userError "empty-variant Lean emission failed")
  for file in emptyVariantTree.files do
    if file.relativePath.endsWith ".lean" then
      IO.FS.writeBinFile (".golden-build/model-interface-lean/" ++ file.relativePath) file.bytes
  IO.println "model_interface_lean_spec: 10 checks passed; structural and empty-variant native corpora emitted"
end ModelInterfaceLeanSpec

def main : IO Unit := ModelInterfaceLeanSpec.run
