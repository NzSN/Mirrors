import Core.Tla.Elaboration
import Core.Tla.Parser
import Shell.Tla.ModuleResolver
import Shell.Tla.SourceProvider

/-!
# Unified TLA+ frontend (`Shell/Tla/Frontend.lean`)

One analysis entry point for every model-interface command
(`Docs/model-interface-compiler/tla-frontend-design.md`, §7 "Frontend interface",
§16 "Effective model facts", and §17 "Model-interface compiler integration").

`analyze` composes the three accepted slices in order: the borrowed or inline
source provider captures bytes, the module resolver builds one captured graph,
and the pure elaborator resolves declarations, `EXTENDS` visibility, `INSTANCE`
substitutions, and levels. `analyzeFile` additionally discovers the declared
module name of a borrowed root file through the frontend's own parse seam, so a
caller with only a path never runs a second lexical scanner.

`admitEvidence` is the frontend's evidence boundary: raw ITF variables must
equal the elaborated effective variables as sets before any parameter partition
or projection. Source-only variables keep their resolved declaration origin so
diagnostics can name the declaring module without inventing one.
-/

namespace Shell.Tla

open Core.Tla

/-! ## Limits and requests -/

/-- Budgets for one frontend analysis. Resolver budgets bound graph
construction; elaboration budgets bound declarations, symbols, and
diagnostics. -/
structure FrontendLimits where
  resolver : ResolverLimits := {}
  elaboration : ElaborationLimits := {}
  deriving Repr, BEq

/-- Analyze one root reference through one provider. -/
structure FrontendRequest where
  root : ModuleRef
  profile : LanguageProfile := LanguageProfile.default
  limits : FrontendLimits := {}
  deriving Repr

/-- A failed analysis: bounded structured diagnostics and no partial graph. -/
structure FrontendFailure where
  diagnostics : Array Diagnostic
  deriving Repr, BEq

/-- One successfully analyzed root: the captured graph, the elaborated root
facts, and (for interface parity with `FrontendFailure`) an empty diagnostic
list. A result carrying any error diagnostic never reaches this type. -/
structure FrontendResult where
  root : ModuleName
  graph : ResolvedModuleGraph
  elaborated : ElaboratedModule
  diagnostics : Array Diagnostic := #[]

namespace FrontendResult

/-- The effective root variables with declaration origins, in declaration
order. -/
def variables (result : FrontendResult) : Array ResolvedVariable :=
  result.elaborated.variables

/-- The effective root variable names in declaration order. -/
def variableNames (result : FrontendResult) : List String :=
  result.elaborated.variables.toList.map (fun entry => entry.visibleName)

/-- The complete sorted captured source manifest. -/
def sourceManifest (result : FrontendResult) : Array SourceIdentity :=
  result.elaborated.sourceManifest

/-- The logical path of the captured module with the given name, if any. -/
def logicalPath? (result : FrontendResult) (moduleName : ModuleName) :
    Option String :=
  (result.graph.findNode? moduleName).map (fun node => node.logicalPath)

end FrontendResult

/-! ## Analysis -/

/-- The resolver's parser seam: the revision-1 TF2 parser under the request's
language profile. -/
def parseUnitWith (profile : LanguageProfile) : ParseModule :=
  fun unit => pure (parseSource profile ParserProfile.default {} {} unit)

/-- Analyze one root reference into a complete frontend result. A parse, graph,
or elaboration failure never crosses the success path; the caller receives
bounded diagnostics instead of a partial graph. -/
def analyze (provider : SourceProvider) (request : FrontendRequest) :
    IO (Except FrontendFailure FrontendResult) := do
  let config : ResolverConfig :=
    { provider := provider
      parse := parseUnitWith request.profile
      limits := request.limits.resolver }
  match ← resolve config request.root with
  | .error failure => pure (.error { diagnostics := failure.diagnostics })
  | .ok graph =>
      match Core.Tla.elaborate request.profile request.limits.elaboration graph with
      | .error diagnostics => pure (.error { diagnostics := diagnostics.toArray })
      | .ok elaborated => pure (.ok { root := graph.root, graph, elaborated })

/-! ## Borrowed root files -/

/-- A borrowed-root request: `specPath` names a file whose declared module name
is discovered from its captured bytes. Dependencies resolve to sibling
`<Name>.tla` files under the same directory, and the pinned catalog supplies
standard-module identity. -/
structure FrontendFileRequest where
  specPath : String
  profile : LanguageProfile := LanguageProfile.default
  limits : FrontendLimits := {}
  sourceLimits : SourceProviderLimits := {}
  catalog : StandardModuleCatalog := StandardModuleCatalog.default

private def zeroRange : SourceRange :=
  { start := { offset := 0, line := 1, column := 1 },
    stop := { offset := 0, line := 1, column := 1 } }

private def logicalLocation (logicalPath : String) : SourceLocation :=
  { moduleName := none, logicalPath, range := zeroRange }

private def rootFailure (code logicalPath message : String) : FrontendFailure :=
  { diagnostics := #[Diagnostic.error code .moduleGraph message
      (logicalLocation logicalPath)] }

/-- `true` when the diagnostic reports a root that could not be captured at all
(unreadable, symbolic link, special file, oversized, or invalid UTF-8). Callers
that distinguish infrastructure failures from findings use this test. -/
def FrontendFailure.rootCaptureFailed (failure : FrontendFailure) : Bool :=
  failure.diagnostics.any fun diagnostic =>
    diagnostic.code == "TLA-FRONTEND-ROOT-READ"

/-- Capture and parse one borrowed root file without resolving its graph. The
declared module name comes from the frontend's own parse of the captured
bytes, so a caller that only has a path never runs a second scanner, and the
captured unit is returned so a later resolution reuses it instead of reading
the root twice. `parse` on the development inspection CLI is the direct caller;
`analyzeFile` continues from the same result. -/
def captureRootFile (request : FrontendFileRequest) :
    IO (Except FrontendFailure (String × SourceUnit × ParsedModule)) := do
  let rootPath : System.FilePath := request.specPath
  let some logicalPath := rootPath.fileName
    | return .error (rootFailure "TLA-FRONTEND-ROOT-PATH" request.specPath
        "model source path has no filename")
  let rootDir := rootPath.parent.getD ("." : System.FilePath)
  let unit ← match ← SourceProvider.readRootFile rootDir logicalPath
      request.sourceLimits with
    | .ok unit => pure unit
    | .error error =>
        return .error (rootFailure "TLA-FRONTEND-ROOT-READ" logicalPath
          s!"unable to read model source '{logicalPath}': {error.message}")
  let outcome := parseSource request.profile ParserProfile.default {} {} unit
  if outcome.hasErrors then
    return .error { diagnostics := outcome.diagnostics }
  let some parsed := outcome.module?
    | return .error (rootFailure "TLA-FRONTEND-ROOT-PARSE" logicalPath
        s!"model source '{logicalPath}' did not produce a module")
  return .ok (logicalPath, unit, parsed)

/-- Analyze one borrowed root file. The declared module name comes from the
frontend's own parse of the captured root bytes, so a caller that only has a
path never runs a second scanner. The captured root unit is reused for
resolution, so each analysis reads the root exactly once. -/
def analyzeFile (request : FrontendFileRequest) :
    IO (Except FrontendFailure FrontendResult) := do
  match ← captureRootFile request with
  | .error failure => return .error failure
  | .ok (logicalPath, unit, parsed) =>
      let rootPath : System.FilePath := request.specPath
      let rootDir := rootPath.parent.getD ("." : System.FilePath)
      let provider := SourceProvider.borrowedDirectory rootDir request.sourceLimits
        request.catalog
      let root : ModuleRef := { moduleName := parsed.name, logicalPath }
      let captured : SourceProvider :=
        { provider with readRoot := fun _ => pure (.ok unit) }
      analyze captured { root, profile := request.profile, limits := request.limits }

/-! ## Evidence admission -/

/-- Version-1 evidence-side budgets. They mirror the retired scanner's limits so
a source/evidence pair admitted before the frontend keeps the same shape. -/
structure EvidenceLimits where
  maxVariables : Nat := 4096
  maxIdentifierBytes : Nat := 256
  deriving Repr, BEq

/-- Why raw evidence variables were refused. `mismatch` carries the resolved
source-only declarations (with origins) and the evidence-only names, so a
caller can name declaration origins without inventing any. -/
inductive EvidenceAdmissionError where
  | duplicateEvidence (name : String)
  | evidenceLimit (message : String)
  | mismatch (sourceOnly : Array ResolvedVariable) (evidenceOnly : Array String)
  deriving Repr, BEq

private def sortedStrings (values : List String) : List String :=
  values.toArray.qsort (fun left right => compare left right == .lt) |>.toList

/-- Require raw evidence variables to equal the elaborated effective variables
as sets. The evidence side keeps its own duplicates and limits checks, so a
malformed or oversized evidence list fails here before any partition. -/
def admitEvidence (result : FrontendResult) (rawVariables : List String)
    (limits : EvidenceLimits := {}) : Except EvidenceAdmissionError Unit := do
  if rawVariables.length > limits.maxVariables then
    throw (.evidenceLimit
      s!"evidence variables exceed count limit {limits.maxVariables}")
  if rawVariables.any (fun name => name.toUTF8.size > limits.maxIdentifierBytes) then
    throw (.evidenceLimit
      s!"evidence variable name exceeds byte limit {limits.maxIdentifierBytes}")
  match rawVariables.find? (fun name =>
      (rawVariables.filter (· == name)).length > 1) with
  | some name => throw (.duplicateEvidence name)
  | none => pure ()
  let effective := result.elaborated.variables
  let sourceOnly := effective.filter fun entry =>
    !rawVariables.contains entry.visibleName
  let effectiveNames := effective.toList.map (fun entry => entry.visibleName)
  let evidenceOnly := rawVariables.filter fun name =>
    !effectiveNames.contains name
  if sourceOnly.isEmpty && evidenceOnly.isEmpty then return ()
  throw (.mismatch sourceOnly (sortedStrings evidenceOnly |> List.toArray))

end Shell.Tla
