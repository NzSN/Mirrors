import Core.ModelInterface.Conformance
import Codec.ModelInterfaceJson
import Codec.Json
import Shell.ModelInterface.Emit.TypeScript
import Shell.ModelInterface.Emit.TypeScriptAsync
import Shell.ModelInterface.Emit.Cpp
import Shell.ModelInterface.Emit.Rust
import Shell.ModelInterface.Emit.Lean

/-! Shared executable MITL judgments and fresh native conformance artifacts.
The synthetic interfaces below are test inputs, never production evidence. -/
namespace ModelInterfaceLanguageSpec
open Lean Core.ModelInterface

def fixtures : System.FilePath := "test/fixtures/model-interface/language"
def get (j : Json) (key : String) : IO Json :=
  IO.ofExcept (j.getObjVal? key)
def str (j : Json) (key : String) : IO String :=
  IO.ofExcept ((j.getObjVal? key).bind Json.getStr?)
def bool (j : Json) (key : String) (fallback := false) : Bool :=
  ((j.getObjVal? key).bind Json.getBool?).toOption.getD fallback
def check (name : String) (condition : Bool) : IO Unit :=
  unless condition do throw (IO.userError s!"MITL fixture failed: {name}")
def rows (name : String) : IO (List Json) := do
  let text ← IO.FS.readFile (fixtures / name)
  (text.splitOn "\n" |>.filter (!·.isEmpty)).mapM fun line =>
    IO.ofExcept (Json.parse line)
def decodeType (json : Json) : IO ModelType := IO.ofExcept (Codec.ModelInterfaceJson.decodeModelType json)
def typeFor (types : List (String × ModelType)) (row : Json) : IO ModelType := do
  let name ← str row "typeId"
  match types.lookup name with
  | some type => pure type
  | none => throw (IO.userError s!"unknown fixture type: {name}")
def decoded (json : Json) : Option Value := (Codec.decodeValue json).toOption
def path (json : Json) : IO (List PathSegment) := do
  let entries ← IO.ofExcept json.getArr?
  entries.toList.mapM fun entry => do
    if let .ok value := entry.getObjVal? "field" then
      return .field (← IO.ofExcept value.getStr?)
    if let .ok value := entry.getObjVal? "index" then
      return .index (← IO.ofExcept value.getNat?)
    if let .ok value := entry.getObjVal? "variantValue" then
      return .variantValue (← IO.ofExcept value.getStr?)
    let key ← get entry "mapKey"
    match ← str key "kind" with
    | "str" => return .mapKey (.str (← str key "value"))
    | _ => throw (IO.userError "fixture map projection expects a string key")

def lower (name : String) : String := Shell.ModelInterface.Emit.TypeScript.Shared.lowerName name

def contractAction (a : ResolvedAction) : ContractAction := {
  id := a.id, wireAction := a.wireAction, wireAliases := a.wireAliases
  inputs := a.inputs.map fun i => {
    id := i.id, fromRoot := i.projection.root, path := i.projection.path } }

def makeLock (base : LockedModelInterface) (name : String)
    (initializers actions : List ResolvedAction)
    (observations : List ResolvedObservation) : LockedModelInterface := Id.run do
  let contract := { base.contract with
    model := { base.contract.model with moduleName := name }
    initializers := initializers.map contractAction
    actions := actions.map contractAction
    observations := observations.map fun o => {
      id := o.id, wireName := o.wireName, provenance := .implementation } }
  let lock := { base with modelModule := name, contract, initializers, actions, observations }
  let digest := Sha256.digestDomainHex "mirrors-model-interface-lock/v1"
    (Codec.ModelInterfaceJson.canonicalSemanticDescriptorBytes lock.toSemanticDescriptor)
  return { lock with semanticDigest := digest }

def emitters : List (String × (LockedModelInterface → Shell.ModelInterface.Emit.TypeScript.EmitResult Shell.ModelInterface.Emit.TypeScript.GeneratedTree)) := [
  ("ts", Shell.ModelInterface.Emit.TypeScript.emitTypeScript),
  ("async", Shell.ModelInterface.Emit.TypeScriptAsync.emitTypeScriptAsync),
  ("async-v2", fun lock => Shell.ModelInterface.Emit.TypeScriptAsync.emitTypeScriptAsync lock "mirrorecma-async-v2"),
  ("cpp", Shell.ModelInterface.Emit.Cpp.emitCpp),
  ("cpp-v2", fun lock => Shell.ModelInterface.Emit.Cpp.emitCpp lock "mirrorcpp-v2"),
  ("rust", Shell.ModelInterface.Emit.Rust.emitRust),
  ("rust-v2", fun lock => Shell.ModelInterface.Emit.Rust.emitRust lock "mirrorrust-v2"),
  ("lean", Shell.ModelInterface.Emit.Lean.emitLean)]

def emit (output : System.FilePath) (lock : LockedModelInterface) : IO Unit := do
  for (target, generate) in emitters do
    let tree ← match generate lock with
      | .ok tree => pure tree
      | .error ds => throw (IO.userError s!"{target}/{lock.modelModule}: {reprStr ds}")
    let dir := output / target / lock.modelModule
    IO.FS.createDirAll dir
    for file in tree.files do
      IO.FS.writeBinFile (dir / file.relativePath) file.bytes
    IO.FS.writeBinFile (dir / "synthetic.lock.json") (Codec.ModelInterfaceJson.canonicalFileBytes (Codec.ModelInterfaceJson.encodeLock lock))

def run (output : System.FilePath) : IO Unit := do
  let atDepth := (List.replicate (maxStructuralTypeDepthV1 - 1) ()).foldl
    (fun type _ => ModelType.seq type) .int
  check "versioned type depth boundary" (Core.ModelInterface.Conformance.typeWellFormed atDepth)
  check "versioned type depth overflow" (!Core.ModelInterface.Conformance.typeWellFormed (.seq atDepth))
  check "versioned normalized node overflow"
    (!Core.ModelInterface.Conformance.typeWellFormed (.tuple (List.replicate maxNormalizedTypeNodesV1 .int)))
  check "versioned wire-name byte overflow"
    (!Core.ModelInterface.Conformance.typeWellFormed (.record [{
      wireName := String.ofList (List.replicate (maxStableNameBytesV1 + 1) 'x'), type := .int }]))
  let typeRows ← rows "mitl-types.jsonl"
  let types ← typeRows.mapM fun row => do
    return (← str row "id", ← decodeType (← get row "type"))
  let base ← IO.ofExcept (Codec.ModelInterfaceJson.parseLockString (← IO.FS.readFile
    "test/fixtures/model-interface/counter/Counter.mirror-interface.lock.json"))
  for row in typeRows do
    let name ← str row "id"
    let type ← decodeType (← get row "type")
    check (name ++ ".wellFormed") (Core.ModelInterface.Conformance.typeWellFormed type == bool row "wellFormed")
    check (name ++ ".portable")
      ((Core.ModelInterface.Conformance.typeWellFormed type && Core.ModelInterface.Conformance.portableType type) == bool row "portable")
    if bool row "wellFormed" then
      let probe := makeLock base "Probe" base.initializers base.actions
        [{ id := "Value", wireName := "value", type }]
      for (target, generate) in emitters do
        -- This fixture is outside the common v1 baseline but is the explicit
        -- integer-key-map extension of mirrorcpp-v2.
        let accepted := bool row "portable" ||
          ((target == "cpp-v2" || target == "rust-v2" || target == "async-v2") && type == ModelType.map .int .int)
        check (name ++ ".emission." ++ target)
          ((generate probe).isOk == accepted)
  let valueRows ← rows "mitl-values.jsonl"
  for row in valueRows do
    let type ← typeFor types row
    let value := decoded (← get row "value")
    let accepted := value.any (Core.ModelInterface.Conformance.valueWellTyped type)
    check ((← str row "id") ++ ".typing") (accepted == bool row "accepted")
    if let some value := value then
      if accepted then
        let roundtrip := decoded (Codec.encValue value)
        check ((← str row "id") ++ ".wireRoundtrip")
          (roundtrip.any (Core.ModelInterface.Conformance.equivalent type value))
  let eqRows ← rows "mitl-equivalence.jsonl"
  for row in eqRows do
    let type ← typeFor types row
    let left := decoded (← get row "left")
    let right := decoded (← get row "right")
    check ((← str row "id") ++ ".leftTyped")
      (left.any (Core.ModelInterface.Conformance.valueWellTyped type) == bool row "leftAccepted")
    check ((← str row "id") ++ ".rightTyped")
      (right.any (Core.ModelInterface.Conformance.valueWellTyped type) == bool row "rightAccepted")
    let equivalent := left.any fun a => right.any (Core.ModelInterface.Conformance.equivalent type a)
    check ((← str row "id") ++ ".equivalent") (equivalent == bool row "equivalent")
  let pathRows ← rows "mitl-paths.jsonl"
  for row in pathRows do
    let name ← str row "id"
    let type ← typeFor types row
    let segments ← path (← get row "path")
    let result := Core.ModelInterface.Conformance.pathType type segments
    check (name ++ ".pathType") (result.isOk == bool row "static" true)
    if let .ok actual := result then
      let expected ← decodeType (← get row "type")
      check (name ++ ".pathTypeResult") (actual == canonicalizeModelType expected)
      let value ← match decoded (← get row "value") with
        | some value => pure value
        | none => throw (IO.userError s!"invalid path fixture value: {name}")
      let projected := Core.ModelInterface.Conformance.evaluatePath type value segments
      check (name ++ ".pathValue") (projected.isOk == bool row "dynamic" true)
      if let .ok actual := projected then
        check (name ++ ".pathValueResult")
          ((decoded (← get row "result")).any (Core.ModelInterface.Conformance.equivalent expected actual))
  let portable := typeRows.filter (fun row => bool row "portable")
  let portableInputs ← portable.mapM fun row => do
    let name ← str row "id"
    return ({ id := name, projection := {
      root := .initialState, path := [.field (lower name)],
      type := ← decodeType (← get row "type") } } : ResolvedInput)
  let portableObservations := portableInputs.map fun i =>
    ({ id := i.id, wireName := lower i.id, type := i.projection.type } : ResolvedObservation)
  emit output (makeLock base "Portable"
    [{ id := "Initialize", phase := .initialize, wireAction := "init", inputs := portableInputs }]
    [] portableObservations)
  let recording := makeLock base "Recording"
    [{ id := "Initialize", phase := .initialize, wireAction := "init", wireAliases := ["reset"] }]
    [{ id := "Tick", phase := .transition, wireAction := "tick", wireAliases := ["increment"]
       inputs := [
        { id := "Enabled"
          projection := {
            root := .stepParameters
            path := [.field "parameters", .field "meta", .index 0, .variantValue "flag"]
            type := .bool } },
        { id := "Stride"
          projection := {
            root := .stepParameters
            path := [.field "parameters", .field "stride"]
            type := .int } }] }]
    [{ id := "Count", wireName := "count", type := .int }]
  emit output recording
  -- Each generated portable projection is also emitted from its own checked
  -- input shape, so native runners execute the exact path from the shared row.
  for row in pathRows do
    if bool row "static" true then
      let name := "Path" ++ (← str row "id")
      let resultType ← decodeType (← get row "type")
      let segments ← path (← get row "path")
      let projection := if bool row "stateRoot" then segments else .field "root" :: segments
      let probe := makeLock base name
        [{ id := "Initialize", phase := .initialize, wireAction := "init"
           inputs := [{ id := "Value"
                        projection := {
                          root := .initialState
                          path := projection
                          type := resultType } }] }]
        [] [{ id := "Value", wireName := "value", type := resultType }]
      if bool row "generatedPortable" true then emit output probe
      else
        for (target, generate) in emitters do
          check (name ++ ".excludedPath." ++ target)
            ((generate probe).isOk == (target == "cpp-v2" || target == "rust-v2"))
  IO.println s!"MITL judgments: {typeRows.length} types, {valueRows.length} values, {eqRows.length} equivalence, {pathRows.length} paths; fresh bindings: {emitters.length} profiles"

end ModelInterfaceLanguageSpec

def main (args : List String) : IO UInt32 := do
  try
    let output := System.FilePath.mk (args.headD ".golden-build/model-interface-conformance/generated")
    ModelInterfaceLanguageSpec.run output
    pure 0
  catch error =>
    IO.eprintln error.toString
    pure 1
