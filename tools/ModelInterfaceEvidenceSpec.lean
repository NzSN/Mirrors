import Core.ModelInterface.Types
import Shell.ModelInterface.Evidence
import Shell.ModelInterface.SpecVariables

namespace ModelInterfaceEvidenceSpec

open Core.ModelInterface

abbrev Failures := IO.Ref (List String)

private def check (failures : Failures) (name : String) (condition : Bool)
    (detail : String := "") : IO Unit := do
  if !condition then
    failures.modify fun values => values ++ [if detail.isEmpty then name else s!"{name}: {detail}"]

private def errorContains {α : Type} (needle : String) (result : Except String α) : Bool :=
  match result with
  | .ok _ => false
  | .error error => error.contains needle

private def nestedMapText (wrappers : Nat) : String :=
  (List.range wrappers).foldl (fun value _ => "(Int -> " ++ value ++ ")") "Int"

private def parsesAs (raw : String) (expected : ModelType) : Bool :=
  match Shell.ModelInterface.Evidence.parseType raw with
  | .ok actual => actual == expected
  | .error _ => false

private def scenarioArrowTypes (failures : Failures) : IO Unit := do
  check failures "arrow: Int map"
    (parsesAs "(Int -> Int)" (.map .int .int))
  check failures "arrow: string-valued map"
    (parsesAs "(Int -> Str)" (.map .int .str))
  check failures "arrow: nested right precedence"
    (parsesAs "(Int -> (Int -> Str))" (.map .int (.map .int .str)))
  check failures "arrow: nested key and record value"
    (parsesAs "((Int -> Int) -> { left: Int, labels: (Int -> Str) })"
      (.map (.map .int .int) (.record [
          { wireName := "left", type := .int },
          { wireName := "labels", type := .map .int .str }])))
  check failures "arrow: nesting in set"
    (parsesAs "Set((Int -> Str))" (.set (.map .int .str)))
  check failures "arrow: depth boundary accepted"
    (Shell.ModelInterface.Evidence.parseType
      (nestedMapText (maxStructuralTypeDepthV1 - 1))).isOk
  check failures "arrow: depth overflow rejected"
    (!(Shell.ModelInterface.Evidence.parseType
      (nestedMapText maxStructuralTypeDepthV1)).isOk)
  for (name, malformed) in [
      ("unparenthesized", "Int -> Int"),
      ("missing key", "( -> Int)"),
      ("missing value", "(Int -> )"),
      ("multiple arrows", "(Int -> Int -> Str)"),
      ("missing arrow", "(Int)"),
      ("mismatched delimiters", "(Int -> { x: Int])")] do
    check failures ("arrow malformed: " ++ name)
      (!(Shell.ModelInterface.Evidence.parseType malformed).isOk)

private def rbtEvidenceJson (paramVars : String) : String :=
  "{\"#meta\":{\"varTypes\":{" ++
    "\"nk\":\"(Int -> Int)\",\"nc\":\"(Int -> Str)\"," ++
    "\"action_taken\":\"Str\"}}," ++
    "\"vars\":[\"nk\",\"nc\",\"action_taken\"]," ++
    "\"param_vars\":" ++ paramVars ++ ",\"params\":null}"

private def scenarioRawEvidence (failures : Failures) : IO Unit := do
  match Shell.ModelInterface.Evidence.fromString (rbtEvidenceJson "null") "rbt.itf.json" with
  | .error error => check failures "evidence: null param_vars accepted" false error
  | .ok evidence =>
      check failures "evidence: null param_vars normalized" evidence.itfParamVars.isEmpty
      check failures "evidence: arrow facts normalized"
        (evidence.typeFacts.any fun fact =>
          fact.modelPath.root == "nc" && fact.modelPath.path.isEmpty &&
            fact.type == .map .int .str)
  check failures "evidence: absent param_vars accepted"
    (Shell.ModelInterface.Evidence.fromString
      ((rbtEvidenceJson "null").replace ",\"param_vars\":null" "") "rbt.itf.json").isOk
  check failures "evidence: wrong param_vars rejected"
    (errorContains "expected array or null"
      (Shell.ModelInterface.Evidence.fromString (rbtEvidenceJson "7") "rbt.itf.json"))

private def rbtSource : String := String.intercalate "\n" [
  "---- MODULE RBT ----",
  "VARIABLES",
  "  \\* @type: Int -> Int;",
  "  nk,",
  "  \\* @type: Int -> Str;",
  "  nc, nl,",
  "  nr, nb, root,",
  "  activeKeys, usedNodes,",
  "  action_taken, step_count, parameters",
  "===="]

private def currentRbtVariables : List String :=
  ["nk", "nc", "nl", "nr", "nb", "root", "activeKeys", "usedNodes",
    "action_taken", "step_count", "parameters"]

private def scenarioSpecVariables (failures : Failures) : IO Unit := do
  check failures "variables: current RBT multiline declarations"
    (Shell.ModelInterface.SpecVariables.extract rbtSource == .ok currentRbtVariables)
  let lexicalNoise := String.intercalate "\n" [
    "---- MODULE Noise ----",
    "\\* VARIABLES lineCommentFake",
    "(* VARIABLES blockFake (* VARIABLE nestedFake *) *)",
    "Text == \"VARIABLES stringFake\\\"stillString\"",
    "VARIABLE first",
    "VARIABLES second,",
    "  third",
    "===="]
  check failures "variables: comments and strings hidden"
    (Shell.ModelInterface.SpecVariables.extract lexicalNoise ==
      .ok ["first", "second", "third"])
  check failures "variables: stale nodes rejected with both directions"
    (match Shell.ModelInterface.SpecVariables.validateEvidenceVariables
        rbtSource ["nodes", "root", "activeKeys", "usedNodes", "action_taken",
          "step_count", "parameters"] with
      | .ok _ => false
      | .error error => error.contains "nodes" && error.contains "nk" && error.contains "nc")
  check failures "variables: matching current evidence accepted"
    (Shell.ModelInterface.SpecVariables.validateEvidenceVariables
      rbtSource currentRbtVariables).isOk
  for (name, source) in [
      ("missing comma", "VARIABLES one two"),
      ("unfinished", "VARIABLES one,"),
      ("missing first name", "VARIABLES\nInit == TRUE"),
      ("invalid name", "VARIABLE 7bad"),
      ("unterminated comment", "(* VARIABLES hidden"),
      ("unterminated string", "Text == \"VARIABLE hidden")] do
    check failures ("variables malformed: " ++ name)
      (!(Shell.ModelInterface.SpecVariables.extract source).isOk)
  check failures "variables bounds: source bytes"
    (errorContains "source exceeds byte limit"
      (Shell.ModelInterface.SpecVariables.extract "VARIABLE x"
        { Shell.ModelInterface.SpecVariables.defaultLimits with maxSourceBytes := 1 }))
  check failures "variables bounds: declaration count"
    (errorContains "declarations exceed count limit"
      (Shell.ModelInterface.SpecVariables.extract "VARIABLES x, y"
        { Shell.ModelInterface.SpecVariables.defaultLimits with maxDeclarations := 1 }))
  check failures "variables bounds: identifier bytes"
    (errorContains "name exceeds byte limit"
      (Shell.ModelInterface.SpecVariables.extract "VARIABLE longName"
        { Shell.ModelInterface.SpecVariables.defaultLimits with maxIdentifierBytes := 3 }))
  check failures "variables bounds: nested comment depth"
    (errorContains "comment exceeds depth limit"
      (Shell.ModelInterface.SpecVariables.extract "(* outer (* inner *) *)\nVARIABLE x"
        { Shell.ModelInterface.SpecVariables.defaultLimits with maxCommentDepth := 1 }))
  check failures "variables malformed: duplicate declaration"
    (errorContains "duplicate"
      (Shell.ModelInterface.SpecVariables.extract "VARIABLES x, x"))
  check failures "variables malformed: duplicate evidence"
    (errorContains "duplicate evidence"
      (Shell.ModelInterface.SpecVariables.validateEvidenceVariables
        "VARIABLE x" ["x", "x"]))

def run : IO UInt32 := do
  let failures ← IO.mkRef ([] : List String)
  scenarioArrowTypes failures
  scenarioRawEvidence failures
  scenarioSpecVariables failures
  let values ← failures.get
  if values.isEmpty then
    IO.println "MODEL INTERFACE EVIDENCE SPEC GREEN"
    return 0
  for failure in values do IO.eprintln s!"FAIL {failure}"
  IO.eprintln s!"{values.length} FAILURES"
  return 1

end ModelInterfaceEvidenceSpec

def main : IO UInt32 := ModelInterfaceEvidenceSpec.run
