import Core.ModelInterface.Types

/-!
# Pure model-interface resolution

Deterministic validation and normalization from an already-decoded companion
contract and structural evidence to the semantic descriptor. Hashing of the
canonical projection is deliberately performed by the effectful shell after
this module returns.
-/

namespace Core.ModelInterface

/-! ## Canonical collection helpers -/

def sortStrings (xs : List String) : List String :=
  xs.toArray.qsort (fun a b => compare a b == .lt) |>.toList

def stableUniqueStrings (xs : List String) : List String :=
  xs.foldl (fun out x => if out.contains x then out else out ++ [x]) []

def duplicateStrings (xs : List String) : List String :=
  sortStrings <| stableUniqueStrings <|
    xs.filter (fun x => xs.count x > 1)

def stableUniqueOrigins (xs : List EvidenceOrigin) : List EvidenceOrigin :=
  xs.foldl (fun out x => if out.contains x then out else out ++ [x]) []

private def sortFields (xs : List ModelField) : List ModelField :=
  xs.toArray.qsort (fun a b => compare a.wireName b.wireName == .lt) |>.toList

private def sortCases (xs : List VariantCase) : List VariantCase :=
  xs.toArray.qsort (fun a b => compare a.tag b.tag == .lt) |>.toList

private def sortInputs (xs : List ResolvedInput) : List ResolvedInput :=
  xs.toArray.qsort (fun a b => compare a.id b.id == .lt) |>.toList

private def sortActions (xs : List ResolvedAction) : List ResolvedAction :=
  xs.toArray.qsort (fun a b => compare a.id b.id == .lt) |>.toList

private def sortObservations (xs : List ResolvedObservation) : List ResolvedObservation :=
  xs.toArray.qsort (fun a b => compare a.id b.id == .lt) |>.toList

private def sortSources (xs : List SourceDigest) : List SourceDigest :=
  xs.toArray.qsort (fun a b =>
    match compare a.moduleName b.moduleName with
    | .lt => true
    | .eq => compare a.logicalPath b.logicalPath == .lt
    | .gt => false) |>.toList

/-! Explicit measures make traversals over the mutually recursive structural
type declarations visibly total to Lean. -/
mutual

  def modelTypeSize : ModelType → Nat
    | .int | .bool | .str | .null | .opaqueItf _ => 1
    | .set t | .seq t => 1 + modelTypeSize t
    | .tuple ts => 1 + modelTypesSize ts
    | .record fields => 1 + modelFieldsSize fields
    | .map k v => 1 + modelTypeSize k + modelTypeSize v
    | .variant cases => 1 + variantCasesSize cases

  def modelTypesSize : List ModelType → Nat
    | [] => 0
    | t :: ts => modelTypeSize t + 1 + modelTypesSize ts

  def modelFieldsSize : List ModelField → Nat
    | [] => 0
    | f :: fs => modelTypeSize f.type + 1 + modelFieldsSize fs

  def variantCasesSize : List VariantCase → Nat
    | [] => 0
    | c :: cs => modelTypeSize c.payload + 1 + variantCasesSize cs

end

mutual

  /-- Every user-controlled field/tag/opaque label nested in a type. -/
  def modelTypeWireNames : ModelType → List String
    | .int | .bool | .str | .null => []
    | .set type | .seq type => modelTypeWireNames type
    | .tuple types => modelTypesWireNames types
    | .record fields => modelFieldsWireNames fields
    | .map key value => modelTypeWireNames key ++ modelTypeWireNames value
    | .variant cases => variantCasesWireNames cases
    | .opaqueItf description => [description]

  def modelTypesWireNames : List ModelType → List String
    | [] => []
    | type :: rest => modelTypeWireNames type ++ modelTypesWireNames rest

  def modelFieldsWireNames : List ModelField → List String
    | [] => []
    | field :: rest =>
        field.wireName :: modelTypeWireNames field.type ++ modelFieldsWireNames rest

  def variantCasesWireNames : List VariantCase → List String
    | [] => []
    | item :: rest =>
        item.tag :: modelTypeWireNames item.payload ++ variantCasesWireNames rest

end


private def pathWireNames (path : List PathSegment) : List String :=
  path.filterMap fun
    | .field name | .variantValue name => some name
    | _ => none

mutual

  /-- Exact number of structural-type constructors in a normalized type. -/
  def modelTypeNodeCount : ModelType → Nat
    | .int | .bool | .str | .null | .opaqueItf _ => 1
    | .set t | .seq t => 1 + modelTypeNodeCount t
    | .tuple ts => 1 + modelTypesNodeCount ts
    | .record fields => 1 + modelFieldsNodeCount fields
    | .map k v => 1 + modelTypeNodeCount k + modelTypeNodeCount v
    | .variant cases => 1 + variantCasesNodeCount cases

  def modelTypesNodeCount : List ModelType → Nat
    | [] => 0
    | t :: ts => modelTypeNodeCount t + modelTypesNodeCount ts

  def modelFieldsNodeCount : List ModelField → Nat
    | [] => 0
    | f :: fs => modelTypeNodeCount f.type + modelFieldsNodeCount fs

  def variantCasesNodeCount : List VariantCase → Nat
    | [] => 0
    | c :: cs => modelTypeNodeCount c.payload + variantCasesNodeCount cs

end

mutual

  /-- Maximum constructor depth, counting the root constructor as depth one. -/
  def modelTypeDepth : ModelType → Nat
    | .int | .bool | .str | .null | .opaqueItf _ => 1
    | .set t | .seq t => 1 + modelTypeDepth t
    | .tuple ts => 1 + modelTypesMaxDepth ts
    | .record fields => 1 + modelFieldsMaxDepth fields
    | .map k v => 1 + max (modelTypeDepth k) (modelTypeDepth v)
    | .variant cases => 1 + variantCasesMaxDepth cases

  def modelTypesMaxDepth : List ModelType → Nat
    | [] => 0
    | t :: ts => max (modelTypeDepth t) (modelTypesMaxDepth ts)

  def modelFieldsMaxDepth : List ModelField → Nat
    | [] => 0
    | f :: fs => max (modelTypeDepth f.type) (modelFieldsMaxDepth fs)

  def variantCasesMaxDepth : List VariantCase → Nat
    | [] => 0
    | c :: cs => max (modelTypeDepth c.payload) (variantCasesMaxDepth cs)

end

mutual

  /-- Normalize every set-like part of a structural type. Tuple and sequence
  order remains semantic and is preserved. -/
  def canonicalizeModelType : ModelType → ModelType
    | .int => .int
    | .bool => .bool
    | .str => .str
    | .null => .null
    | .set t => .set (canonicalizeModelType t)
    | .seq t => .seq (canonicalizeModelType t)
    | .tuple ts => .tuple (canonicalizeTypes ts)
    | .record fields => .record (sortFields (canonicalizeFields fields))
    | .map k v => .map (canonicalizeModelType k) (canonicalizeModelType v)
    | .variant cases => .variant (sortCases (canonicalizeCases cases))
    | .opaqueItf description => .opaqueItf description

  def canonicalizeTypes : List ModelType → List ModelType
    | [] => []
    | t :: ts => canonicalizeModelType t :: canonicalizeTypes ts

  def canonicalizeFields : List ModelField → List ModelField
    | [] => []
    | f :: fs =>
        { f with type := canonicalizeModelType f.type } :: canonicalizeFields fs

  def canonicalizeCases : List VariantCase → List VariantCase
    | [] => []
    | c :: cs =>
        { c with payload := canonicalizeModelType c.payload } :: canonicalizeCases cs

end

private def normalizeContractInput (input : ContractInput) : ContractInput :=
  { input with expectedType := input.expectedType.map canonicalizeModelType }

private def normalizeContractAction (action : ContractAction) : ContractAction :=
  { action with
      wireAliases := sortStrings action.wireAliases
      inputs := (action.inputs.map normalizeContractInput).toArray.qsort
        (fun a b => compare a.id b.id == .lt) |>.toList }

private def normalizeContractObservation
    (observation : ContractObservation) : ContractObservation :=
  { observation with
      expectedType := observation.expectedType.map canonicalizeModelType }

/-- Normalize every set-like contract collection while preserving semantic
sequence/path order. This is the exact contract retained by resolved and lock
artifacts. -/
def normalizeContractV1 (contract : ContractV1) : ContractV1 :=
  { contract with
      initializers := (contract.initializers.map normalizeContractAction).toArray.qsort
        (fun a b => compare a.id b.id == .lt) |>.toList
      actions := (contract.actions.map normalizeContractAction).toArray.qsort
        (fun a b => compare a.id b.id == .lt) |>.toList
      observations := (contract.observations.map normalizeContractObservation).toArray.qsort
        (fun a b => compare a.id b.id == .lt) |>.toList }

mutual

  /-- Structural well-formedness independent of any target-language profile. -/
  def ModelType.wellFormed : ModelType → Bool
    | .int | .bool | .str | .null => true
    | .set t | .seq t => t.wellFormed
    | .tuple ts => modelTypesWellFormed ts
    | .record fields =>
        let names := fields.map (·.wireName)
        names.all (fun n => !n.isEmpty) && (duplicateStrings names).isEmpty &&
          modelFieldsWellFormed fields
    | .map k v => k.wellFormed && v.wellFormed
    | .variant cases =>
        let tags := cases.map (·.tag)
        tags.all (fun n => !n.isEmpty) && (duplicateStrings tags).isEmpty &&
          variantCasesWellFormed cases
    | .opaqueItf description => !description.isEmpty

  def modelTypesWellFormed : List ModelType → Bool
    | [] => true
    | t :: ts => t.wellFormed && modelTypesWellFormed ts

  def modelFieldsWellFormed : List ModelField → Bool
    | [] => true
    | f :: fs => f.type.wellFormed && modelFieldsWellFormed fs

  def variantCasesWellFormed : List VariantCase → Bool
    | [] => true
    | c :: cs => c.payload.wellFormed && variantCasesWellFormed cs

end

mutual

  def literalSize : CanonicalItfLiteral → Nat
    | .int _ | .bool _ | .str _ | .null => 1
    | .set xs | .seq xs | .tuple xs => 1 + literalListSize xs
    | .record fields => 1 + literalRecordSize fields
    | .map entries => 1 + literalMapSize entries
    | .variant _ payload => 1 + literalSize payload

  def literalListSize : List CanonicalItfLiteral → Nat
    | [] => 0
    | x :: xs => literalSize x + 1 + literalListSize xs

  def literalRecordSize : List (String × CanonicalItfLiteral) → Nat
    | [] => 0
    | (_, value) :: rest => literalSize value + 1 + literalRecordSize rest

  def literalMapSize :
      List (CanonicalItfLiteral × CanonicalItfLiteral) → Nat
    | [] => 0
    | (key, value) :: rest =>
        literalSize key + literalSize value + 1 + literalMapSize rest

end

mutual

  /-- Check a data-only map-key literal against its structural type. -/
  def CanonicalItfLiteral.hasType : CanonicalItfLiteral → ModelType → Bool
    | .int _, .int => true
    | .bool _, .bool => true
    | .str _, .str => true
    | .null, .null => true
    | .set xs, .set t => literalsHaveType xs t
    | .seq xs, .seq t => literalsHaveType xs t
    | .tuple xs, .tuple ts => literalTupleHasTypes xs ts
    | .record fields, .record types =>
        fields.length == types.length &&
          (duplicateStrings (fields.map Prod.fst)).isEmpty &&
          literalRecordHasType fields types
    | .map entries, .map k v => literalMapHasType entries k v
    | .variant tag payload, .variant cases =>
        match cases.find? (fun c => c.tag == tag) with
        | some c => payload.hasType c.payload
        | none => false
    | _, _ => false

  def literalsHaveType : List CanonicalItfLiteral → ModelType → Bool
    | [], _ => true
    | x :: xs, t => x.hasType t && literalsHaveType xs t

  def literalTupleHasTypes : List CanonicalItfLiteral → List ModelType → Bool
    | [], [] => true
    | x :: xs, t :: ts => x.hasType t && literalTupleHasTypes xs ts
    | _, _ => false

  def literalRecordHasType : List (String × CanonicalItfLiteral) →
      List ModelField → Bool
    | [], types => types.isEmpty
    | (name, value) :: rest, types =>
        match types.find? (fun t => t.wireName == name) with
        | some t => value.hasType t.type && literalRecordHasType rest types
        | none => false

  def literalMapHasType :
      List (CanonicalItfLiteral × CanonicalItfLiteral) → ModelType → ModelType → Bool
    | [], _, _ => true
    | (key, value) :: rest, kt, vt =>
        key.hasType kt && value.hasType vt && literalMapHasType rest kt vt

end

/-! ## Diagnostics -/

private def thenCompare (first second : Ordering) : Ordering :=
  if first == .eq then second else first

private def compareOptionString : Option String → Option String → Ordering
  | none, none => .eq
  | none, some _ => .lt
  | some _, none => .gt
  | some left, some right => compare left right

private def compareOptionNat : Option Nat → Option Nat → Ordering
  | none, none => .eq
  | none, some _ => .lt
  | some _, none => .gt
  | some left, some right => compare left right

private def compareSeverity : Severity → Severity → Ordering
  | .error, .error | .warning, .warning | .obligation, .obligation => .eq
  | .error, _ => .lt
  | .warning, .error => .gt
  | .warning, .obligation => .lt
  | .obligation, _ => .gt

/-- Total ordering for logical source locations. -/
def compareSourceLocation (left right : SourceLocation) : Ordering :=
  thenCompare (compare left.source right.source) <|
  thenCompare (compareOptionString left.pointer right.pointer) <|
  thenCompare (compareOptionNat left.line right.line) <|
  compareOptionNat left.column right.column

/-- Sort related locations by their complete logical location and remove exact
duplicates. The normalized list is part of diagnostic identity and ordering. -/
def normalizeDiagnosticRelated
    (locations : List SourceLocation) : List SourceLocation :=
  (locations.toArray.qsort fun left right =>
    compareSourceLocation left right == .lt).toList.eraseDupsBy fun left right =>
      decide (left = right)

private def compareSourceLocations :
    List SourceLocation → List SourceLocation → Ordering
  | [], [] => .eq
  | [], _ :: _ => .lt
  | _ :: _, [] => .gt
  | left :: leftRest, right :: rightRest =>
      thenCompare (compareSourceLocation left right)
        (compareSourceLocations leftRest rightRest)

private def compareDiagnosticArgument
    (left right : String × String) : Ordering :=
  thenCompare (compare left.1 right.1) (compare left.2 right.2)

/-- Sort diagnostic arguments by name and then value, removing exact
duplicates. This is shared by total diagnostic ordering and canonical JSON
encoding. -/
def normalizeDiagnosticArguments
    (arguments : List (String × String)) : List (String × String) :=
  (arguments.toArray.qsort fun left right =>
    compareDiagnosticArgument left right == .lt).toList.eraseDups

private def compareDiagnosticArguments :
    List (String × String) → List (String × String) → Ordering
  | [], [] => .eq
  | [], _ :: _ => .lt
  | _ :: _, [] => .gt
  | left :: leftRest, right :: rightRest =>
      thenCompare (compareDiagnosticArgument left right)
        (compareDiagnosticArguments leftRest rightRest)

private def compareDiagnostics (left right : Diagnostic) : Ordering :=
  thenCompare (compare left.stage right.stage) <|
  thenCompare (compareSourceLocation left.primary right.primary) <|
  thenCompare (compare left.code right.code) <|
  thenCompare (compare left.subject.kind right.subject.kind) <|
  thenCompare (compareOptionString left.subject.stableId right.subject.stableId) <|
  thenCompare
    (compareDiagnosticArguments
      (normalizeDiagnosticArguments left.arguments)
      (normalizeDiagnosticArguments right.arguments)) <|
  thenCompare (compareSeverity left.severity right.severity) <|
  compareSourceLocations
    (normalizeDiagnosticRelated left.related)
    (normalizeDiagnosticRelated right.related)

def sortDiagnostics (xs : List Diagnostic) : List Diagnostic :=
  xs.toArray.qsort (fun left right => compareDiagnostics left right == .lt)
    |>.toList

private def diag (code : String) (severity : Severity) (subjectKind : String)
    (stableId : Option String) (primary : SourceLocation)
    (arguments : List (String × String) := []) : Diagnostic where
  code := code
  severity := severity
  stage := "resolve"
  subject := { kind := subjectKind, stableId := stableId }
  primary := primary
  arguments := arguments.toArray.qsort (fun a b => compare a.1 b.1 == .lt) |>.toList

def finishCompile (candidate : Option α) (diagnostics : List Diagnostic) : CompileResult α :=
  let diagnostics := sortDiagnostics diagnostics
  if diagnostics.any Diagnostic.isError then
    { value := none, diagnostics }
  else
    { value := candidate, diagnostics }

/-! ## Contract primitives -/

private def asciiUpper (c : Char) : Bool :=
  decide (65 ≤ c.toNat ∧ c.toNat ≤ 90)

private def asciiLower (c : Char) : Bool :=
  decide (97 ≤ c.toNat ∧ c.toNat ≤ 122)

private def asciiDigit (c : Char) : Bool :=
  decide (48 ≤ c.toNat ∧ c.toNat ≤ 57)

private def asciiAlpha (c : Char) : Bool := asciiUpper c || asciiLower c

def validStableId (id : String) : Bool :=
  match id.toList with
  | [] => false
  | c :: cs => asciiUpper c && cs.all (fun x => asciiAlpha x || asciiDigit x)

def validModuleName (name : String) : Bool :=
  match name.toList with
  | [] => false
  | c :: cs => (asciiAlpha c || c == '_') &&
      cs.all (fun x => asciiAlpha x || asciiDigit x || x == '_')

private def decimalComponent (s : String) : Bool :=
  !s.isEmpty && s.toList.all asciiDigit

def validInterfaceVersion (version : String) : Bool :=
  match version.splitOn "." with
  | [major, minor, patch] =>
      decimalComponent major && decimalComponent minor && decimalComponent patch
  | _ => false

def validLogicalPath (path : String) : Bool :=
  !path.isEmpty && !path.startsWith "/" && !path.startsWith "\\" &&
    !path.contains '\\' && !path.contains ':' &&
    (path.splitOn "/").all (fun segment =>
      !segment.isEmpty && segment != "." && segment != "..")

/-! ## Exact comparison variables -/

def effectiveParamVars (evidence : ModelEvidence) (run : RunProfile) : List String :=
  stableUniqueStrings (evidence.itfParamVars ++ run.configuredParamVar.toList)

/-- Exact root variables compared by the current Mirrors pipeline. -/
def requiredObservationVars (evidence : ModelEvidence) (run : RunProfile) : List String :=
  let params := effectiveParamVars evidence run
  stableUniqueStrings <| evidence.traceVars.filter (fun name =>
    !params.contains name && !isMetaKey name)

def resolvedRunProfile (contract : ContractV1) (evidence : ModelEvidence)
    (run : RunProfile) : ResolvedRunProfile where
  actionVariable := contract.wire.actionVariable
  configuredParamVar := run.configuredParamVar
  itfParamVars := sortStrings (stableUniqueStrings evidence.itfParamVars)
  effectiveParamVars := sortStrings (effectiveParamVars evidence run)

/-! ## Type evidence and typed paths -/

private structure ResolvedType where
  type : ModelType
  origins : List EvidenceOrigin

private def topFacts (evidence : ModelEvidence) (name : String) : List TypeFact :=
  let facts := evidence.typeFacts.filter (fun fact =>
    fact.modelPath.root == name && fact.modelPath.path.isEmpty)
  facts.toArray.qsort (fun left right =>
    let locationOrder := compareSourceLocation left.location right.location
    if locationOrder != .eq then locationOrder == .lt
    else
      let leftType := toString (repr (canonicalizeModelType left.type))
      let rightType := toString (repr (canonicalizeModelType right.type))
      match compare leftType rightType with
      | .lt => true
      | .gt => false
      | .eq =>
          match left.origin, right.origin with
          | .apalacheTypecheck, .apalacheTypecheck
          | .itfVarTypes, .itfVarTypes
          | .contractAssertion, .contractAssertion => false
          | .apalacheTypecheck, _ => true
          | .itfVarTypes, .contractAssertion => true
          | _, _ => false)
    |>.toList

private def typeArguments (name : String) : List (String × String) :=
  [("modelPath", name)]

private def resolveTopType (evidence : ModelEvidence) (name : String)
    (expected : Option ModelType) (primary : SourceLocation)
    (subjectKind : String) (stableId : Option String) :
    CompileResult ResolvedType :=
  let facts := topFacts evidence name
  match facts with
  | [] =>
      match expected with
      | some asserted =>
          let asserted := canonicalizeModelType asserted
          let ds :=
            if asserted.wellFormed then
              [diag "MIC-R-TYPE-003" .obligation subjectKind stableId primary
                (("origin", "contractAssertion") :: typeArguments name)]
            else
              [diag "MIC-R-TYPE-001" .error subjectKind stableId primary
                (("reason", "ill-formed asserted type") :: typeArguments name)]
          finishCompile (some { type := asserted, origins := [.contractAssertion] }) ds
      | none =>
          finishCompile none
            [diag "MIC-R-TYPE-002" .error subjectKind stableId primary (typeArguments name)]
  | first :: rest =>
      let firstType := canonicalizeModelType first.type
      let conflicts := rest.filter (fun fact =>
        canonicalizeModelType fact.type != firstType)
      let related := conflicts.map (·.location)
      let conflictDs :=
        if conflicts.isEmpty then [] else
          [{ (diag "MIC-R-TYPE-001" .error subjectKind stableId first.location
              (("reason", "conflicting declaration evidence") :: typeArguments name)) with
              related := related }]
      let malformedDs :=
        if firstType.wellFormed then [] else
          [diag "MIC-R-TYPE-001" .error subjectKind stableId first.location
            (("reason", "ill-formed structural type") :: typeArguments name)]
      let expectedDs := match expected with
        | none => []
        | some asserted =>
            if canonicalizeModelType asserted == firstType then [] else
              [diag "MIC-R-TYPE-001" .error subjectKind stableId primary
                (("reason", "contract assertion disagrees with evidence") ::
                  typeArguments name)]
      let origins := stableUniqueOrigins
        (facts.map (·.origin) ++ if expected.isSome then [.contractAssertion] else [])
      finishCompile (some { type := firstType, origins := origins })
        (conflictDs ++ malformedDs ++ expectedDs)

structure PathFailure where
  segmentIndex : Nat
  reason : String
  available : List String := []
  deriving Repr, DecidableEq

private def lookupField (fields : List ModelField) (name : String) : Option ModelType :=
  (fields.find? (fun field => field.wireName == name)).map (·.type)

private def lookupVariant (cases : List VariantCase) (tag : String) : Option ModelType :=
  (cases.find? (fun c => c.tag == tag)).map (·.payload)

private def resolvePathAux : ModelType → List PathSegment → Nat →
    Except PathFailure ModelType
  | current, [], _ => .ok current
  | current, segment :: rest, index =>
      let next : Except PathFailure ModelType := match segment, current with
        | .field name, .record fields =>
            match lookupField fields name with
            | some t => .ok t
            | none => .error
                { segmentIndex := index, reason := "record field does not exist",
                  available := sortStrings (fields.map (·.wireName)) }
        | .index i, .tuple elements =>
            match elements[i]? with
            | some t => .ok t
            | none => .error
                { segmentIndex := index, reason := "tuple index is out of range" }
        | .index _, .seq element => .ok element
        | .mapKey key, .map keyType valueType =>
            if key.hasType keyType then .ok valueType else
              .error { segmentIndex := index, reason := "map key has the wrong type" }
        | .variantValue tag, .variant cases =>
            match lookupVariant cases tag with
            | some t => .ok t
            | none => .error
                { segmentIndex := index, reason := "variant case does not exist",
                  available := sortStrings (cases.map (·.tag)) }
        | .field _, _ => .error
            { segmentIndex := index, reason := "field segment requires a record" }
        | .index _, _ => .error
            { segmentIndex := index, reason := "index segment requires a tuple or sequence" }
        | .mapKey _, _ => .error
            { segmentIndex := index, reason := "mapKey segment requires a map" }
        | .variantValue _, _ => .error
            { segmentIndex := index, reason := "variantValue segment requires a variant" }
      match next with
      | .ok t => resolvePathAux t rest (index + 1)
      | .error e => .error e

def resolvePathType (root : ModelType) (path : List PathSegment) :
    Except PathFailure ModelType :=
  resolvePathAux (canonicalizeModelType root) path 0

@[simp] theorem resolvePathType_empty (root : ModelType) :
    resolvePathType root [] = .ok (canonicalizeModelType root) := rfl

private def rootVariables (phase : ActionPhase) (evidence : ModelEvidence)
    (run : RunProfile) : List String :=
  match phase with
  | .initialize => requiredObservationVars evidence run
  | .transition => effectiveParamVars evidence run

private def expectedRoot (phase : ActionPhase) : PathRoot :=
  match phase with
  | .initialize => .initialState
  | .transition => .stepParameters

private def resolveRootFields (evidence : ModelEvidence) (names : List String)
    (primary : SourceLocation) (subjectKind : String) (stableId : Option String) :
    CompileResult (List ModelField) :=
  let results := names.map (fun name =>
    (name, resolveTopType evidence name none primary subjectKind stableId))
  let fields := results.filterMap (fun pair =>
    pair.2.value.map (fun resolved =>
      ({ wireName := pair.1, type := resolved.type } : ModelField)))
  let ds := results.flatMap (fun pair => pair.2.diagnostics)
  finishCompile (some (sortFields fields)) ds

private def resolveProjection (input : ContractInput) (phase : ActionPhase)
    (evidence : ModelEvidence) (run : RunProfile) (primary : SourceLocation) :
    CompileResult (InputProjection × List EvidenceOrigin) :=
  if input.fromRoot != expectedRoot phase then
    finishCompile none
      [diag "MIC-R-PATH-001" .error "input" (some input.id) primary
        [("reason", "input root is not legal for its action phase")]]
  else
    let names := rootVariables phase evidence run
    match input.path with
    | [] =>
        let rootResult := resolveRootFields evidence names primary "input" (some input.id)
        match rootResult.value with
        | none => { value := none, diagnostics := rootResult.diagnostics }
        | some fields =>
            let rootType := ModelType.record fields
            let assertionDs := match input.expectedType with
              | none => []
              | some expected =>
                  if canonicalizeModelType expected == rootType then [] else
                    [diag "MIC-R-TYPE-001" .error "input" (some input.id) primary
                      [("reason", "input assertion disagrees with resolved root")]]
            finishCompile
              (some ({ root := input.fromRoot, path := [], type := rootType }, []))
              (rootResult.diagnostics ++ assertionDs)
    | .field name :: rest =>
        if !names.contains name then
          finishCompile none
            [diag "MIC-R-PATH-001" .error "input" (some input.id) primary
              [("reason", "root field is unavailable"), ("field", name)]]
        else
          let topExpected := if rest.isEmpty then input.expectedType else none
          let top := resolveTopType evidence name topExpected primary "input" (some input.id)
          match top.value with
          | none => { value := none, diagnostics := top.diagnostics }
          | some resolved =>
              match resolvePathType resolved.type rest with
              | .error failure =>
                  finishCompile none (top.diagnostics ++
                    [diag "MIC-R-PATH-001" .error "input" (some input.id) primary
                      [("segment", toString (failure.segmentIndex + 1)),
                       ("reason", failure.reason),
                       ("available", String.intercalate "," failure.available)]])
              | .ok leaf =>
                  let assertionDs :=
                    if rest.isEmpty then [] else match input.expectedType with
                    | none => []
                    | some expected =>
                        if canonicalizeModelType expected == leaf then [] else
                          [diag "MIC-R-TYPE-001" .error "input" (some input.id) primary
                            [("reason", "input assertion disagrees with projected type")]]
                  let origins := stableUniqueOrigins
                    (resolved.origins ++ if input.expectedType.isSome then
                      [.contractAssertion] else [])
                  finishCompile
                    (some ({ root := input.fromRoot, path := input.path, type := leaf }, origins))
                    (top.diagnostics ++ assertionDs)
    | _ =>
        finishCompile none
          [diag "MIC-R-PATH-001" .error "input" (some input.id) primary
            [("segment", "0"), ("reason", "payload root requires a field segment")]]

/-! ## Action and observation resolution -/

private def resolveAction (action : ContractAction) (phase : ActionPhase)
    (evidence : ModelEvidence) (run : RunProfile) (base : SourceLocation) :
    CompileResult ResolvedAction :=
  let inputResults := action.inputs.map (fun input =>
    (input, resolveProjection input phase evidence run
      (base.atPointer ("/actions/" ++ action.id ++ "/inputs/" ++ input.id))))
  let inputs := inputResults.filterMap (fun pair =>
    pair.2.value.map (fun projection =>
      ({ id := pair.1.id, projection := projection.1,
         typeOrigins := projection.2 } : ResolvedInput)))
  let ds := inputResults.flatMap (fun pair => pair.2.diagnostics)
  let resolvedAction : ResolvedAction :=
    { id := action.id
      phase := phase
      wireAction := action.wireAction
      wireAliases := sortStrings action.wireAliases
      inputs := sortInputs inputs }
  finishCompile (some resolvedAction) ds

private def resolveObservation (observation : ContractObservation)
    (required : List String) (evidence : ModelEvidence) (base : SourceLocation) :
    CompileResult ResolvedObservation :=
  let primary := base.atPointer ("/observations/" ++ observation.id)
  if !required.contains observation.wireName then
    finishCompile none
      [diag "MIC-R-OBS-002" .error "observation" (some observation.id) primary
        [("wireName", observation.wireName)]]
  else if observation.provenance != .implementation then
    finishCompile none
      [diag "MIC-R-OBS-002" .error "observation" (some observation.id) primary
        [("wireName", observation.wireName),
         ("reason", "version 1 requires implementation provenance")]]
  else
    let resolved := resolveTopType evidence observation.wireName observation.expectedType
      primary "observation" (some observation.id)
    match resolved.value with
    | none => { value := none, diagnostics := resolved.diagnostics }
    | some t =>
        let resolvedObservation : ResolvedObservation :=
          { id := observation.id
            wireName := observation.wireName
            type := t.type
            provenance := .implementation
            typeOrigins := t.origins }
        finishCompile (some resolvedObservation) resolved.diagnostics

/-! ## Aggregate validation -/

private def duplicateDiagnostics (code subjectKind argumentName : String)
    (values : List String) (base : SourceLocation) : List Diagnostic :=
  (duplicateStrings values).map (fun value =>
    diag code .error subjectKind (some value) base [(argumentName, value)])

private def invalidIdDiagnostics (subjectKind : String) (ids : List String)
    (base : SourceLocation) : List Diagnostic :=
  ids.filter (fun id => !validStableId id) |>.map (fun id =>
    diag "MIC-R-ID-001" .error subjectKind (some id) base
      [("reason", "stable id must match [A-Z][A-Za-z0-9]*")])

private def actionInputDiagnostics (action : ContractAction)
    (base : SourceLocation) : List Diagnostic :=
  let ids := action.inputs.map (·.id)
  invalidIdDiagnostics "input" ids base ++
    duplicateDiagnostics "MIC-R-ID-001" "input" "id" ids base

private def actionLabels (action : ContractAction) : List String :=
  action.wireAction :: action.wireAliases

private def limitDiagnostic (subjectKind reason : String)
    (actual limit : Nat) (base : SourceLocation)
    (stableId : Option String := none) : Diagnostic :=
  diag "MIC-R-LIMIT-001" .error subjectKind stableId base
    [("actual", toString actual), ("limit", toString limit), ("resource", reason)]

private def contractResourceDiagnostics (input : ResolveInput) : List Diagnostic :=
  let contract := input.contract.value
  let base := input.contract.location
  let allActions := contract.initializers ++ contract.actions
  let actionCountDs :=
    (if contract.initializers.length > maxInitializersV1 then
      [limitDiagnostic "initializer" "initializers" contract.initializers.length
        maxInitializersV1 base]
    else []) ++
    (if contract.actions.length > maxTransitionActionsV1 then
      [limitDiagnostic "action" "transitionActions" contract.actions.length
        maxTransitionActionsV1 base]
    else []) ++
    (if contract.observations.length > maxObservationsV1 then
      [limitDiagnostic "observation" "observations" contract.observations.length
        maxObservationsV1 base]
    else [])
  let perActionDs := allActions.flatMap fun action =>
    (if action.wireAliases.length > maxAliasesPerActionV1 then
      [limitDiagnostic "action" "aliasesPerAction" action.wireAliases.length
        maxAliasesPerActionV1 base (some action.id)]
    else []) ++
    (if action.inputs.length > maxInputsPerActionV1 then
      [limitDiagnostic "action" "inputsPerAction" action.inputs.length
        maxInputsPerActionV1 base (some action.id)]
    else []) ++
    action.inputs.filterMap (fun input =>
      if input.path.length > maxPathSegmentsV1 then
        some (limitDiagnostic "input" "pathSegments" input.path.length
          maxPathSegmentsV1 base (some input.id))
      else none)
  let requiredCount := (requiredObservationVars input.evidence input.runProfile).length
  let requiredDs :=
    if requiredCount > maxObservationsV1 then
      [limitDiagnostic "evidence" "comparableVariables" requiredCount
        maxObservationsV1 base]
    else []
  let assertedTypes :=
    allActions.flatMap (fun action => action.inputs.filterMap (·.expectedType)) ++
      contract.observations.filterMap (·.expectedType)
  let allTypes := input.evidence.typeFacts.map (·.type) ++ assertedTypes
  let totalNodes := allTypes.foldl (fun total type =>
    total + modelTypeNodeCount type) 0
  let typeDs :=
    (if totalNodes > maxNormalizedTypeNodesV1 then
      [limitDiagnostic "typeEvidence" "normalizedTypeNodes" totalNodes
        maxNormalizedTypeNodesV1 base]
    else []) ++
    (allTypes.filterMap fun type =>
      let depth := modelTypeDepth type
      if depth > maxStructuralTypeDepthV1 then
        some (limitDiagnostic "typeEvidence" "structuralTypeDepth" depth
          maxStructuralTypeDepthV1 base)
      else none)
  let stableNames :=
    [contract.model.moduleName, contract.wire.actionVariable] ++
    contract.wire.parameterVariable.toList ++
    allActions.flatMap (fun action =>
      action.id :: action.wireAction :: action.wireAliases ++
        action.inputs.flatMap (fun input => input.id :: pathWireNames input.path)) ++
    contract.observations.flatMap (fun observation =>
      [observation.id, observation.wireName]) ++
    allTypes.flatMap modelTypeWireNames
  let nameDs := (stableUniqueStrings stableNames).filterMap fun name =>
    let bytes := name.toUTF8.size
    if bytes > maxStableNameBytesV1 then
      some (limitDiagnostic "name" "stableIdOrWireLabelBytes" bytes
        maxStableNameBytesV1 base (some name))
    else none
  actionCountDs ++ perActionDs ++ requiredDs ++ typeDs ++ nameDs

private def contractDiagnostics (input : ResolveInput) : List Diagnostic :=
  let contract := input.contract.value
  let base := input.contract.location
  let allActions := contract.initializers ++ contract.actions
  let actionIds := allActions.map (·.id)
  let observationIds := contract.observations.map (·.id)
  let observationNames := contract.observations.map (·.wireName)
  let allLabels := allActions.flatMap actionLabels
  let initLabels := contract.initializers.flatMap actionLabels
  let transitionLabels := contract.actions.flatMap actionLabels
  let phaseOverlap := stableUniqueStrings <|
    initLabels.filter (fun label => transitionLabels.contains label)
  let schemaDs :=
    if contract.schema == contractSchemaV1 then [] else
      [diag "MIC-R-SCHEMA-001" .error "contract" none base
        [("schema", contract.schema)]]
  let versionDs :=
    if validInterfaceVersion contract.interfaceVersion then [] else
      [diag "MIC-R-SCHEMA-001" .error "contract" none base
        [("reason", "interfaceVersion must have three decimal components")]]
  let modelDs :=
    (if validModuleName contract.model.moduleName then [] else
      [diag "MIC-R-SCHEMA-001" .error "model" none base
        [("reason", "invalid model module"), ("module", contract.model.moduleName)]]) ++
    (if validLogicalPath contract.model.source then [] else
      [diag "MIC-R-SCHEMA-001" .error "model" none base
        [("reason", "model source must be a normalized relative path")]])
  let wireDs :=
    (if contract.wire.actionVariable == actionVariableV1 then [] else
      [diag "MIC-R-ACTION-001" .error "wire" none base
        [("actionVariable", contract.wire.actionVariable)]]) ++
    (if contract.wire.parameterVariable == input.runProfile.configuredParamVar then [] else
      [diag "MIC-R-PARAM-001" .error "wire" none base
        [("contract", contract.wire.parameterVariable.getD ""),
         ("runProfile", input.runProfile.configuredParamVar.getD "")]])
  let initializerDs :=
    if contract.initializers.isEmpty then
      [diag "MIC-R-ACTION-001" .error "initializer" none base
        [("reason", "at least one initializer is required")]] else []
  let labelDs :=
    allActions.flatMap (fun action =>
      (if action.wireAction.isEmpty then
        [diag "MIC-R-ACTION-001" .error "action" (some action.id) base
          [("reason", "wire action is empty")]] else []) ++
      (action.wireAliases.filter (·.isEmpty)).map (fun _ =>
        diag "MIC-R-ACTION-001" .error "action" (some action.id) base
          [("reason", "wire alias is empty")])) ++
    duplicateDiagnostics "MIC-R-ACTION-001" "wireAction" "label" allLabels base ++
    phaseOverlap.map (fun label =>
      diag "MIC-R-ACTION-002" .error "wireAction" (some label) base
        [("label", label)])
  let evidenceDs :=
    duplicateDiagnostics "MIC-R-TYPE-001" "traceVariable" "name"
      input.evidence.traceVars base ++
    duplicateDiagnostics "MIC-R-PARAM-001" "parameterVariable" "name"
      input.evidence.itfParamVars base ++
    ((input.evidence.itfParamVars.filter (fun name =>
      !input.evidence.traceVars.contains name)).map (fun name =>
        diag "MIC-R-PARAM-001" .error "parameterVariable" (some name) base
          [("reason", "parameter variable is absent from trace vars")])) ++
    ((input.evidence.typeFacts.filter (fun fact => !fact.type.wellFormed)).map (fun fact =>
      diag "MIC-R-TYPE-001" .error "typeEvidence" (some fact.modelPath.root)
        fact.location [("reason", "ill-formed structural type")]))
  let actionType := resolveTopType input.evidence contract.wire.actionVariable none
    base "wire" none
  let actionTypeDs := actionType.diagnostics ++ match actionType.value with
    | some resolved =>
        if resolved.type == .str then [] else
          [diag "MIC-R-TYPE-001" .error "wire" none base
            [("modelPath", contract.wire.actionVariable),
             ("reason", "action variable must have type Str")]]
    | none => []
  contractResourceDiagnostics input ++
    schemaDs ++ versionDs ++ modelDs ++ wireDs ++ initializerDs ++ labelDs ++
    evidenceDs ++ actionTypeDs ++
    invalidIdDiagnostics "action" actionIds base ++
    duplicateDiagnostics "MIC-R-ID-001" "action" "id" actionIds base ++
    allActions.flatMap (fun action => actionInputDiagnostics action base) ++
    invalidIdDiagnostics "observation" observationIds base ++
    duplicateDiagnostics "MIC-R-ID-001" "observation" "id" observationIds base ++
    duplicateDiagnostics "MIC-R-OBS-002" "observation" "wireName" observationNames base

private def missingObservationDiagnostics (required : List String)
    (observations : List ContractObservation) (base : SourceLocation) : List Diagnostic :=
  let declared := observations.map (·.wireName)
  (required.filter (fun name => !declared.contains name)).map (fun name =>
    diag "MIC-R-OBS-001" .error "observation" none base [("wireName", name)])

/-! ## Decoded descriptor validation -/

private def namesWithinLimit (names : List String) : Bool :=
  names.all (fun name => name.toUTF8.size ≤ maxStableNameBytesV1)

private def originsUnique (origins : List EvidenceOrigin) : Bool :=
  (stableUniqueOrigins origins).length == origins.length

private def resolvedInputWellFormedV1 (phase : ActionPhase)
    (input : ResolvedInput) : Bool :=
  validStableId input.id && input.id.toUTF8.size ≤ maxStableNameBytesV1 &&
    input.projection.root == expectedRoot phase &&
    input.projection.path.length ≤ maxPathSegmentsV1 &&
    namesWithinLimit (pathWireNames input.projection.path) &&
    input.projection.type.wellFormed &&
    modelTypeDepth input.projection.type ≤ maxStructuralTypeDepthV1 &&
    namesWithinLimit (modelTypeWireNames input.projection.type) &&
    originsUnique input.typeOrigins

private def resolvedActionWellFormedV1 (phase : ActionPhase)
    (action : ResolvedAction) : Bool :=
  let labels := action.wireAction :: action.wireAliases
  action.phase == phase && validStableId action.id &&
    action.id.toUTF8.size ≤ maxStableNameBytesV1 &&
    !action.wireAction.isEmpty &&
    labels.all (fun label => label.toUTF8.size ≤ maxStableNameBytesV1) &&
    (duplicateStrings labels).isEmpty &&
    action.wireAliases.length ≤ maxAliasesPerActionV1 &&
    action.inputs.length ≤ maxInputsPerActionV1 &&
    (duplicateStrings (action.inputs.map (·.id))).isEmpty &&
    action.inputs.all (resolvedInputWellFormedV1 phase)

private def resolvedObservationWellFormedV1
    (observation : ResolvedObservation) : Bool :=
  validStableId observation.id &&
    observation.id.toUTF8.size ≤ maxStableNameBytesV1 &&
    !observation.wireName.isEmpty &&
    observation.wireName.toUTF8.size ≤ maxStableNameBytesV1 &&
    observation.provenance == .implementation &&
    observation.type.wellFormed &&
    modelTypeDepth observation.type ≤ maxStructuralTypeDepthV1 &&
    namesWithinLimit (modelTypeWireNames observation.type) &&
    originsUnique observation.typeOrigins

/-- Semantic validation for a descriptor decoded from a lock, cache, or wire
envelope. This checks every invariant that does not require the original
contract/evidence locations. -/
def semanticDescriptorWellFormedV1 (descriptor : SemanticDescriptor) : Bool :=
  let allActions := descriptor.initializers ++ descriptor.actions
  let labels := allActions.flatMap (fun action =>
    action.wireAction :: action.wireAliases)
  let types := allActions.flatMap (fun action =>
      action.inputs.map (·.projection.type)) ++
    descriptor.observations.map (·.type)
  let typeNodes := types.foldl (fun total type =>
    total + modelTypeNodeCount type) 0
  let effective := sortStrings <| stableUniqueStrings <|
    descriptor.runProfile.itfParamVars ++
      descriptor.runProfile.configuredParamVar.toList
  descriptor.schema == descriptorSchemaV1 &&
    validInterfaceVersion descriptor.interfaceVersion &&
    validModuleName descriptor.modelModule &&
    descriptor.resolverSemanticsVersion == resolverSemanticsV1 &&
    descriptor.comparisonPolicyVersion == comparisonPolicyV1 &&
    descriptor.runProfile.actionVariable == actionVariableV1 &&
    (duplicateStrings descriptor.runProfile.itfParamVars).isEmpty &&
    descriptor.runProfile.effectiveParamVars == effective &&
    descriptor.initializers.length > 0 &&
    descriptor.initializers.length ≤ maxInitializersV1 &&
    descriptor.actions.length ≤ maxTransitionActionsV1 &&
    descriptor.observations.length ≤ maxObservationsV1 &&
    (duplicateStrings (allActions.map (·.id))).isEmpty &&
    (duplicateStrings labels).isEmpty &&
    descriptor.initializers.all (resolvedActionWellFormedV1 .initialize) &&
    descriptor.actions.all (resolvedActionWellFormedV1 .transition) &&
    (duplicateStrings (descriptor.observations.map (·.id))).isEmpty &&
    (duplicateStrings (descriptor.observations.map (·.wireName))).isEmpty &&
    descriptor.observations.all resolvedObservationWellFormedV1 &&
    typeNodes ≤ maxNormalizedTypeNodesV1

/-! ## Public resolver -/

def resolve (input : ResolveInput) : CompileResult ResolvedModelInterface :=
  let contract := normalizeContractV1 input.contract.value
  let required := requiredObservationVars input.evidence input.runProfile
  let initResults := contract.initializers.map (fun action =>
    resolveAction action .initialize input.evidence input.runProfile input.contract.location)
  let actionResults := contract.actions.map (fun action =>
    resolveAction action .transition input.evidence input.runProfile input.contract.location)
  let observationResults := contract.observations.map (fun observation =>
    resolveObservation observation required input.evidence input.contract.location)
  let initializers := initResults.filterMap (·.value)
  let actions := actionResults.filterMap (·.value)
  let observations := observationResults.filterMap (·.value)
  let diagnostics :=
    contractDiagnostics input ++
    missingObservationDiagnostics required contract.observations input.contract.location ++
    initResults.flatMap (·.diagnostics) ++ actionResults.flatMap (·.diagnostics) ++
    observationResults.flatMap (·.diagnostics)
  let descriptor : SemanticDescriptor :=
    { interfaceVersion := contract.interfaceVersion
      modelModule := contract.model.moduleName
      runProfile := resolvedRunProfile contract input.evidence input.runProfile
      initializers := sortActions initializers
      actions := sortActions actions
      observations := sortObservations observations }
  let provenance : LockProvenance :=
    { compilerVersion := input.compilerVersion
      contractSha256 := input.contractSha256
      evidenceSha256 := input.evidence.evidenceSha256
      sources := sortSources input.sources }
  finishCompile (some { toSemanticDescriptor := descriptor, contract, provenance }) diagnostics

/-- Attach shell-computed canonical digests without changing resolution
diagnostics or rerunning resolution. -/
def lockResolved (result : CompileResult ResolvedModelInterface)
    (semanticDigest : SemanticDigest) (provenanceDigest : ProvenanceDigest) :
    CompileResult LockedModelInterface :=
  { value := result.value.map (fun resolved =>
      resolved.withDigests semanticDigest provenanceDigest)
    diagnostics := result.diagnostics }

theorem lockResolved_preserves_diagnostics (result : CompileResult ResolvedModelInterface)
    (semantic provenance : String) :
    (lockResolved result semantic provenance).diagnostics = result.diagnostics := rfl

end Core.ModelInterface
