import Codec.TlaFrontendJson
import Shell.Tla.Frontend

/-! Test-only observations over the production frontend, including the inline
provider and parsed INSTANCE actuals omitted from inspection v1. -/

namespace TlaDifferentialDriver

open Lean Core.Tla Shell.Tla

def schema : String := "mirrors.tla-differential-driver/v1"

/-- Only qualified atomic actuals have a canonical semantic representation.
Other expressions remain explicitly unavailable to the comparator. -/
def actualJson : Expression → Json
  | .name reference _ => Json.mkObj [("kind", .str "name"),
      ("value", .str ((reference.qualifier.map (· ++ "!")).getD "" ++ reference.spelling))]
  | .integer value _ => Json.mkObj [("kind", .str "integer"), ("value", toJson value)]
  | .boolean value _ => Json.mkObj [("kind", .str "boolean"), ("value", .bool value)]
  | .string value _ => Json.mkObj [("kind", .str "string"), ("value", .str value)]
  | _ => .null

def instanceJson (owner : ModuleName) (forcedLocal : Bool) : Declaration → Array Json
  | .«local» _ declaration => instanceJson owner true declaration
  | .«instance» inst => #[Json.mkObj [
      ("owner", .str owner.name), ("name", toJson inst.name),
      ("module", .str inst.moduleName.name),
      ("local", .bool (forcedLocal || inst.«local»)),
      ("line", toJson inst.range.start.line),
      ("substitutions", .arr (inst.substitutions.map fun substitution =>
        Json.mkObj [("formal", .str substitution.formal),
          ("actual", actualJson substitution.actual), ("implicit", .bool false)]))]]
  | _ => #[]

def moduleJson (node : ModuleNode) : Json :=
  Json.mkObj [("name", .str node.name.name),
    ("instances", .arr (node.module.declarations.foldl
      (fun acc declaration => acc ++ instanceJson node.name false declaration) #[])),
    ("declarations", .arr (node.module.declarations.map fun declaration =>
      Json.mkObj [("kind", .str declaration.summaryKind),
        ("names", toJson declaration.summaryNames), ("line", toJson declaration.firstLine),
        ("arities", toJson declaration.operatorArities)]))]

def document (path : String) (outcome : Except FrontendFailure FrontendResult) : Json :=
  let (inspection, modules) := match outcome with
    | .error failure =>
        (Codec.TlaFrontendJson.resolveDocument path none failure.diagnostics, #[])
    | .ok result =>
        (Codec.TlaFrontendJson.resolveDocument path
          (some (result.graph, result.elaborated)) #[], result.graph.sortedNodes.map moduleJson)
  Json.mkObj [("schema", .str schema), ("inspection", inspection), ("modules", .arr modules)]

def inlineRequest (json : Json) : Except String (String × Array (ModuleName × String)) := do
  let root ← json.getObjValAs? String "root"
  let values ← json.getObjVal? "sources" >>= Json.getArr?
  let sources ← values.mapM fun value => do
    let name ← value.getObjValAs? String "name"
    let text ← value.getObjValAs? String "text"
    pure (({ name := name } : ModuleName), text)
  return (root, sources)

def run (arguments : List String) : IO UInt32 := do
  let (path, result) ← match arguments with
    | ["borrowed", path, expectedRoot] => do
        let file : System.FilePath := path
        let result ← analyze (SourceProvider.borrowedDirectory (file.parent.getD "."))
          { root := { moduleName := { name := expectedRoot }, logicalPath := file.fileName.getD path } }
        pure (((path : System.FilePath).fileName.getD path), result)
    | ["inline", input] => do
        let raw ← IO.FS.readFile input
        let (root, sources) ← IO.ofExcept (Json.parse raw >>= inlineRequest)
        let result ← analyze (SourceProvider.inline sources)
          { root := ModuleRef.ofModuleName { name := root } }
        pure (root ++ ".tla", result)
    | _ => do
        IO.eprintln "usage: tla_differential_driver (borrowed SPEC ROOT | inline REQUEST.json)"
        return 2
  IO.println (document path result).compress
  return if result.isOk then 0 else 1

end TlaDifferentialDriver

def main (arguments : List String) : IO UInt32 := do
  try TlaDifferentialDriver.run arguments
  catch error =>
    IO.eprintln s!"tla_differential_driver: {error}"
    return 2
