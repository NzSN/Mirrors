import Codec.TlaFrontendJson
import Shell.Tla.Frontend

/-!
# `tla_frontend` development CLI (`tools/TlaFrontendCli.lean`)

Development-only inspection tool for the general TLA+ frontend
(`Docs/model-interface-compiler/tla-frontend-design.md`, §24 "Inspection
tool"). The operational `mirror` executable gains no development command.

`parse` reports the root file's syntax facts only; `resolve` performs full
graph resolution and elaboration; `inspect` projects approved facts from the
same captured analysis the model-interface compiler consumes. Default output
carries logical module identities only, never a physical path.

Exit codes follow `model_interface_gen`: `0` success, `1` analysis failure with
reported diagnostics, `2` malformed arguments.
-/

namespace TlaFrontendCli

open Core.Tla
open Lean
open Shell.Tla

/-- The exact usage text; `tla_frontend help` prints it unchanged. -/
def usage : String := String.intercalate "\n" [
  "usage:",
  "  tla_frontend parse --spec FILE [--format json]",
  "  tla_frontend resolve --spec FILE [--format json]",
  "  tla_frontend inspect --spec FILE [--variables] [--dependencies]",
  "    [--operators] [--levels] [--format json]",
  "  tla_frontend help",
  "",
  "  parse    reports the root file's syntax facts only",
  "  resolve  performs full graph resolution and elaboration",
  "  inspect  projects approved facts from the same analysis",
  "",
  "`inspect` without a section flag prints every section. Default output",
  "contains logical module identities only, never a physical path. JSON",
  "documents use the closed schema " ++ Codec.TlaFrontendJson.schema ++ "."
]

private inductive Format where
  | human
  | json
  deriving BEq

private structure Options where
  spec : Option String := none
  format : Format := .human
  sectionFlags : Array String := #[]

private def sectionFlagNames : List String :=
  ["--variables", "--dependencies", "--operators", "--levels"]

private def allowedFlags : List String :=
  "--spec" :: "--format" :: sectionFlagNames

private def parseOptions (arguments : List String) : Except String Options :=
  go arguments {} []
where
  go (remaining : List String) (options : Options) (seen : List String) :
      Except String Options :=
    match remaining with
    | [] => pure options
    | flag :: rest =>
        if !allowedFlags.contains flag then
          throw s!"unknown option: {flag}"
        else if seen.contains flag then
          throw s!"duplicate option: {flag}"
        else if sectionFlagNames.contains flag then
          go rest { options with sectionFlags := options.sectionFlags.push flag }
            (flag :: seen)
        else
          match rest with
          | [] => throw s!"missing value for {flag}"
          | value :: tail =>
              if value.isEmpty then
                throw s!"empty value for {flag}"
              else if flag == "--format" then
                if value != "json" then
                  throw s!"unsupported --format {value}; expected json"
                else
                  go tail { options with format := .json } (flag :: seen)
              else
                go tail { options with spec := some value } (flag :: seen)

private inductive Command where
  | help
  | parse (spec : String)
  | resolve (spec : String)
  | inspect (spec : String) (sections : Codec.TlaFrontendJson.Sections)

private structure Parsed where
  command : Command
  format : Format

/-- Admit only a bare `*.tla` file name, so every rendered identity is a
logical path and a physical path can never reach default output. -/
private def checkedSpec (spec : String) : Except String String :=
  match (spec : System.FilePath).fileName with
  | some name =>
      if name.endsWith ".tla" then pure spec
      else throw "spec path must name a .tla file"
  | none => throw "spec path must name a .tla file"

private def parseCommand (arguments : List String) : Except String Parsed := do
  let (name, rest) ← match arguments with
    | name :: rest => pure (name, rest)
    | [] => throw "missing command"
  if name == "help" || name == "--help" || name == "-h" then
    if !rest.isEmpty then throw "help takes no arguments"
    return { command := .help, format := .human }
  if name != "parse" && name != "resolve" && name != "inspect" then
    throw s!"unknown command: {name}"
  let options ← parseOptions rest
  let spec ← match options.spec with
    | some value => checkedSpec value
    | none => throw "missing required option: --spec"
  match name with
  | "parse" =>
      match options.sectionFlags.toList with
      | flag :: _ => throw s!"option {flag} is not valid for parse"
      | [] => pure { command := .parse spec, format := options.format }
  | "resolve" =>
      match options.sectionFlags.toList with
      | flag :: _ => throw s!"option {flag} is not valid for resolve"
      | [] => pure { command := .resolve spec, format := options.format }
  | "inspect" =>
      let sections :=
        if options.sectionFlags.isEmpty then {}
        else
          { variables := options.sectionFlags.contains "--variables"
            dependencies := options.sectionFlags.contains "--dependencies"
            operators := options.sectionFlags.contains "--operators"
            levels := options.sectionFlags.contains "--levels" }
      pure { command := .inspect spec sections, format := options.format }
  | other => throw s!"unknown command: {other}"

/-! ## Rendering -/

private def renderLocation (location : SourceLocation) : String :=
  s!"{location.logicalPath}:{location.range.start.line}:{location.range.start.column}"

private def renderDiagnostic (diagnostic : Diagnostic) : String :=
  s!"{renderLocation diagnostic.primary}: {diagnostic.severity.toString} [{diagnostic.code}] {diagnostic.message}"

private def renderParse (logicalPath : String) (parsed : ParsedModule) : String :=
  String.intercalate "\n" [
    s!"module: {parsed.name.name}",
    s!"path: {logicalPath}",
    s!"declarations: {parsed.declarations.size}",
    s!"dependencies: {parsed.dependencies.size}",
    "diagnostics: 0"
  ]

private def renderResolve (logicalPath : String) (graph : ResolvedModuleGraph)
    (elaborated : ElaboratedModule) : String :=
  String.intercalate "\n" [
    s!"module: {elaborated.moduleName.name}",
    s!"path: {logicalPath}",
    s!"sources: {elaborated.sourceManifest.size}",
    s!"dependencies: {graph.canonicalEdges.size}",
    s!"variables: {elaborated.variables.size}",
    s!"operators: {elaborated.operators.size}",
    "diagnostics: 0"
  ]

private def renderInspect (logicalPath : String)
    (sections : Codec.TlaFrontendJson.Sections) (graph : ResolvedModuleGraph)
    (elaborated : ElaboratedModule) : String :=
  let header := [s!"module: {elaborated.moduleName.name}", s!"path: {logicalPath}"]
  let variableLines :=
    if sections.variables then
      ["variables:"] ++ elaborated.variables.toList.map (fun entry =>
        s!"  {entry.visibleName} declared in {entry.declaredIn.name}")
    else []
  let dependencyLines :=
    if sections.dependencies then
      ["dependencies:"] ++ graph.canonicalEdges.toList.map (fun edge =>
        s!"  {edge.owner.name} -> {edge.dependency.name} ({edge.kind.toString}, {edge.resolution.toString})")
    else []
  let operatorLines :=
    if sections.operators then
      ["operators:"] ++ elaborated.operators.toList.map (fun operator =>
        s!"  {operator.name}/{operator.arity} ({Codec.TlaFrontendJson.fixityString operator.fixity}, {operator.level.toString}) declared in {operator.declaredIn.name}")
    else []
  let levelLines :=
    if sections.levels then
      ["levels:"] ++
        elaborated.constants.toList.map (fun entry =>
          s!"  constant {entry.name} constant declared in {entry.declaredIn.name}") ++
        elaborated.variables.toList.map (fun entry =>
          s!"  variable {entry.visibleName} state declared in {entry.declaredIn.name}") ++
        elaborated.operators.toList.map (fun entry =>
          s!"  operator {entry.name} {entry.level.toString} declared in {entry.declaredIn.name}") ++
        elaborated.assumptions.toList.map (fun entry =>
          s!"  assumption {entry.level.toString} declared in {entry.declaredIn.name}")
    else []
  String.intercalate "\n"
    (header ++ variableLines ++ dependencyLines ++ operatorLines ++ levelLines)

/-! ## Commands -/

private def failWith (format : Format) (document : Json)
    (failure : FrontendFailure) : IO UInt32 := do
  match format with
  | .human =>
      for diagnostic in failure.diagnostics do
        IO.println (renderDiagnostic diagnostic)
  | .json => IO.println (Json.compress document)
  return 1

private def emit (format : Format) (document : Json) (human : String) : IO UInt32 := do
  match format with
  | .human => IO.println human
  | .json => IO.println (Json.compress document)
  return 0

private def runParse (format : Format) (spec : String) : IO UInt32 := do
  let logicalPath := ((spec : System.FilePath).fileName).getD ""
  match ← captureRootFile { specPath := spec } with
  | .error failure =>
      failWith format
        (Codec.TlaFrontendJson.parseDocument logicalPath none failure.diagnostics)
        failure
  | .ok (path, _, parsed) =>
      emit format (Codec.TlaFrontendJson.parseDocument path (some parsed) #[])
        (renderParse path parsed)

private def runResolve (format : Format) (spec : String) : IO UInt32 := do
  let logicalPath := ((spec : System.FilePath).fileName).getD ""
  match ← analyzeFile { specPath := spec } with
  | .error failure =>
      failWith format
        (Codec.TlaFrontendJson.resolveDocument logicalPath none failure.diagnostics)
        failure
  | .ok result =>
      emit format
        (Codec.TlaFrontendJson.resolveDocument logicalPath
          (some (result.graph, result.elaborated)) #[])
        (renderResolve logicalPath result.graph result.elaborated)

private def runInspect (format : Format) (spec : String)
    (sections : Codec.TlaFrontendJson.Sections) : IO UInt32 := do
  let logicalPath := ((spec : System.FilePath).fileName).getD ""
  match ← analyzeFile { specPath := spec } with
  | .error failure =>
      failWith format
        (Codec.TlaFrontendJson.inspectDocument logicalPath sections none
          failure.diagnostics)
        failure
  | .ok result =>
      emit format
        (Codec.TlaFrontendJson.inspectDocument logicalPath sections
          (some (result.graph, result.elaborated)) #[])
        (renderInspect logicalPath sections result.graph result.elaborated)

def run (arguments : List String) : IO UInt32 := do
  match parseCommand arguments with
  | .error message =>
      IO.eprintln message
      IO.eprintln usage
      return 2
  | .ok parsed =>
      match parsed.command with
      | .help =>
          IO.println usage
          return 0
      | .parse spec => runParse parsed.format spec
      | .resolve spec => runResolve parsed.format spec
      | .inspect spec sections => runInspect parsed.format spec sections

end TlaFrontendCli

def main (arguments : List String) : IO UInt32 := do
  try
    TlaFrontendCli.run arguments
  catch error =>
    IO.eprintln s!"tla_frontend: {error}"
    return 2
