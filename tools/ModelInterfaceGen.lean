import Shell.ModelInterface.Compiler
import Codec.ModelInterfaceJson
import Shell.ModelInterface.ScaffoldWorkflow
import Shell.ModelInterface.Corpus
import Shell.ModelInterface.Migration
import Shell.ModelInterface.ScheduleKit

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
  "  model_interface_gen generate --lock FILE --target TARGET --out DIR",
  "    [--diagnostics json]",
  "  model_interface_gen bundle --lock FILE --target mirrorecma-async-v1 --out DIR",
  "    [--diagnostics json]",
  "  model_interface_gen check-bundle --spec FILE --contract FILE --evidence FILE",
  "    [--param-var NAME] --lock FILE --target mirrorecma-async-v1 --out DIR",
  "    [--diagnostics json]",
  "  model_interface_gen check --spec FILE --contract FILE --evidence FILE",
  "    [--param-var NAME] --lock FILE --target TARGET --out DIR",
  "    [--diagnostics json]",
  "  model_interface_gen generate-dpm|check-dpm --lock FILE --mapping FILE --target TARGET --out DIR",
  "    [--diagnostics json]",
  "  model_interface_gen compare-locks --from-lock OLD --to-lock NEW",
  "    [--diagnostics json]",
  "  model_interface_gen preflight --lock FILE --trace PATH",
  "    [--require-all-actions] [--diagnostics json]",
  "  model_interface_gen scaffold --spec FILE --evidence FILE",
  "    [--param-var NAME] [--projection PLAN] --proposal FILE",
  "    [--replace] [--diagnostics json]",
  "  model_interface_gen scaffold --reviewable --spec FILE --evidence FILE",
  "    [--evidence FILE ...] [--param-var NAME] [--projection PLAN] --proposal FILE",
  "  model_interface_gen seal-scaffold --spec FILE --evidence FILE [--evidence FILE ...]",
  "    [--param-var NAME] [--projection PLAN] --proposal FILE --review FILE --out DIR",
  "  model_interface_gen resolve-sealed --spec FILE --evidence FILE [--evidence FILE ...]",
  "    [--param-var NAME] [--projection PLAN] --sealed DIR [--corpus-manifest FILE] --lock FILE",
  "  model_interface_gen check-sealed|check-sealed-bundle --spec FILE --evidence FILE",
  "    [--evidence FILE ...] [--param-var NAME] [--projection PLAN] --sealed DIR",
  "    [--corpus-manifest FILE] --lock FILE --target TARGET --out DIR",
  "  model_interface_gen project-corpus --spec FILE --evidence RAW [--evidence RAW ...]",
  "    --projection PLAN --out DIR [--diagnostics json]",
  "  model_interface_gen check-corpus --out DIR --manifest-sha256 HASH [--diagnostics json]",
  "  model_interface_gen project-trace --spec FILE --evidence RAW",
  "    --projection PLAN --out PROJECTED --receipt RECEIPT",
  "    [--replace] [--diagnostics json]",
  "  model_interface_gen generate-cmake|check-cmake --spec FILE --contract FILE",
  "    --evidence FILE [--param-var NAME] --lock FILE --target CPP_TARGET --out DIR",
  "    (paths relative to the consumer root; optional CMake helpers)",
  "  TARGET: mirrorecma-v1 | mirrorecma-async-v1 | mirrorecma-async-v2 | mirrorcpp-v1 | mirrorcpp-v2 | mirrorrust-v1 | mirrorrust-v2 | mirrorlean-v1"
]

private inductive DiagnosticsMode where
  | human
  | json

private structure RawOptions where
  mapping : Option String := none
  fromLock : Option String := none
  toLock : Option String := none
  spec : Option String := none
  contract : Option String := none
  evidence : Option String := none
  evidences : List String := []
  paramVar : Option String := none
  paramVarSeen : Bool := false
  lock : Option String := none
  target : Option String := none
  out : Option String := none
  trace : Option String := none
  proposal : Option String := none
  projection : Option String := none
  receipt : Option String := none
  review : Option String := none
  sealed : Option String := none
  corpusManifest : Option String := none
  manifestSha256 : Option String := none
  diagnostics : Option String := none

private inductive Command where
  | scheduleKit (lock mapping target out : String) (check : Bool)
  | compareLocks (fromLock toLock : String)
  | resolve (inputs : InputPaths) (lock : String)
  | generate (lock target out : String) (bundle : Bool)
  | check (inputs : InputPaths) (lock target out : String) (bundle : Bool)
  | generateCmake (inputs : InputPaths) (lock target out : String)
  | checkCmake (inputs : InputPaths) (lock target out : String)
  | preflight (lock trace : String) (requireAllActions : Bool)
  | scaffold (inputs : ScaffoldPaths)
  | projectTrace (inputs : ProjectTracePaths)
  | scaffoldWorkflow (inputs : Shell.ModelInterface.ScaffoldWorkflow.WorkflowPaths)
      (proposal : String) (replace : Bool)
  | sealScaffold (inputs : Shell.ModelInterface.ScaffoldWorkflow.WorkflowPaths)
      (proposal review out : String)
  | resolveSealed (inputs : Shell.ModelInterface.ScaffoldWorkflow.WorkflowPaths)
      (sealed : String) (corpusManifest : Option String) (lock : String)
  | checkSealed (inputs : Shell.ModelInterface.ScaffoldWorkflow.WorkflowPaths)
      (sealed : String) (corpusManifest : Option String) (lock target out : String) (bundle : Bool)
  | projectCorpus (inputs : Shell.ModelInterface.Corpus.ProjectCorpusPaths)
  | checkCorpus (out manifestSha256 : String)

private structure ParsedCommand where
  command : Command
  diagnostics : DiagnosticsMode

private def allowedFlags : List String :=
  ["--mapping", "--from-lock", "--to-lock", "--spec", "--contract", "--evidence", "--param-var", "--lock", "--target", "--out",
   "--trace", "--proposal", "--projection", "--receipt", "--diagnostics",
   "--review", "--sealed", "--corpus-manifest", "--manifest-sha256"]

private def optionPairs : List String → Except String (List (String × String))
  | [] => .ok []
  | flag :: [] => .error s!"missing value for {flag}"
  | flag :: value :: rest => do
      if !allowedFlags.contains flag then throw s!"unknown option: {flag}"
      if value.isEmpty && flag != "--param-var" then throw s!"empty value for {flag}"
      return (flag, value) :: (← optionPairs rest)

private def parseOptions (arguments : List String) : Except String RawOptions := do
  let pairs ← optionPairs arguments
  let duplicateFlags := Core.ModelInterface.duplicateStrings
    (pairs.map Prod.fst |>.filter (· != "--evidence"))
  match duplicateFlags with
  | flag :: _ => throw s!"duplicate option: {flag}"
  | [] => pure ()
  let param := List.lookup "--param-var" pairs
  return {
    mapping := List.lookup "--mapping" pairs
    fromLock := List.lookup "--from-lock" pairs
    toLock := List.lookup "--to-lock" pairs
    spec := List.lookup "--spec" pairs
    contract := List.lookup "--contract" pairs
    evidence := List.lookup "--evidence" pairs
    evidences := pairs.filterMap fun (flag, value) => if flag == "--evidence" then some value else none
    paramVar := param.bind fun value => if value.isEmpty then none else some value
    paramVarSeen := param.isSome
    lock := List.lookup "--lock" pairs
    target := List.lookup "--target" pairs
    out := List.lookup "--out" pairs
    trace := List.lookup "--trace" pairs
    proposal := List.lookup "--proposal" pairs
    projection := List.lookup "--projection" pairs
    receipt := List.lookup "--receipt" pairs
    review := List.lookup "--review" pairs
    sealed := List.lookup "--sealed" pairs
    corpusManifest := List.lookup "--corpus-manifest" pairs
    manifestSha256 := List.lookup "--manifest-sha256" pairs
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

private def workflowInputsOf (options : RawOptions) :
    Except String Shell.ModelInterface.ScaffoldWorkflow.WorkflowPaths := do
  if options.evidences.isEmpty then throw "missing required option: --evidence"
  return {
    spec := ← requireOption "--spec" options.spec
    evidence := options.evidences
    paramVar := options.paramVar
    projection := options.projection
  }

private def checkedTarget (options : RawOptions) : Except String String := do
  let target ← requireOption "--target" options.target
  if !supportedTarget target then
    throw s!"unsupported --target {target}; see the supported TARGET list"
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
  let replaceCount := rest.count "--replace"
  if replaceCount > 1 then throw "duplicate option: --replace"
  let replace := replaceCount == 1
  let reviewableCount := rest.count "--reviewable"
  if reviewableCount > 1 then throw "duplicate option: --reviewable"
  let reviewable := reviewableCount == 1
  if reviewable && name != "scaffold" then
    throw "option --reviewable is only valid for scaffold"
  let optionArguments := rest.filter fun argument =>
    argument != "--require-all-actions" && argument != "--replace" && argument != "--reviewable"
  let options ← parseOptions optionArguments
  let diagnostics ← diagnosticsMode options
  if name == "generate-dpm" || name == "check-dpm" then
    if requireAllActions || replace || reviewable then throw "unsupported flag for DPM kit"
    for (flag, _) in (← optionPairs optionArguments) do
      unless ["--lock", "--mapping", "--target", "--out", "--diagnostics"].contains flag do
        throw s!"option {flag} is not valid for DPM kit"
    return {
      command := .scheduleKit (← requireOption "--lock" options.lock)
        (← requireOption "--mapping" options.mapping) (← checkedTarget options)
        (← requireOption "--out" options.out) (name == "check-dpm")
      diagnostics }
  let _ ← rejectPresent "--mapping" options.mapping
  if name == "compare-locks" then
    if requireAllActions || replace || reviewable then
      throw "unsupported flag for compare-locks"
    for (flag, _) in (← optionPairs optionArguments) do
      unless ["--from-lock", "--to-lock", "--diagnostics"].contains flag do
        throw s!"option {flag} is not valid for compare-locks"
    return {
      command := .compareLocks (← requireOption "--from-lock" options.fromLock)
        (← requireOption "--to-lock" options.toLock)
      diagnostics }
  let _ ← rejectPresent "--from-lock" options.fromLock
  let _ ← rejectPresent "--to-lock" options.toLock
  let workflowCommands := ["seal-scaffold", "resolve-sealed", "check-sealed", "check-sealed-bundle",
    "project-corpus", "check-corpus"]
  if !workflowCommands.contains name then
    for (flag, value) in [("--review", options.review), ("--sealed", options.sealed),
        ("--corpus-manifest", options.corpusManifest), ("--manifest-sha256", options.manifestSha256)] do
      let _ ← rejectPresent flag value
    if name != "scaffold" && options.evidences.length > 1 then
      throw "duplicate option: --evidence"
  else
    if requireAllActions || replace then throw "unsupported flag for workflow command"
    let commandFlags := match name with
      | "seal-scaffold" => ["--spec", "--evidence", "--param-var", "--projection", "--proposal", "--review", "--out"]
      | "resolve-sealed" => ["--spec", "--evidence", "--param-var", "--projection", "--sealed", "--corpus-manifest", "--lock"]
      | "check-sealed" | "check-sealed-bundle" =>
          ["--spec", "--evidence", "--param-var", "--projection", "--sealed", "--corpus-manifest", "--lock", "--target", "--out"]
      | "project-corpus" => ["--spec", "--evidence", "--projection", "--out"]
      | _ => ["--out", "--manifest-sha256"]
    for (flag, _) in ← optionPairs optionArguments do
      if flag != "--diagnostics" && !commandFlags.contains flag then
        throw s!"option {flag} is not valid for {name}"
  let command : Command ← match name with
  | "seal-scaffold" =>
      pure <| Command.sealScaffold (← workflowInputsOf options)
        (← requireOption "--proposal" options.proposal) (← requireOption "--review" options.review)
        (← requireOption "--out" options.out)
  | "resolve-sealed" =>
      pure <| Command.resolveSealed (← workflowInputsOf options)
        (← requireOption "--sealed" options.sealed) options.corpusManifest
        (← requireOption "--lock" options.lock)
  | "check-sealed" | "check-sealed-bundle" =>
      pure <| Command.checkSealed (← workflowInputsOf options)
        (← requireOption "--sealed" options.sealed) options.corpusManifest
        (← requireOption "--lock" options.lock) (← checkedTarget options)
        (← requireOption "--out" options.out) (name == "check-sealed-bundle")
  | "project-corpus" =>
      if options.evidences.isEmpty then throw "missing required option: --evidence"
      pure <| Command.projectCorpus {
        spec := ← requireOption "--spec" options.spec
        evidence := options.evidences
        projection := ← requireOption "--projection" options.projection
        out := ← requireOption "--out" options.out
      }
  | "check-corpus" =>
      pure <| Command.checkCorpus (← requireOption "--out" options.out)
        (← requireOption "--manifest-sha256" options.manifestSha256)
  | "resolve" =>
      if requireAllActions then throw "option --require-all-actions is not valid for resolve"
      if replace then throw "option --replace is not valid for resolve"
      let _ ← rejectPresent "--target" options.target
      let _ ← rejectPresent "--out" options.out
      let _ ← rejectPresent "--trace" options.trace
      let _ ← rejectPresent "--proposal" options.proposal
      let _ ← rejectPresent "--projection" options.projection
      let _ ← rejectPresent "--receipt" options.receipt
      pure <| Command.resolve (← inputsOf options) (← requireOption "--lock" options.lock)
  | "generate" | "bundle" =>
      if requireAllActions then throw "option --require-all-actions is not valid for generate"
      if replace then throw "option --replace is not valid for generate"
      let _ ← rejectPresent "--spec" options.spec
      let _ ← rejectPresent "--contract" options.contract
      let _ ← rejectPresent "--evidence" options.evidence
      let _ ← rejectPresent "--trace" options.trace
      let _ ← rejectPresent "--proposal" options.proposal
      let _ ← rejectPresent "--projection" options.projection
      let _ ← rejectPresent "--receipt" options.receipt
      if options.paramVarSeen then throw "option --param-var is not valid for generate"
      pure <| Command.generate (← requireOption "--lock" options.lock)
        (← checkedTarget options) (← requireOption "--out" options.out) (name == "bundle")
  | "check" | "check-bundle" =>
      if requireAllActions then throw "option --require-all-actions is not valid for check"
      if replace then throw "option --replace is not valid for check"
      let _ ← rejectPresent "--trace" options.trace
      let _ ← rejectPresent "--proposal" options.proposal
      let _ ← rejectPresent "--projection" options.projection
      let _ ← rejectPresent "--receipt" options.receipt
      pure <| Command.check (← inputsOf options) (← requireOption "--lock" options.lock)
        (← checkedTarget options) (← requireOption "--out" options.out) (name == "check-bundle")
  | "generate-cmake" | "check-cmake" =>
      if requireAllActions || replace then throw "unsupported flag for CMake integration"
      for (flag, value) in [("--trace", options.trace), ("--proposal", options.proposal),
          ("--projection", options.projection), ("--receipt", options.receipt)] do
        let _ ← rejectPresent flag value
      let inputs ← inputsOf options
      let lock ← requireOption "--lock" options.lock
      let target ← checkedTarget options
      let out ← requireOption "--out" options.out
      if name == "generate-cmake" then pure (Command.generateCmake inputs lock target out)
      else pure (Command.checkCmake inputs lock target out)
  | "preflight" =>
      if replace then throw "option --replace is not valid for preflight"
      let _ ← rejectPresent "--spec" options.spec
      let _ ← rejectPresent "--contract" options.contract
      let _ ← rejectPresent "--evidence" options.evidence
      let _ ← rejectPresent "--target" options.target
      let _ ← rejectPresent "--out" options.out
      let _ ← rejectPresent "--proposal" options.proposal
      let _ ← rejectPresent "--projection" options.projection
      let _ ← rejectPresent "--receipt" options.receipt
      if options.paramVarSeen then throw "option --param-var is not valid for preflight"
      pure <| Command.preflight (← requireOption "--lock" options.lock)
        (← requireOption "--trace" options.trace) requireAllActions
  | "scaffold" =>
      if requireAllActions then throw "option --require-all-actions is not valid for scaffold"
      let _ ← rejectPresent "--contract" options.contract
      let _ ← rejectPresent "--lock" options.lock
      let _ ← rejectPresent "--target" options.target
      let _ ← rejectPresent "--out" options.out
      let _ ← rejectPresent "--trace" options.trace
      let _ ← rejectPresent "--receipt" options.receipt
      if reviewable || options.evidences.length > 1 then
        pure <| Command.scaffoldWorkflow (← workflowInputsOf options)
          (← requireOption "--proposal" options.proposal) replace
      else
        pure <| Command.scaffold {
          spec := ← requireOption "--spec" options.spec
          evidence := ← requireOption "--evidence" options.evidence
          paramVar := options.paramVar
          projection := options.projection
          proposal := ← requireOption "--proposal" options.proposal
          replace := replace
        }
  | "project-trace" =>
      if requireAllActions then throw "option --require-all-actions is not valid for project-trace"
      let _ ← rejectPresent "--contract" options.contract
      let _ ← rejectPresent "--lock" options.lock
      let _ ← rejectPresent "--target" options.target
      let _ ← rejectPresent "--trace" options.trace
      let _ ← rejectPresent "--proposal" options.proposal
      if options.paramVarSeen then throw "option --param-var is not valid for project-trace"
      pure <| Command.projectTrace {
        spec := ← requireOption "--spec" options.spec
        evidence := ← requireOption "--evidence" options.evidence
        projection := ← requireOption "--projection" options.projection
        out := ← requireOption "--out" options.out
        receipt := ← requireOption "--receipt" options.receipt
        replace := replace
      }
  | "--help" | "-h" => throw usage
  | other => throw s!"unknown command: {other}"
  return { command, diagnostics }

private def severityText : Severity → String
  | .error => "error"
  | .warning => "warning"
  | .obligation => "obligation"

/-- Quote diagnostic data when literal rendering would change line structure
or make quotes/backslashes ambiguous. Ordinary identifier rendering is stable. -/
private def diagnosticText (value : String) : String :=
  if value.toList.any (fun character =>
      character.toNat < 32 || character == '"' || character == '\\') then
    Codec.ModelInterfaceJson.canonicalString (.str value)
  else value

private def renderDiagnostic (diagnostic : Diagnostic) : String :=
  let pointer := diagnostic.primary.pointer.map (fun value => " " ++ diagnosticText value) |>.getD ""
  let subject := diagnostic.subject.stableId.map (fun value => " " ++ diagnosticText value) |>.getD ""
  let arguments := normalizeDiagnosticArguments diagnostic.arguments |>.map (fun argument =>
    diagnosticText argument.1 ++ "=" ++ diagnosticText argument.2)
  let suffix := if arguments.isEmpty then "" else " " ++ String.intercalate " " arguments
  s!"{severityText diagnostic.severity} {diagnostic.code} " ++
    s!"{diagnosticText diagnostic.primary.source}{pointer} {diagnostic.subject.kind}{subject}{suffix}"

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
      IO.eprintln (diagnosticText error.message)
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
    (lock target out : String) (bundle : Bool) : IO UInt32 := do
  match ← generate lock target out bundle with
  | .error error => reportError mode error
  | .ok paths =>
      match mode with
      | .human => pure ()
      | .json => printJsonDiagnostics []
      IO.println s!"generated {paths.length} files in {out}"
      return 0

private def runCheck (mode : DiagnosticsMode)
    (inputs : InputPaths) (lock target out : String) (bundle : Bool) : IO UInt32 := do
  match ← check inputs lock target out bundle with
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

private def runScaffold (mode : DiagnosticsMode) (inputs : ScaffoldPaths) : IO UInt32 := do
  match ← scaffold inputs with
  | .error error => reportError mode error
  | .ok result =>
      match mode with
      | .human => printDiagnostics result.diagnostics
      | .json => printJsonDiagnostics result.diagnostics
      IO.println s!"scaffolded proposal {inputs.proposal}"
      return 0

private def runProjectTrace (mode : DiagnosticsMode) (inputs : ProjectTracePaths) : IO UInt32 := do
  match ← projectTrace inputs with
  | .error error => reportError mode error
  | .ok result =>
      match mode with
      | .human => pure ()
      | .json => printJsonDiagnostics []
      IO.println s!"projected trace {inputs.out} receipt {inputs.receipt} {result.result.receipt.outputSha256}"
      return 0

private def workflowSuccess (mode : DiagnosticsMode) (message : String) : IO UInt32 := do
  if let .json := mode then printJsonDiagnostics []
  IO.println message
  return 0

private def runResolveSealed (mode : DiagnosticsMode)
    (inputs : Shell.ModelInterface.ScaffoldWorkflow.WorkflowPaths)
    (sealed : String) (corpusManifest : Option String) (lock : String) : IO UInt32 := do
  match ← Shell.ModelInterface.ScaffoldWorkflow.compileResolveSealed inputs sealed corpusManifest with
  | .error error => reportError mode error
  | .ok compilation =>
      match ← writeLock lock compilation with
      | .error error => reportError mode error compilation.diagnostics
      | .ok () =>
          match mode with
          | .human => printDiagnostics compilation.diagnostics
          | .json => printJsonDiagnostics compilation.diagnostics
          IO.println s!"resolved sealed {lock} {compilation.lock.semanticDigest}"
          return 0

private def runCheckSealed (mode : DiagnosticsMode)
    (inputs : Shell.ModelInterface.ScaffoldWorkflow.WorkflowPaths)
    (sealed : String) (corpusManifest : Option String) (lock target out : String)
    (bundle : Bool) : IO UInt32 := do
  match ← Shell.ModelInterface.ScaffoldWorkflow.compileResolveSealed inputs sealed corpusManifest with
  | .error error => reportError mode error
  | .ok compilation =>
      match ← checkCompilation compilation lock target out bundle with
      | .error error => reportError mode error compilation.diagnostics
      | .ok report =>
          match mode with
          | .human => printDiagnostics report.diagnostics
          | .json =>
              let diagnostics := if !report.clean && report.diagnostics.isEmpty then
                  [shellDiagnostic "MIC-C-STALE-001" "generatedOutput" "generated output is stale"]
                else report.diagnostics
              printJsonDiagnostics diagnostics
          if report.clean then
            IO.println "model-interface sealed check clean"
            return 0
          for path in report.stalePaths do IO.eprintln s!"stale: {path}"
          return 1

def run (arguments : List String) : IO UInt32 := do
  if arguments == ["--version"] then
    IO.println "model-interface-gen/1 mirrors.suite-bundle/v1"
    return 0
  match parseCommand arguments with
  | .error message =>
      IO.eprintln message
      if message != usage then IO.eprintln usage
      return 2
  | .ok parsed =>
      match parsed.command with
      | .scheduleKit lock mapping target out check =>
          if check then
            match ← Shell.ModelInterface.ScheduleKit.check lock mapping target out with
            | .error error => reportError parsed.diagnostics error
            | .ok report =>
                IO.println s!"DPM kit check: {if report.clean then "clean" else "stale"}"
                for path in report.stalePaths do IO.eprintln s!"stale: {path}"
                return if report.clean then 0 else 1
          else
            match ← Shell.ModelInterface.ScheduleKit.generate lock mapping target out with
            | .error error => reportError parsed.diagnostics error
            | .ok paths =>
                IO.println s!"generated DPM kit: {paths.length} owned files in {out}"
                return 0
      | .compareLocks fromLock toLock =>
          match ← Shell.ModelInterface.Migration.compareLocks fromLock toLock with
          | .error error => reportError parsed.diagnostics error
          | .ok report =>
              IO.println (Lean.Json.compress report)
              return 0
      | .resolve inputs lock => runResolve parsed.diagnostics inputs lock
      | .generate lock target out bundle => runGenerate parsed.diagnostics lock target out bundle
      | .generateCmake inputs lock target out =>
          match ← generateCmake inputs lock target out with
          | .error error => reportError parsed.diagnostics error
          | .ok paths =>
              IO.println s!"generated {paths.length} files in {out}"
              return 0
      | .checkCmake inputs lock target out =>
          match ← checkCmake inputs lock target out with
          | .error error => reportError parsed.diagnostics error
          | .ok report =>
              match parsed.diagnostics with
              | .json => printJsonDiagnostics report.diagnostics
              | .human => printDiagnostics report.diagnostics
              if report.clean then
                IO.println "model-interface CMake check clean"
                return 0
              for path in report.stalePaths do IO.eprintln s!"stale: {path}"
              return 1
      | .check inputs lock target out bundle => runCheck parsed.diagnostics inputs lock target out bundle
      | .preflight lock trace requireAllActions =>
          runPreflightCommand parsed.diagnostics lock trace requireAllActions
      | .scaffold inputs => runScaffold parsed.diagnostics inputs
      | .projectTrace inputs => runProjectTrace parsed.diagnostics inputs
      | .scaffoldWorkflow inputs proposal replace =>
          match ← Shell.ModelInterface.ScaffoldWorkflow.writeScaffold inputs proposal replace with
          | .error error => reportError parsed.diagnostics error
          | .ok result =>
              match parsed.diagnostics with
              | .human => printDiagnostics result.diagnostics
              | .json => printJsonDiagnostics result.diagnostics
              IO.println s!"scaffolded reviewable proposal {proposal} {result.proposalSha256}"
              return 0
      | .sealScaffold inputs proposal review out =>
          match ← Shell.ModelInterface.ScaffoldWorkflow.sealScaffold inputs proposal review out with
          | .error error => reportError parsed.diagnostics error
          | .ok result =>
              match parsed.diagnostics with
              | .human => printDiagnostics result.compilation.diagnostics
              | .json => printJsonDiagnostics result.compilation.diagnostics
              IO.println s!"sealed scaffold {out} {result.compilation.lock.semanticDigest}"
              return 0
      | .resolveSealed inputs sealed corpusManifest lock =>
          runResolveSealed parsed.diagnostics inputs sealed corpusManifest lock
      | .checkSealed inputs sealed corpusManifest lock target out bundle =>
          runCheckSealed parsed.diagnostics inputs sealed corpusManifest lock target out bundle
      | .projectCorpus inputs =>
          match ← Shell.ModelInterface.Corpus.projectCorpus inputs with
          | .error error => reportError parsed.diagnostics error
          | .ok result =>
              workflowSuccess parsed.diagnostics s!"projected corpus {inputs.out} {result.manifestSha256}"
      | .checkCorpus out manifestSha256 =>
          match ← Shell.ModelInterface.Corpus.checkCorpus out manifestSha256 with
          | .error error => reportError parsed.diagnostics error
          | .ok _ => workflowSuccess parsed.diagnostics "model-interface corpus check clean"

end ModelInterfaceGen

def main (arguments : List String) : IO UInt32 := do
  try
    ModelInterfaceGen.run arguments
  catch error =>
    IO.eprintln s!"model_interface_gen: {error}"
    return 2
