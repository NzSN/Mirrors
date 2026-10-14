import Codec.StrictJson
import Core.Dpm
import Core.ModelInterface.Reduction

namespace Codec.Dpm
open Lean Core.Dpm

def object (j : Json) (keys : List String) : Except String (List (String × Json)) := do
  let .obj values := j | throw "expected object"
  let fields := values.toList
  unless fields.length == keys.length && fields.all (fun f => keys.contains f.1) do
    throw "missing or unknown field"
  return fields

def get (fields : List (String × Json)) (name : String) : Except String Json :=
  match fields.lookup name with
  | some value => .ok value
  | none => .error s!"missing field {name}"

def string : Json → Except String String
  | .str value => .ok value
  | _ => .error "expected string"

def natural : Json → Except String Nat
  | .num ⟨n, 0⟩ => if n ≥ 0 then .ok n.toNat else .error "expected natural"
  | _ => .error "expected natural"

def array : Json → Except String (List Json)
  | .arr values => .ok values.toList
  | _ => .error "expected array"

private def file (j : Json) : Except String Unit := do
  let f ← object j ["path", "sha256"]
  let path ← string (← get f "path")
  if path.isEmpty || path.toUTF8.size > 4096 || path.contains '\x00' then throw "invalid path"
  if !Core.ModelInterface.validSha256 (← string (← get f "sha256")) then
    throw "invalid artifact digest"

def decode (raw : ByteArray) : Except String (Json × List Candidate) := do
  let j ← (StrictJson.parseBytes raw { maxBytes := 4*1024*1024, maxDepth := 32 }).mapError toString
  unless (j.getObjValAs? String "schema").toOption == some "mirrors.dpm-project/v2" do
    throw "unsupported project; reprepare as mirrors.dpm-project/v2"
  let p ← object j ["schema", "profile", "identity", "explorerIdentity", "command", "artifacts", "chains",
    "baseline", "candidates", "signature", "limits"]
  let profile ← string (← get p "profile")
  unless ["mirrorcpp.cooperative-checkpoints/v1", "mirrorecma.worker-checkpoints/v1",
    "mirrorrust.cooperative-checkpoints/v1"].contains profile do throw "unsupported scheduling profile"
  let identity ← get p "identity"
  let ids ← object identity ["modelSemanticDigest", "mappingSha256", "implementationSha256"]
  for (_, value) in ids do
    unless Core.ModelInterface.validSha256 (← string value) do throw "invalid identity"
  let explorer ← get p "explorerIdentity"
  unless explorer == Json.null do
    let fields ← object explorer ["modelSemanticDigest", "mappingSha256", "implementationSha256"]
    for (_, value) in fields do
      unless Core.ModelInterface.validSha256 (← string value) do throw "invalid explorer identity"
  let command ← get p "command"
  let kind ← match command.getObjValAs? String "kind" with
    | .ok value => pure value
    | .error _ => throw "typed command required"
  let fields ← object command (if kind == "python-isolated" then
    ["kind", "executable", "script", "args"] else ["kind", "executable", "args"])
  unless kind == "native" || kind == "python-isolated" do throw "unsupported command kind"
  let boundedText := fun (value : Json) (allowEmpty : Bool) => do
    let arg ← string value
    if (!allowEmpty && arg.isEmpty) || arg.contains '\x00' || arg.toUTF8.size > 4096 then
      throw "invalid command argument"
    pure ()
  boundedText (← get fields "executable") false
  if kind == "python-isolated" then boundedText (← get fields "script") false
  let args ← array (← get fields "args")
  if args.length > 8 then throw "invalid command bound"
  for arg in args do
    let .obj values := arg | throw "typed argument required"
    let keys := values.toList.map Prod.fst
    unless keys == ["artifact"] || keys == ["literal"] do throw "unknown argument kind"
    boundedText (← get values.toList keys.head!) (keys == ["literal"])
  let artifacts ← array (← get p "artifacts")
  if artifacts.isEmpty || artifacts.length > 16384 then throw "invalid artifact count"
  artifacts.forM file
  let signature ← string (← get p "signature")
  unless ["exact-terminal/v1", "counter-count-delta/v1"].contains signature do
    throw "unsupported failure signature"
  let limits ← object (← get p "limits") ["attempts", "timeoutMs", "totalTimeoutMs", "outputBytes", "totalOutputBytes"]
  for (key, value) in limits do
    let n ← natural value
    let bound := if key == "attempts" then 4096 else if key == "outputBytes" then 32*1024*1024
      else if key == "totalOutputBytes" then 256*1024*1024 else 3600000
    if n == 0 || n > bound then throw "invalid execution limit"
  if (← natural (← get limits "totalOutputBytes")) ≤
      65536 + (← natural (← get limits "attempts")) * 1024 then
    throw "total output budget cannot reserve final reporting"
  let chains ← (← array (← get p "chains")).mapM fun j => do
    let c ← object j ["actor", "checkpoints"]
    let actor ← string (← get c "actor")
    let checkpoints ← (← array (← get c "checkpoints")).mapM string
    return { actor, checkpoints : Chain }
  let candidates ← (← array (← get p "candidates")).mapM fun j => do
    let c ← object j ["id", "inputRank", "schedule", "oracle", "provenance"]
    file (← get c "oracle")
    file (← get c "provenance")
    let s ← object (← get c "schedule") ["schema", "profile", "identity", "inputs", "steps"]
    unless (← string (← get s "schema")) == "mirrors.checkpoint-schedule/v1" &&
        (← string (← get s "profile")) == profile && (← get s "identity") == identity do
      throw "candidate identity/profile mismatch"
    let .obj _ := ← get s "inputs" | throw "inputs must be object"
    let steps ← (← array (← get s "steps")).mapM fun j => do
      let step ← object j ["actor", "checkpoint"]
      let actor ← string (← get step "actor")
      let checkpoint ← string (← get step "checkpoint")
      return { actor, checkpoint : Step }
    let id ← string (← get c "id")
    let inputRank ← natural (← get c "inputRank")
    return { id, inputRank, steps : Candidate }
  validate chains candidates (← string (← get p "baseline"))
  return (j, candidates)

def plan (candidates : List Candidate) : Json :=
  Json.mkObj [("schema", .str "mirrors.dpm-search-plan/v1"),
    ("scope", .str "admitted-catalog-only"),
    ("order", .arr ((ordered candidates).map fun c => Json.mkObj [
      ("id", .str c.id), ("cost", toJson (cost c))]).toArray)]

end Codec.Dpm
