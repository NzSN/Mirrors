import Core.ModelInterface.Resolve
import Core.Trace

/-!
# Pure model-interface trace preflight

Checks already-decoded, parameter-repartitioned ITF traces against a locked
model interface before a negotiated replay is admitted.  It does not mutate a
trace, weaken `Core.Diff`, or perform I/O.
-/

namespace Core.ModelInterface

structure PreflightOptions where
  requireAllActions : Bool := false
  deriving Repr, DecidableEq

structure ActionCoverage where
  id : StableId
  count : Nat
  deriving Repr, DecidableEq

structure CoverageReport where
  traces : Nat
  states : Nat
  actions : List ActionCoverage
  unseenActions : List StableId
  deriving Repr, DecidableEq

structure PreflightResult where
  coverage : CoverageReport
  diagnostics : List Diagnostic
  deriving Repr

def PreflightResult.hasErrors (result : PreflightResult) : Bool :=
  result.diagnostics.any Diagnostic.isError

private def nodupStrings (names : List String) : Bool :=
  (duplicateStrings names).isEmpty

private def sameStringSet (left right : List String) : Bool :=
  sortStrings (stableUniqueStrings left) == sortStrings (stableUniqueStrings right)

private def wellFormedValueFuel : Nat → Value → Bool
  | 0, _ => false
  | fuel + 1, value =>
      match value with
      | .vint _ | .vbool _ | .vstr _ | .vunserializable _ | .vnull => true
      | .vset values | .vseq values | .vtuple values =>
          values.all (wellFormedValueFuel fuel)
      | .vrecord fields | .vmap fields =>
          nodupStrings (fields.map Prod.fst) &&
            fields.all (fun field => wellFormedValueFuel fuel field.2)
      | .vvariant _ payload => wellFormedValueFuel fuel payload

private def wellFormedValue (value : Value) : Bool :=
  wellFormedValueFuel (valueSize value + 1) value

private def valueHasTypeFuel : Nat → Value → ModelType → Bool
  | 0, _, _ => false
  | fuel + 1, value, type =>
      match value, type with
      | .vint _, .int => true
      | .vbool _, .bool => true
      | .vstr _, .str => true
      | .vnull, .null => true
      | .vset values, .set element =>
          values.all (fun value => valueHasTypeFuel fuel value element)
      | .vseq values, .seq element =>
          values.all (fun value => valueHasTypeFuel fuel value element)
      | .vtuple values, .tuple elements =>
          values.length == elements.length &&
            (values.zip elements).all (fun pair =>
              valueHasTypeFuel fuel pair.1 pair.2)
      | .vrecord fields, .record expected =>
          let actualNames := fields.map Prod.fst
          let expectedNames := expected.map (·.wireName)
          nodupStrings actualNames && nodupStrings expectedNames &&
            sameStringSet actualNames expectedNames &&
            fields.all (fun field =>
              match expected.find? (fun item => item.wireName == field.1) with
              | some item => valueHasTypeFuel fuel field.2 item.type
              | none => false)
      | .vmap entries, .map keyType valueType =>
          -- Core.Value's ITF-map representation has string keys.
          keyType == .str && nodupStrings (entries.map Prod.fst) &&
            entries.all (fun entry =>
              valueHasTypeFuel fuel (.vstr entry.1) keyType &&
                valueHasTypeFuel fuel entry.2 valueType)
      | .vvariant tag payload, .variant cases =>
          match cases.find? (fun item => item.tag == tag) with
          | some item => valueHasTypeFuel fuel payload item.payload
          | none => false
      | _, .opaqueItf _ => wellFormedValueFuel fuel value
      | _, _ => false

/-- Check a concrete ITF value against a resolved model type, including the
duplicate-key side conditions used by `Core.Diff`. -/
def valueHasType (value : Value) (type : ModelType) : Bool :=
  wellFormedValue value &&
    valueHasTypeFuel (valueSize value + modelTypeSize type + 1) value type

private def literalStringKey? : CanonicalItfLiteral → Option String
  | .str value => some value
  | _ => none

private def projectValueAux : Value → List PathSegment → Nat → Except String Value
  | value, [], _ => .ok value
  | value, segment :: rest, index => do
      let next ← match segment, value with
        | .field name, .vrecord fields =>
            match fields.lookup name with
            | some value => .ok value
            | none => .error s!"segment {index}: missing record field {name}"
        | .index i, .vseq values | .index i, .vtuple values =>
            match values[i]? with
            | some value => .ok value
            | none => .error s!"segment {index}: index {i} is out of range"
        | .mapKey key, .vmap entries =>
            match literalStringKey? key with
            | none => .error s!"segment {index}: Core.Value maps require a string key"
            | some key =>
                match entries.lookup key with
                | some value => .ok value
                | none => .error s!"segment {index}: map key is absent"
        | .variantValue expected, .vvariant actual payload =>
            if actual == expected then .ok payload
            else .error s!"segment {index}: expected variant {expected}, got {actual}"
        | .field _, _ => .error s!"segment {index}: field requires a record"
        | .index _, _ => .error s!"segment {index}: index requires a sequence or tuple"
        | .mapKey _, _ => .error s!"segment {index}: mapKey requires a map"
        | .variantValue _, _ => .error s!"segment {index}: variantValue requires a variant"
      projectValueAux next rest (index + 1)

/-- Project a typed input from a protocol state map. -/
def projectState (state : ValueMap) (path : List PathSegment) : Except String Value :=
  projectValueAux (.vrecord state) path 0

private def traceLocation (traceIndex stepIndex : Nat) : SourceLocation :=
  { source := s!"<trace:{traceIndex}>"
    pointer := some s!"/states/{stepIndex}" }

private def preflightDiagnostic (code : String) (severity : Severity)
    (traceIndex stepIndex : Nat) (subjectKind : String)
    (stableId : Option String := none)
    (arguments : List (String × String) := []) : Diagnostic :=
  { code
    severity
    stage := "preflight"
    subject := { kind := subjectKind, stableId }
    primary := traceLocation traceIndex stepIndex
    arguments := arguments.mergeSort fun left right => left.1 ≤ right.1 }

private def actionAcceptsLabel (action : ResolvedAction) (label : String) : Bool :=
  action.wireAction == label || action.wireAliases.contains label

private def findAction (actions : List ResolvedAction) (label : String) : Option ResolvedAction :=
  actions.find? (fun action => actionAcceptsLabel action label)

private def incrementCoverage (id : String) : List ActionCoverage → List ActionCoverage
  | [] => [{ id, count := 1 }]
  | item :: rest =>
      if item.id == id then { item with count := item.count + 1 } :: rest
      else item :: incrementCoverage id rest

private def checkInput (traceIndex stepIndex : Nat) (step : Step)
    (action : ResolvedAction) (input : ResolvedInput) : List Diagnostic :=
  let root := match input.projection.root with
    | .initialState => filterMeta step.vars
    | .stepParameters => step.params
  match projectState root input.projection.path with
  | .error reason =>
      [preflightDiagnostic "MIC-P-VALUE-001" .error traceIndex stepIndex
        "input" (some input.id)
        [("action", action.id), ("reason", reason)]]
  | .ok value =>
      if valueHasType value input.projection.type then [] else
        [preflightDiagnostic "MIC-P-VALUE-001" .error traceIndex stepIndex
          "input" (some input.id)
          [("action", action.id), ("reason", "projected input has the wrong type")]]

private def checkObservation (traceIndex stepIndex : Nat) (actual : ValueMap)
    (observation : ResolvedObservation) : List Diagnostic :=
  match actual.lookup observation.wireName with
  | none =>
      [preflightDiagnostic "MIC-P-TRACE-001" .error traceIndex stepIndex
        "observation" (some observation.id)
        [("reason", "required observation key is missing"),
         ("wireName", observation.wireName)]]
  | some value =>
      if valueHasType value observation.type then [] else
        [preflightDiagnostic "MIC-P-VALUE-001" .error traceIndex stepIndex
          "observation" (some observation.id)
          [("reason", "observation value has the wrong type"),
           ("wireName", observation.wireName)]]

private structure Accumulator where
  diagnostics : List Diagnostic := []
  coverage : List ActionCoverage
  states : Nat := 0

private def checkStep (lock : LockedModelInterface) (traceIndex : Nat)
    (accumulator : Accumulator) (step : Step) : Accumulator :=
  let actualObservations := filterMeta step.vars
  let actualKeys := actualObservations.map Prod.fst
  let expectedKeys := lock.observations.map (·.wireName)
  let keyDiagnostics :=
    if nodupStrings actualKeys && sameStringSet actualKeys expectedKeys then [] else
      [preflightDiagnostic "MIC-P-TRACE-001" .error traceIndex step.idx
        "observation" none
        [("actual", String.intercalate "," (sortStrings actualKeys)),
         ("expected", String.intercalate "," (sortStrings expectedKeys)),
         ("reason", "comparable observation keys differ")]]
  let valueDiagnostics := lock.observations.flatMap
    (checkObservation traceIndex step.idx actualObservations)
  let phaseActions := if step.idx == 0 then lock.initializers else lock.actions
  let otherPhaseActions := if step.idx == 0 then lock.actions else lock.initializers
  let actionResult :=
    if step.act.isEmpty then
      (none, [preflightDiagnostic "MIC-P-TRACE-001" .error traceIndex step.idx
        "action" none [("reason", "missing or non-string action_taken")]])
    else match findAction phaseActions step.act with
    | some action => (some action, [])
    | none =>
        match findAction otherPhaseActions step.act with
        | some action =>
            let reason := if step.idx == 0 then
              "transition action appears at state zero"
            else "initializer appears in transition tail"
            (none, [preflightDiagnostic "MIC-P-ACTION-001" .error traceIndex step.idx
              "action" (some action.id) [("action", step.act), ("reason", reason)]])
        | none =>
            (none, [preflightDiagnostic "MIC-P-ACTION-001" .error traceIndex step.idx
              "action" none [("action", step.act), ("reason", "undeclared action")]])
  let actionDiagnostics := actionResult.2
  let inputDiagnostics := match actionResult.1 with
    | some action => action.inputs.flatMap (checkInput traceIndex step.idx step action)
    | none => []
  let coverage := match actionResult.1 with
    | some action => incrementCoverage action.id accumulator.coverage
    | none => accumulator.coverage
  { diagnostics := accumulator.diagnostics ++ keyDiagnostics ++ valueDiagnostics ++
      actionDiagnostics ++ inputDiagnostics
    coverage
    states := accumulator.states + 1 }

private def initialCoverage (lock : LockedModelInterface) : List ActionCoverage :=
  ((lock.initializers ++ lock.actions).map fun action =>
    ({ id := action.id, count := 0 } : ActionCoverage)).toArray.qsort
      (fun left right => compare left.id right.id == .lt) |>.toList

/-- Validate every trace and produce deterministic action coverage. -/
def preflight (lock : LockedModelInterface) (traces : List ItfTrace)
    (options : PreflightOptions := {}) : PreflightResult :=
  let initial : Accumulator := { coverage := initialCoverage lock }
  let initial := if traces.isEmpty then
      { initial with diagnostics := [preflightDiagnostic "MIC-P-TRACE-001" .error
        0 0 "trace" none [("reason", "trace bundle is empty")]] }
    else initial
  let checked := traces.zipIdx.foldl (fun accumulator pair =>
    let trace := pair.1
    let traceIndex := pair.2
    let expectedVars := lock.runProfile.actionVariable ::
      (lock.runProfile.effectiveParamVars ++ lock.observations.map (·.wireName))
    let schemaDiagnostics :=
      (if nodupStrings trace.traceVars && sameStringSet trace.traceVars expectedVars then []
       else [preflightDiagnostic "MIC-P-TRACE-001" .error traceIndex 0
        "traceSchema" none
        [("actual", String.intercalate "," (sortStrings trace.traceVars)),
         ("expected", String.intercalate "," (sortStrings expectedVars)),
         ("reason", "trace vars differ from the resolved run profile")]]) ++
      (if sameStringSet trace.paramVars lock.runProfile.effectiveParamVars then []
       else [preflightDiagnostic "MIC-P-TRACE-001" .error traceIndex 0
        "traceSchema" none
        [("actual", String.intercalate "," (sortStrings trace.paramVars)),
         ("expected", String.intercalate ","
           (sortStrings lock.runProfile.effectiveParamVars)),
         ("reason", "trace param_vars differ from the resolved run profile")]])
    let accumulator := {
      accumulator with diagnostics := accumulator.diagnostics ++ schemaDiagnostics }
    let steps := traceSteps trace
    if steps.isEmpty then
      { accumulator with diagnostics := accumulator.diagnostics ++
          [preflightDiagnostic "MIC-P-TRACE-001" .error traceIndex 0
            "trace" none [("reason", "trace has no states")]] }
    else steps.foldl (checkStep lock traceIndex) accumulator) initial
  let unseen := checked.coverage.filter (fun item => item.count == 0) |>.map (·.id)
  let coverageSeverity := if options.requireAllActions then Severity.error else Severity.obligation
  let coverageDiagnostics := unseen.map fun id =>
    preflightDiagnostic "MIC-P-COVERAGE-001" coverageSeverity 0 0
      "action" (some id) [("reason", "declared action was not exercised")]
  let coverage : CoverageReport :=
    { traces := traces.length
      states := checked.states
      actions := checked.coverage
      unseenActions := unseen }
  { coverage
    diagnostics := sortDiagnostics (checked.diagnostics ++ coverageDiagnostics) }

end Core.ModelInterface
