import Shell.ModelInterface.Compiler
import Codec.ModelInterfaceJson

/-!
# `model_interface_gen` command line

The executable target is intentionally separate from the operational mirror.
`check` is strictly read-only; `resolve` owns one lock file and `generate`
owns only paths named by a strict generated-tree manifest.
-/

namespace ModelInterfaceGen

open Core.ModelInterface
open Shell.ModelInterface.Compiler

def usage : String := String.intercalate "\n" [
  "usage:",
  "  model_interface_gen resolve --spec FILE --contract FILE --evidence FILE",
  "    [--param-var NAME] --lock FILE [--diagnostics json]",
  "  model_interface_gen generate --lock FILE --target mirrorecma-v1|mirrorcpp-v1 --out DIR",
  "    [--diagnostics json]",
  "  model_interface_gen check --spec FILE --contract FILE --evidence FILE",
  "    [--param-var NAME] --lock FILE --target mirrorecma-v1|mirrorcpp-v1 --out DIR",
  "    [--diagnostics json]",
  "  model_interface_gen preflight --lock FILE --trace PATH",
  "    [--require-all-actions] [--diagnostics json]"
]

private inductive DiagnosticsMode where
  | human
  | json

private structure RawOptions where
  spec : Option String := none
  contract : Option String := none
  evidence : Option String := none
  paramVar : Option String := none
  paramVarSeen : Bool := false
  lock : Option String := none
  target : Option String := none
  out : Option String := none
  trace : Option String := none
  diagnostics : Option String := none

private inductive Command where
  | resolve (inputs : InputPaths) (lock : String)
  | generate (lock target out : String)
  | check (inputs : InputPaths) (lock target out : String)
  | preflight (lock trace : String) (requireAllActions : Bool)

private structure ParsedCommand where
  command : Command
  diagnostics : DiagnosticsMode

private def allowedFlags : List String :=
  ["--spec", "--contract", "--evidence", "--param-var", "--lock", "--target", "--out",
   "--trace", "--diagnostics"]

private def optionPairs : List String → Except String (List (String × String))
  | [] => .ok []
  | flag :: [] => .error s!"missing value for {flag}"
  | flag :: value :: rest => do
      if !allowedFlags.contains flag then throw s!"unknown option: {flag}"
      if value.isEmpty && flag != "--param-var" then throw s!"empty value for {flag}"
      return (flag, value) :: (← optionPairs rest)

private def parseOptions (arguments : List String) : Except String RawOptions := do
  let pairs ← optionPairs arguments
  let duplicateFlags := Core.ModelInterface.duplicateStrings (pairs.map Prod.fst)
  match duplicateFlags with
  | flag :: _ => throw s!"duplicate option: {flag}"
  | [] => pure ()
  let param := List.lookup "--param-var" pairs
  return {
    spec := List.lookup "--spec" pairs
    contract := List.lookup "--contract" pairs
    evidence := List.lookup "--evidence" pairs
    paramVar := param.bind fun value => if value.isEmpty then none else some value
    paramVarSeen := param.isSome
    lock := List.lookup "--lock" pairs
    target := List.lookup "--target" pairs
    out := List.lookup "--out" pairs
    trace := List.lookup "--trace" pairs
    diagnostics := List.lookup "--diagnostics" pairs
  }

private def requireOption (name : String) : Option String → Except String String
  | some value => .ok value
  | none => .error s!"missing required option: {name}"

private def rejectPresent (name : String) (value : Option String) : Except String Unit :=
  if value.isSome then .error s!"option {name} is not valid for this command" else .ok ()

private def inputsOf (options : RawOptions) : Except String InputPaths := do
  return {
    spec := ← requireOption "--spec" options.spec
    contract := ← requireOption "--contract" options.contract
    evidence := ← requireOption "--evidence" options.evidence
    paramVar := options.paramVar
  }

private def checkedTarget (options : RawOptions) : Except String String := do
  let target ← requireOption "--target" options.target
  if target != mirrorecmaTarget && target != mirrorcppTarget then
    throw s!"unsupported --target {target}; expected {mirrorecmaTarget} or {mirrorcppTarget}"
  return target

private def diagnosticsMode (options : RawOptions) : Except String DiagnosticsMode :=
  match options.diagnostics with
  | none => .ok .human
  | some "json" => .ok .json
  | some value => .error s!"unsupported --diagnostics {value}; expected json"

private def parseCommand (arguments : List String) : Except String ParsedCommand := do
  let (name, rest) ← match arguments with
    | name :: rest => pure (name, rest)
    | [] => throw "missing command"
  if rest.contains "--help" || rest.contains "-h" then throw usage
  let requireAllCount := rest.count "--require-all-actions"
  if requireAllCount > 1 then throw "duplicate option: --require-all-actions"
  let requireAllActions := requireAllCount == 1
  let optionArguments := rest.filter (· != "--require-all-actions")
  let options ← parseOptions optionArguments
  let diagnostics ← diagnosticsMode options
  let command : Command ← match name with
  | "resolve" =>
      if requireAllActions then throw "option --require-all-actions is not valid for resolve"
      let _ ← rejectPresent "--target" options.target
      let _ ← rejectPresent "--out" options.out
      let _ ← rejectPresent "--trace" options.trace
      pure <| Command.resolve (← inputsOf options) (← requireOption "--lock" options.lock)
  | "generate" =>
      if requireAllActions then throw "option --require-all-actions is not valid for generate"
      let _ ← rejectPresent "--spec" options.spec
      let _ ← rejectPresent "--contract" options.contract
      let _ ← rejectPresent "--evidence" options.evidence
      let _ ← rejectPresent "--trace" options.trace
      if options.paramVarSeen then throw "option --param-var is not valid for generate"
      pure <| Command.generate (← requireOption "--lock" options.lock)
        (← checkedTarget options) (← requireOption "--out" options.out)
  | "check" =>
      if requireAllActions then throw "option --require-all-actions is not valid for check"
      let _ ← rejectPresent "--trace" options.trace
      pure <| Command.check (← inputsOf options) (← requireOption "--lock" options.lock)
        (← checkedTarget options) (← requireOption "--out" options.out)
  | "preflight" =>
      let _ ← rejectPresent "--spec" options.spec
      let _ ← rejectPresent "--contract" options.contract
      let _ ← rejectPresent "--evidence" options.evidence
      let _ ← rejectPresent "--target" options.target
      let _ ← rejectPresent "--out" options.out
      if options.paramVarSeen then throw "option --param-var is not valid for preflight"
      pure <| Command.preflight (← requireOption "--lock" options.lock)
        (← requireOption "--trace" options.trace) requireAllActions
  | "--help" | "-h" => throw usage
  | other => throw s!"unknown command: {other}"
  return { command, diagnostics }

private def severityText : Severity → String
  | .error => "error"
  | .warning => "warning"
  | .obligation => "obligation"

private def renderDiagnostic (diagnostic : Diagnostic) : String :=
  let pointer := diagnostic.primary.pointer.map (" " ++ ·) |>.getD ""
  let subject := diagnostic.subject.stableId.map (" " ++ ·) |>.getD ""
  let arguments := normalizeDiagnosticArguments diagnostic.arguments |>.map (fun argument =>
    argument.1 ++ "=" ++ argument.2)
  let suffix := if arguments.isEmpty then "" else " " ++ String.intercalate " " arguments
  s!"{severityText diagnostic.severity} {diagnostic.code} " ++
    s!"{diagnostic.primary.source}{pointer} {diagnostic.subject.kind}{subject}{suffix}"

private def printDiagnostics (diagnostics : List Diagnostic) : IO Unit := do
  for diagnostic in diagnostics do
    IO.eprintln (renderDiagnostic diagnostic)

private def printJsonDiagnostics (diagnostics : List Diagnostic) : IO Unit :=
  IO.eprintln <| Codec.ModelInterfaceJson.canonicalString
    (Codec.ModelInterfaceJson.encodeDiagnostics diagnostics)

private def shellDiagnostic (code subject reason : String) : Diagnostic := {
  code := code
  severity := .error
  stage := "cli"
  subject := { kind := subject }
  primary := { source := "<compiler>" }
  arguments := [("reason", reason)]
}

private def compilerErrorDiagnostic (error : CompilerError) : Diagnostic :=
  if error.kind == .infrastructure then
    shellDiagnostic "MIC-C-INFRASTRUCTURE-001" "infrastructure"
      "compiler infrastructure failure"
  else if error.message.contains "contract" then
    shellDiagnostic "MIC-C-CONTRACT-001" "contract" "invalid compiler contract"
  else if error.message.contains "evidence" || error.message.contains "trace" then
    shellDiagnostic "MIC-C-EVIDENCE-001" "evidence" "invalid compiler evidence"
  else if error.message.contains "lock" then
    shellDiagnostic "MIC-C-LOCK-001" "lock" "invalid compiler lock"
  else if error.message.contains "target" || error.message.contains "generated" ||
      error.message.contains "output" then
    shellDiagnostic "MIC-C-OUTPUT-001" "generatedOutput"
      "invalid generated output"
  else
    shellDiagnostic "MIC-C-FINDING-001" "compiler" "compiler finding"

private def reportError (mode : DiagnosticsMode) (error : CompilerError)
    (priorDiagnostics : List Diagnostic := []) : IO UInt32 := do
  match mode with
  | .human =>
      printDiagnostics priorDiagnostics
      IO.eprintln error.message
      printDiagnostics error.diagnostics
  | .json =>
      let diagnostics := priorDiagnostics ++ error.diagnostics
      printJsonDiagnostics (diagnostics ++ [compilerErrorDiagnostic error])
  return match error.kind with
    | .finding => 1
    | .infrastructure => 2

private def runResolve (mode : DiagnosticsMode)
    (inputs : InputPaths) (lockPath : String) : IO UInt32 := do
  match ← compile inputs with
  | .error error => reportError mode error
  | .ok compilation =>
      match ← writeLock lockPath compilation with
      | .error error => reportError mode error compilation.diagnostics
      | .ok () =>
          match mode with
          | .human =>
              printDiagnostics compilation.diagnostics
          | .json => printJsonDiagnostics compilation.diagnostics
          IO.println s!"resolved {lockPath} {compilation.lock.semanticDigest}"
          return 0

private def runGenerate (mode : DiagnosticsMode)
    (lock target out : String) : IO UInt32 := do
  match ← generate lock target out with
  | .error error => reportError mode error
  | .ok paths =>
      match mode with
      | .human => pure ()
      | .json => printJsonDiagnostics []
      IO.println s!"generated {paths.length} files in {out}"
      return 0

private def runCheck (mode : DiagnosticsMode)
    (inputs : InputPaths) (lock target out : String) : IO UInt32 := do
  match ← check inputs lock target out with
  | .error error => reportError mode error
  | .ok report =>
      match mode with
      | .human =>
          printDiagnostics report.diagnostics
          if report.clean then
            IO.println "model-interface check clean"
          else
            for path in report.stalePaths do
              IO.eprintln s!"stale: {path}"
      | .json =>
          let diagnostics := if !report.clean && report.diagnostics.isEmpty then
              [shellDiagnostic "MIC-C-STALE-001" "generatedOutput"
                "generated output is stale"]
            else report.diagnostics
          printJsonDiagnostics diagnostics
          if report.clean then
            IO.println "model-interface check clean"
          else
            for path in report.stalePaths do
              IO.println s!"stale: {path}"
      return if report.clean then 0 else 1

private def runPreflightCommand (mode : DiagnosticsMode) (lock trace : String)
    (requireAllActions : Bool) : IO UInt32 := do
  match ← Shell.ModelInterface.Compiler.runPreflight lock trace requireAllActions with
  | .error error => reportError mode error
  | .ok execution =>
      match mode with
      | .human =>
          IO.println execution.coverageJson
          printDiagnostics execution.result.diagnostics
      | .json =>
          IO.println execution.coverageJson
          printJsonDiagnostics execution.result.diagnostics
      return if execution.result.hasErrors then 1 else 0

def run (arguments : List String) : IO UInt32 := do
  match parseCommand arguments with
  | .error message =>
      IO.eprintln message
      if message != usage then IO.eprintln usage
      return 2
  | .ok parsed =>
      match parsed.command with
      | .resolve inputs lock => runResolve parsed.diagnostics inputs lock
      | .generate lock target out => runGenerate parsed.diagnostics lock target out
      | .check inputs lock target out => runCheck parsed.diagnostics inputs lock target out
      | .preflight lock trace requireAllActions =>
          runPreflightCommand parsed.diagnostics lock trace requireAllActions

end ModelInterfaceGen

def main (arguments : List String) : IO UInt32 := do
  try
    ModelInterfaceGen.run arguments
  catch error =>
    IO.eprintln s!"model_interface_gen: {error}"
    return 2
