import Lean.Data.Json

/-!
# `tla_frontend` CLI gate (`tools/TlaFrontendCliSpec.lean`)

Drives the TF8 slice of `Docs/model-interface-compiler/tla-frontend-tasks.md`:
exact help and malformed-argument behavior, closed and versioned JSON documents
whose human rendering carries equivalent diagnostic facts, no physical path in
default output, and a byte-pinned public fixture for `inspect --variables`.

The gate invokes the built `.lake/build/bin/tla_frontend` binary, so it also
proves the development command stays a separate executable from the operational
`mirror` CLI.
-/

open Lean

namespace TlaFrontendCliSpec

abbrev Failures := IO.Ref (List String)

private def check (failures : Failures) (name : String) (condition : Bool)
    (detail : String := "") : IO Unit := do
  if !condition then
    failures.modify fun values =>
      values ++ [if detail.isEmpty then name else s!"{name}: {detail}"]

/-- The frozen usage text. It duplicates the executable's `usage` on purpose:
help is an acceptance surface, so a wording change must update both files. -/
private def usage : String := String.intercalate "\n" [
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
  "documents use the closed schema mirrors.tla-frontend-inspection/v1."
]

private def schema : String := "mirrors.tla-frontend-inspection/v1"

private def parseKeys : List String :=
  ["command", "declarations", "dependencies", "diagnostics", "module", "ok",
   "schema", "source"]

private def resolveKeys : List String :=
  ["command", "dependencies", "diagnostics", "levels", "module", "ok",
   "operators", "schema", "source", "sources", "variables"]

private def inspectAllKeys : List String :=
  ["command", "dependencies", "diagnostics", "levels", "module", "ok",
   "operators", "schema", "source", "variables"]

private def inspectVariablesKeys : List String :=
  ["command", "diagnostics", "module", "ok", "schema", "source", "variables"]

private def variableKeys : List String :=
  ["declaredIn", "declaredName", "importPath", "local", "location", "name"]

private def transferPath : String :=
  "test/fixtures/tla-frontend/accepted/generic-transfer/GenericTransfer.tla"

private def rejectedPath : String :=
  "test/fixtures/tla-frontend/rejected/RejectPrecedenceMix.tla"

private def goldenPath : System.FilePath :=
  "test/fixtures/tla-frontend/cli/inspect-generic-transfer-variables.json"

/-! ## Helpers -/

private def invoke (args : Array String) : IO IO.Process.Output :=
  IO.Process.output { cmd := ".lake/build/bin/tla_frontend", args := args }

private def decode (raw : String) : Option Json := (Json.parse raw).toOption

private def objKeys (json : Json) : List String :=
  match json with
  | .obj fields =>
      fields.foldl (init := ([] : List String)) (fun acc key _ => acc ++ [key])
  | _ => []

private def field? (json : Json) (key : String) : Option Json :=
  (json.getObjVal? key).toOption

private def stringField? (json : Json) (key : String) : Option String :=
  field? json key >>= fun value => (Json.getStr? value).toOption

private def natField? (json : Json) (key : String) : Option Nat :=
  field? json key >>= fun value => (Json.getNat? value).toOption

private def boolField? (json : Json) (key : String) : Option Bool :=
  field? json key >>= fun value => (Json.getBool? value).toOption

private def arrayField? (json : Json) (key : String) : Option (Array Json) :=
  field? json key >>= fun value => (Json.getArr? value).toOption

private def moduleSource (name parent : String) (variables : List String) : String :=
  let declarationLines := variables.mapIdx fun index entry =>
    if index + 1 == variables.length then "  " ++ entry else "  " ++ entry ++ ","
  String.intercalate "\n"
    (["---- MODULE " ++ name ++ " ----", "", "EXTENDS " ++ parent, "",
      "VARIABLES"] ++ declarationLines ++ ["", "====", ""])

private def leaked (raw : String) (root : System.FilePath) : Bool :=
  raw.contains root.toString

private def readText? (path : System.FilePath) : IO (Option String) := do
  try
    let text ← IO.FS.readFile path
    return some text
  catch _ => return none

/-! ## Exact help and malformed arguments -/

private def scenarioUsage (failures : Failures) : IO Unit := do
  let help ← invoke #["help"]
  check failures "usage: help exits zero" (help.exitCode == 0)
  check failures "usage: help prints the frozen text exactly"
    (help.stdout == usage ++ "\n")
  check failures "usage: help writes nothing to stderr" (help.stderr == "")
  let empty ← invoke #[]
  check failures "usage: missing command exits two" (empty.exitCode == 2)
  check failures "usage: missing command keeps stdout empty" (empty.stdout == "")
  check failures "usage: missing command stderr is exact"
    (empty.stderr == "missing command\n" ++ usage ++ "\n")
  let unknown ← invoke #["frobnicate"]
  check failures "usage: unknown command exits two" (unknown.exitCode == 2)
  check failures "usage: unknown command stderr is exact"
    (unknown.stderr == "unknown command: frobnicate\n" ++ usage ++ "\n")
  let missingValue ← invoke #["parse", "--spec"]
  check failures "usage: missing option value exits two" (missingValue.exitCode == 2)
  check failures "usage: missing option value stderr is exact"
    (missingValue.stderr == "missing value for --spec\n" ++ usage ++ "\n")
  let duplicate ← invoke #["parse", "--spec", "A.tla", "--spec", "B.tla"]
  check failures "usage: duplicate option exits two" (duplicate.exitCode == 2)
  check failures "usage: duplicate option stderr is exact"
    (duplicate.stderr == "duplicate option: --spec\n" ++ usage ++ "\n")
  let badFormat ← invoke #["parse", "--spec", "A.tla", "--format", "yaml"]
  check failures "usage: unsupported format exits two" (badFormat.exitCode == 2)
  check failures "usage: unsupported format stderr is exact"
    (badFormat.stderr == "unsupported --format yaml; expected json\n" ++ usage ++ "\n")
  let sectionFlag ← invoke #["resolve", "--spec", "A.tla", "--variables"]
  check failures "usage: section flag on resolve exits two" (sectionFlag.exitCode == 2)
  check failures "usage: section flag on resolve stderr is exact"
    (sectionFlag.stderr == "option --variables is not valid for resolve\n" ++ usage ++ "\n")

/-! ## Parse: syntax only -/

private def scenarioParse (failures : Failures) (root : System.FilePath) : IO Unit := do
  let base := root / "CliBase.tla"
  IO.FS.writeFile base (moduleSource "CliBase" "Integers"
    ["first", "second", "third"])
  let text := root / "NotTla.txt"
  IO.FS.writeFile text "---- MODULE NotTla ----\n====\n"
  let wrongExtension ← invoke #["parse", "--spec", text.toString]
  check failures "parse: a non-.tla root is a usage error" (wrongExtension.exitCode == 2)
  check failures "parse: a non-.tla root stderr is exact"
    (wrongExtension.stderr == "spec path must name a .tla file\n" ++ usage ++ "\n")
  let human ← invoke #["parse", "--spec", base.toString]
  let jsonRun ← invoke #["parse", "--spec", base.toString, "--format", "json"]
  check failures "parse: human exits zero" (human.exitCode == 0) human.stderr
  check failures "parse: json exits zero" (jsonRun.exitCode == 0) jsonRun.stderr
  check failures "parse: default output carries no physical path"
    (!leaked human.stdout root)
  check failures "parse: json output carries no physical path"
    (!leaked jsonRun.stdout root)
  match decode jsonRun.stdout with
  | none => check failures "parse: json decodes" false jsonRun.stdout
  | some doc =>
      check failures "parse: schema is the closed version"
        (stringField? doc "schema" == some schema)
      check failures "parse: command tag" (stringField? doc "command" == some "parse")
      check failures "parse: ok flag" (boolField? doc "ok" == some true)
      check failures "parse: declared module name"
        (stringField? doc "module" == some "CliBase")
      let sourcePath? :=
        field? doc "source" >>= fun source => stringField? source "path"
      check failures "parse: logical source path" (sourcePath? == some "CliBase.tla")
      check failures "parse: dependency declarations counted"
        ((natField? doc "dependencies").getD 0 >= 1)
      check failures "parse: declaration count present"
        ((natField? doc "declarations").isSome)
      check failures "parse: json object keys are closed" (objKeys doc == parseKeys)
      check failures "parse: human summary matches json facts"
        (human.stdout.contains s!"declarations: {(natField? doc "declarations").getD 0}" &&
         human.stdout.contains s!"dependencies: {(natField? doc "dependencies").getD 0}")

private def scenarioParseRejection (failures : Failures) : IO Unit := do
  let human ← invoke #["parse", "--spec", rejectedPath]
  let jsonRun ← invoke #["parse", "--spec", rejectedPath, "--format", "json"]
  check failures "parse rejection: human exits one" (human.exitCode == 1)
  check failures "parse rejection: json exits one" (jsonRun.exitCode == 1)
  match decode jsonRun.stdout with
  | none => check failures "parse rejection: json decodes" false jsonRun.stdout
  | some doc =>
      check failures "parse rejection: ok flag is false"
        (boolField? doc "ok" == some false)
      check failures "parse rejection: module is null"
        (field? doc "module" == some Json.null)
      check failures "parse rejection: keys stay closed" (objKeys doc == parseKeys)
      match arrayField? doc "diagnostics" with
      | none => check failures "parse rejection: diagnostics present" false
      | some diagnostics =>
          check failures "parse rejection: diagnostics are nonempty"
            (diagnostics.size > 0)
          for diagnostic in diagnostics do
            let code := (stringField? diagnostic "code").getD ""
            let message := (stringField? diagnostic "message").getD ""
            check failures s!"parse rejection: human carries {code}"
              (human.stdout.contains ("[" ++ code ++ "]") && human.stdout.contains message)

/-! ## Resolve: graph and elaboration -/

private def scenarioResolve (failures : Failures) : IO Unit := do
  let human ← invoke #["resolve", "--spec", transferPath]
  let jsonRun ← invoke #["resolve", "--spec", transferPath, "--format", "json"]
  let rerun ← invoke #["resolve", "--spec", transferPath, "--format", "json"]
  check failures "resolve: human exits zero" (human.exitCode == 0) human.stderr
  check failures "resolve: json exits zero" (jsonRun.exitCode == 0) jsonRun.stderr
  check failures "resolve: repeated runs are byte-identical" (rerun.stdout == jsonRun.stdout)
  check failures "resolve: default output carries no physical path"
    (!human.stdout.contains "/home" && !jsonRun.stdout.contains "/home")
  match decode jsonRun.stdout with
  | none => check failures "resolve: json decodes" false jsonRun.stdout
  | some doc =>
      check failures "resolve: schema is the closed version"
        (stringField? doc "schema" == some schema)
      check failures "resolve: ok flag" (boolField? doc "ok" == some true)
      check failures "resolve: object keys are closed" (objKeys doc == resolveKeys)
      check failures "resolve: root module name"
        (stringField? doc "module" == some "GenericTransfer")
      let sourcePath? : Option String :=
        field? doc "source" >>= fun source => stringField? source "path"
      check failures "resolve: logical source path"
        (sourcePath? == some "GenericTransfer.tla")
      match arrayField? doc "variables" with
      | none => check failures "resolve: variables present" false
      | some variables =>
          check failures "resolve: nineteen effective variables"
            (variables.size == 19) (toString variables.size)
          let inherited := variables.filter fun entry =>
            stringField? entry "declaredIn" == some "GenericBase"
          let ownVariables := variables.filter fun entry =>
            stringField? entry "declaredIn" == some "GenericTransfer"
          check failures "resolve: twelve inherited variables"
            (inherited.size == 12) (toString inherited.size)
          check failures "resolve: seven local variables"
            (ownVariables.size == 7) (toString ownVariables.size)
          match variables.toList with
          | [] => check failures "resolve: variable entries" false
          | entry :: _ =>
              check failures "resolve: variable entry keys are closed"
                (objKeys entry == variableKeys)
      match arrayField? doc "sources" with
      | none => check failures "resolve: manifest present" false
      | some sources =>
          check failures "resolve: manifest covers both captured modules"
            (sources.size == 2)
      match arrayField? doc "dependencies" with
      | none => check failures "resolve: dependencies present" false
      | some edges =>
          check failures "resolve: EXTENDS edge to the base module"
            (edges.any fun edge =>
              stringField? edge "dependency" == some "GenericBase" &&
              stringField? edge "kind" == some "extends")
      match arrayField? doc "levels" with
      | none => check failures "resolve: levels present" false
      | some levels =>
          check failures "resolve: every effective variable has a level entry"
            (levels.size >= 19)

private def scenarioMissingDependency (failures : Failures)
    (root : System.FilePath) : IO Unit := do
  let missing := root / "CliMissing.tla"
  IO.FS.writeFile missing (moduleSource "CliMissing" "NoSuchModule" ["solo"])
  let human ← invoke #["resolve", "--spec", missing.toString]
  let jsonRun ← invoke #["resolve", "--spec", missing.toString, "--format", "json"]
  check failures "missing dependency: human exits one" (human.exitCode == 1)
  check failures "missing dependency: json exits one" (jsonRun.exitCode == 1)
  check failures "missing dependency: default output carries no physical path"
    (!leaked human.stdout root && !leaked jsonRun.stdout root)
  match decode jsonRun.stdout with
  | none => check failures "missing dependency: json decodes" false jsonRun.stdout
  | some doc =>
      check failures "missing dependency: ok flag is false"
        (boolField? doc "ok" == some false)
      check failures "missing dependency: keys stay closed" (objKeys doc == resolveKeys)
      check failures "missing dependency: fact sections stay empty"
        ((arrayField? doc "variables").getD (#[] : Array Json) == #[] &&
         (arrayField? doc "sources").getD (#[] : Array Json) == #[])
      let diagnostics := (arrayField? doc "diagnostics").getD (#[] : Array Json)
      check failures "missing dependency: diagnostics reported" (diagnostics.size > 0)
      for diagnostic in diagnostics do
        let code := (stringField? diagnostic "code").getD ""
        check failures s!"missing dependency: human carries {code}"
          (human.stdout.contains ("[" ++ code ++ "]"))

/-! ## Inspect: section projection and the public fixture -/

private def scenarioInspect (failures : Failures) : IO Unit := do
  let variablesRun ← invoke
    #["inspect", "--spec", transferPath, "--variables", "--format", "json"]
  check failures "inspect: --variables exits zero" (variablesRun.exitCode == 0)
  match decode variablesRun.stdout with
  | none => check failures "inspect: --variables json decodes" false
  | some doc =>
      check failures "inspect: --variables keys are closed"
        (objKeys doc == inspectVariablesKeys)
      let projected := (arrayField? doc "variables").getD (#[] : Array Json)
      check failures "inspect: --variables projects nineteen entries"
        (projected.size == 19)
  let allRun ← invoke #["inspect", "--spec", transferPath, "--format", "json"]
  check failures "inspect: default exits zero" (allRun.exitCode == 0)
  match decode allRun.stdout with
  | none => check failures "inspect: default json decodes" false
  | some doc =>
      check failures "inspect: default keys are closed" (objKeys doc == inspectAllKeys)
  let human ← invoke #["inspect", "--spec", transferPath]
  check failures "inspect: human exits zero" (human.exitCode == 0)
  check failures "inspect: human prints every section"
    (human.stdout.contains "variables:" && human.stdout.contains "dependencies:" &&
     human.stdout.contains "operators:" && human.stdout.contains "levels:")
  check failures "inspect: default output carries no physical path"
    (!human.stdout.contains "/home")

private def scenarioPublicFixture (failures : Failures) : IO Unit := do
  let goldenExists ← goldenPath.pathExists
  if !goldenExists then
    check failures "fixture: the inspect golden exists" false goldenPath.toString
    return
  let golden ← IO.FS.readFile goldenPath
  let run ← invoke
    #["inspect", "--spec", transferPath, "--variables", "--format", "json"]
  check failures "fixture: inspect exits zero" (run.exitCode == 0) run.stderr
  check failures "fixture: inspect output matches the pinned public fixture"
    (run.stdout == golden)
  match decode golden with
  | none => check failures "fixture: the golden decodes" false
  | some doc =>
      check failures "fixture: the golden pins the schema"
        (stringField? doc "schema" == some schema)
      check failures "fixture: the golden pins the command"
        (stringField? doc "command" == some "inspect")
      check failures "fixture: the golden pins the root module"
        (stringField? doc "module" == some "GenericTransfer")
      let projected := (arrayField? doc "variables").getD (#[] : Array Json)
      check failures "fixture: the golden pins nineteen variables"
        (projected.size == 19)

/-! ## Operational CLI isolation -/

private def scenarioMirrorIsolation (failures : Failures) : IO Unit := do
  match (← readText? "Shell/Cli.lean") with
  | some text =>
      check failures "isolation: no development command in Shell/Cli.lean"
        (!text.contains "tla_frontend")
  | none => check failures "isolation: Shell/Cli.lean is readable" false
  match (← readText? "Main.lean") with
  | some text =>
      check failures "isolation: no development command in Main.lean"
        (!text.contains "tla_frontend")
  | none => check failures "isolation: Main.lean is readable" false

/-! ## Driver -/

def run : IO UInt32 := do
  let failures ← IO.mkRef ([] : List String)
  let root ← IO.FS.createTempDir
  try
    scenarioUsage failures
    scenarioParse failures root
    scenarioParseRejection failures
    scenarioResolve failures
    scenarioMissingDependency failures root
    scenarioInspect failures
    scenarioPublicFixture failures
    scenarioMirrorIsolation failures
    let collected ← failures.get
    if collected.isEmpty then
      IO.println "TLA FRONTEND CLI GREEN"
      return 0
    else
      for failure in collected do
        IO.println s!"FAIL: {failure}"
      return 1
  finally
    IO.FS.removeDirAll root

end TlaFrontendCliSpec

def main : IO UInt32 := TlaFrontendCliSpec.run
