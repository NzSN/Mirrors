import Core.Tla.Diagnostic
import Core.Tla.Graph
import Core.Tla.Names
import Lean.Data.Json

/-!
# TLA+ frontend inspection JSON (`Codec/TlaFrontendJson.lean`)

Closed, versioned JSON documents for the development-only `tla_frontend`
executable (`Docs/model-interface-compiler/tla-frontend-design.md`, §24
"Inspection tool").

Every document carries `schema` = `mirrors.tla-frontend-inspection/v1`, the
`command` tag, an `ok` flag, the captured root's logical path, and a bounded
diagnostic array. Fact sections project the same `Shell.Tla.Frontend` result the
model-interface compiler consumes, so a fact that would need a second analysis
cannot appear here.

Locations are logical: the declaring module name plus the captured logical path
of that module, never a physical path. The key set of every document and nested
object is fixed by this module; caller text never reaches a key position.
-/

namespace Codec.TlaFrontendJson

open Core.Tla
open Lean

/-- Schema identity of every document the inspection CLI emits. -/
def schema : String := "mirrors.tla-frontend-inspection/v1"

/-! ## Rendering helpers -/

/-- Stable operator-fixity rendering. -/
def fixityString : OperatorFixity → String
  | .functional => "functional"
  | .prefix => "prefix"
  | .infix => "infix"
  | .postfix => "postfix"

/-- Stable assumption-kind rendering. -/
def assumptionKindString : AssumptionKind → String
  | .assume => "assume"
  | .assumption => "assumption"
  | .axiom => "axiom"

private def positionJson (position : SourcePosition) : Json :=
  Json.mkObj [
    ("column", Json.num position.column),
    ("line", Json.num position.line),
    ("offset", Json.num position.offset)
  ]

/-- One half-open source range as `{start, stop}`. -/
def rangeJson (range : SourceRange) : Json :=
  Json.mkObj [
    ("start", positionJson range.start),
    ("stop", positionJson range.stop)
  ]

/-- One logical source location. `pathOf` resolves a declaring module to its
captured logical path; `null` means the module supplies no captured source
(pinned standard modules) or the location predates module-name discovery. -/
def locationJson (pathOf : ModuleName → Option String)
    (location : SourceLocation) : Json :=
  let path :=
    match location.moduleName.bind pathOf with
    | some captured => some captured
    | none => if location.logicalPath.isEmpty then none else some location.logicalPath
  Json.mkObj [
    ("module", match location.moduleName with
      | some name => Json.str name.name
      | none => Json.null),
    ("path", match path with
      | some captured => Json.str captured
      | none => Json.null),
    ("range", rangeJson location.range)
  ]

/-- One structured diagnostic as a closed JSON object. -/
def diagnosticJson (diagnostic : Diagnostic) : Json :=
  Json.mkObj [
    ("arguments", Json.arr (diagnostic.arguments.map fun argument =>
      Json.mkObj [("name", Json.str argument.1), ("value", Json.str argument.2)])),
    ("code", Json.str diagnostic.code),
    ("location", locationJson (fun _ => none) diagnostic.primary),
    ("message", Json.str diagnostic.message),
    ("related", Json.arr (diagnostic.related.map fun related =>
      Json.mkObj [
        ("location", locationJson (fun _ => none) related.location),
        ("message", Json.str related.message)
      ])),
    ("severity", Json.str diagnostic.severity.toString),
    ("stage", Json.str diagnostic.stage.toString)
  ]

/-- A bounded diagnostic array in report order. -/
def diagnosticsJson (diagnostics : Array Diagnostic) : Json :=
  Json.arr (diagnostics.map diagnosticJson)

/-! ## Effective facts -/

/-- One effective root variable with its declaration origin and import path. -/
def variableJson (pathOf : ModuleName → Option String)
    (entry : ResolvedVariable) : Json :=
  Json.mkObj [
    ("declaredIn", Json.str entry.declaredIn.name),
    ("declaredName", Json.str entry.declaredName),
    ("importPath", Json.arr (entry.importPath.map fun name => Json.str name.name)),
    ("local", Json.bool entry.localDeclaration),
    ("location", locationJson pathOf
      { moduleName := some entry.declaredIn, logicalPath := ""
        range := entry.declarationRange }),
    ("name", Json.str entry.visibleName)
  ]

/-- One resolved operator with arity, fixity, and classified level. -/
def operatorJson (pathOf : ModuleName → Option String)
    (operator : ResolvedOperator) : Json :=
  Json.mkObj [
    ("arity", Json.num operator.arity),
    ("declaredIn", Json.str operator.declaredIn.name),
    ("fixity", Json.str (fixityString operator.fixity)),
    ("importPath", Json.arr (operator.importPath.map fun name => Json.str name.name)),
    ("level", Json.str operator.level.toString),
    ("local", Json.bool operator.localDeclaration),
    ("location", locationJson pathOf
      { moduleName := some operator.declaredIn, logicalPath := ""
        range := operator.declarationRange }),
    ("name", Json.str operator.name)
  ]

/-- One classified symbol level; `kind` names the declaration family. -/
def levelJson (kind name : String) (level : Level) (declaredIn : ModuleName)
    (localDeclaration : Bool) : Json :=
  Json.mkObj [
    ("declaredIn", Json.str declaredIn.name),
    ("kind", Json.str kind),
    ("level", Json.str level.toString),
    ("local", Json.bool localDeclaration),
    ("name", Json.str name)
  ]

/-- Every effective symbol with its classified level, in declaration order:
constants, variables, operators, then assumption-like declarations. Unnamed
assumptions carry an empty `name` and their `kind` distinguishes them through
the resolved operator and assumption arrays. -/
def levelsJson (elaborated : ElaboratedModule) : Json :=
  let constants := elaborated.constants.map fun entry =>
    levelJson "constant" entry.name .constant entry.declaredIn entry.localDeclaration
  let variables := elaborated.variables.map fun entry =>
    levelJson "variable" entry.visibleName .state entry.declaredIn entry.localDeclaration
  let operators := elaborated.operators.map fun entry =>
    levelJson "operator" entry.name entry.level entry.declaredIn entry.localDeclaration
  let assumptions := elaborated.assumptions.map fun entry =>
    levelJson "assumption" "" entry.level entry.declaredIn entry.localDeclaration
  Json.arr (constants ++ variables ++ operators ++ assumptions)

/-- One captured source unit as published in the manifest. -/
def sourceJson (identity : SourceIdentity) : Json :=
  Json.mkObj [
    ("module", Json.str identity.moduleName.name),
    ("path", Json.str identity.logicalPath),
    ("sha256", Json.str identity.contentSha256)
  ]

/-- One module dependency edge. Substitution actuals are carried as formal
names, arities, and ranges; expression bodies stay out of the inspection
schema. -/
def dependencyJson (pathOf : ModuleName → Option String)
    (edge : ModuleEdge) : Json :=
  Json.mkObj [
    ("declarationOrder", Json.num edge.declarationOrder),
    ("dependency", Json.str edge.dependency.name),
    ("kind", Json.str edge.kind.toString),
    ("local", Json.bool edge.«local»),
    ("location", locationJson pathOf
      { moduleName := some edge.owner, logicalPath := "", range := edge.range }),
    ("owner", Json.str edge.owner.name),
    ("resolution", Json.str edge.resolution.toString),
    ("substitutions", Json.arr (edge.substitutions.map fun substitution =>
      Json.mkObj [
        ("arity", Json.num substitution.formalArity),
        ("formal", Json.str substitution.formal),
        ("range", rangeJson substitution.range)
      ]))
  ]

/-! ## Documents -/

/-- Fact sections an inspection document may carry. -/
structure Sections where
  variables : Bool := true
  dependencies : Bool := true
  operators : Bool := true
  levels : Bool := true
  deriving Repr, BEq

private def modulePathOf (graph : ResolvedModuleGraph) :
    ModuleName → Option String :=
  fun name => (graph.findNode? name).map fun node => node.logicalPath

private def header (command : String) (ok : Bool) (logicalPath : String) :
    List (String × Json) :=
  [("command", Json.str command),
   ("ok", Json.bool ok),
   ("schema", Json.str schema),
   ("source", Json.mkObj [("path", Json.str logicalPath)])]

private def hasError (diagnostics : Array Diagnostic) : Bool :=
  diagnostics.any fun diagnostic => diagnostic.severity.isError

/-- The `parse` document: syntax facts only, with the same keys whether or not
the parse succeeded. `module` is `null` and the counts are zero when no
complete module was produced. -/
def parseDocument (logicalPath : String) (module? : Option ParsedModule)
    (diagnostics : Array Diagnostic) : Json :=
  let ok := !hasError diagnostics && module?.isSome
  let declarations := match module? with
    | some module => module.declarations.size
    | none => 0
  let dependencies := match module? with
    | some module => module.dependencies.size
    | none => 0
  Json.mkObj (header "parse" ok logicalPath ++ [
    ("declarations", Json.num declarations),
    ("dependencies", Json.num dependencies),
    ("diagnostics", diagnosticsJson diagnostics),
    ("module", match module? with
      | some module => Json.str module.name.name
      | none => Json.null)
  ])

private def emptySections (sections : Sections) : List (String × Json) :=
  (if sections.variables then [("variables", Json.arr #[])] else []) ++
  (if sections.dependencies then [("dependencies", Json.arr #[])] else []) ++
  (if sections.operators then [("operators", Json.arr #[])] else []) ++
  (if sections.levels then [("levels", Json.arr #[])] else [])

private def factSections (sections : Sections) (graph : ResolvedModuleGraph)
    (elaborated : ElaboratedModule) : List (String × Json) :=
  let pathOf := modulePathOf graph
  (if sections.variables then
    [("variables", Json.arr (elaborated.variables.map (variableJson pathOf)))]
   else []) ++
  (if sections.dependencies then
    [("dependencies", Json.arr (graph.canonicalEdges.map (dependencyJson pathOf)))]
   else []) ++
  (if sections.operators then
    [("operators", Json.arr (elaborated.operators.map (operatorJson pathOf)))]
   else []) ++
  (if sections.levels then [("levels", levelsJson elaborated)] else [])

/-- The `resolve` document: full graph resolution and elaboration with the
complete captured source manifest. A failed analysis keeps the same keys with
empty fact sections and `ok = false`. -/
def resolveDocument (logicalPath : String)
    (result? : Option (ResolvedModuleGraph × ElaboratedModule))
    (diagnostics : Array Diagnostic) : Json :=
  let sections : Sections := {}
  let ok := !hasError diagnostics && result?.isSome
  let facts := match result? with
    | some (graph, elaborated) =>
        factSections sections graph elaborated ++
        [("sources", Json.arr (elaborated.sourceManifest.map sourceJson)),
         ("module", Json.str elaborated.moduleName.name)]
    | none =>
        emptySections sections ++
        [("sources", Json.arr #[]), ("module", Json.null)]
  Json.mkObj (header "resolve" ok logicalPath ++ facts ++
    [("diagnostics", diagnosticsJson diagnostics)])

/-- The `inspect` document: the requested fact sections projected from the same
analysis. A failed analysis keeps the same keys with empty fact sections and
`ok = false`. -/
def inspectDocument (logicalPath : String) (sections : Sections)
    (result? : Option (ResolvedModuleGraph × ElaboratedModule))
    (diagnostics : Array Diagnostic) : Json :=
  let ok := !hasError diagnostics && result?.isSome
  let facts := match result? with
    | some (graph, elaborated) => factSections sections graph elaborated
    | none => emptySections sections
  let module? := match result? with
    | some (_, elaborated) => some elaborated.moduleName
    | none => none
  Json.mkObj (header "inspect" ok logicalPath ++ facts ++
    [("diagnostics", diagnosticsJson diagnostics),
     ("module", match module? with
       | some name => Json.str name.name
       | none => Json.null)])

end Codec.TlaFrontendJson
