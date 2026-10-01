import Shell.Client
import Shell.Apalache.SpecSource
import Shell.Mirror.Session
import Codec.StrictJson
import Core.ModelInterface.Sha256
import Shell.SharedTrace

/-! Remote capture through the existing bounded protocol. Returned paths are
receipt data, never local file references. Raw ITF JSON metadata is preserved. -/
namespace Shell.TraceCapture

structure Capture where
  request : Lean.Json
  replies : List String
  traces : List Lean.Json
  jobId : Option String := none
  transfer : Option Lean.Json := none

private def receive (t : Shell.Transport.Transport) :
    IO (Except String (String × Lean.Json × Codec.MirrorMessage)) := do
  match ← t.recv with
  | none => return .error "connection closed"
  | some line =>
    match Codec.StrictJson.parseString line with
    | .error error => return .error s!"bad json: {error}"
    | .ok json =>
      match Codec.decodeMirror json with
      | .error _ => return .error "bad mirror message"
      | .ok message => return .ok (line, json, message)

private def inlineTraces (json : Lean.Json) : Except String (List Lean.Json) := do
  let traces ← (json.getObjVal? "itfTraces").mapError (fun _ => "missing inline ITF traces")
  let traces ← traces.getArr?.mapError (fun _ => "invalid inline ITF traces")
  if traces.isEmpty then throw "remote capture requires nonempty inline ITF traces; server paths are not local files"
  if traces.size > 64 then throw "remote capture exceeds the 64-artifact limit"
  for trace in traces do
    match Shell.Mirror.parseItfTrace trace with
    | .error error => throw s!"invalid ITF trace: {error}"
    | .ok parsed =>
      if parsed.traceStates.isEmpty then throw "invalid ITF trace: empty state sequence"
  return traces.toList

private def cancelOwned (t : Shell.Transport.Transport) (jobId : String) : IO Unit := do
  try Shell.Client.sendMsg t (.cancelJob jobId)
  catch _ => pure ()

private def awaitTraceJob (t : Shell.Transport.Transport) (jobId : String)
    (request : Lean.Json) : Nat → List String → IO (Except String Capture)
  | 0, _ => pure (.error "async trace-generation poll budget exhausted")
  | remaining + 1, replies => do
    Shell.Client.sendMsg t (.awaitJob jobId (some 30))
    match ← receive t with
    | .error error => return .error error
    | .ok (line, json, message) =>
      let replies := replies ++ [line]
      match message with
      | .jobResult id outcome =>
        if id != jobId then return .error "async trace-generation job id mismatch"
        match outcome with
        | .genTraces _ =>
          let result := (json.getObjVal? "outcome").bind (·.getObjVal? "genTraces")
          match result.bind inlineTraces with
          | .error error => return .error error
          | .ok traces => return .ok { request, replies, traces, jobId := some jobId }
        | .validate _ => return .error "unexpected validation result for trace-generation job"
        | .infraError error => return .error error
      | .jobStatus id phase =>
        if id != jobId then return .error "async trace-generation job id mismatch"
        match phase with
        | .pending | .running => awaitTraceJob t jobId request remaining replies
        | .cancelled => return .error "async trace-generation job cancelled"
        | .unknown => return .error "async trace-generation job unknown or evicted"
        | .done | .failed => return .error "async trace-generation job ended without a result"
      | .registerError error | .protocolError error => return .error error
      | _ => return .error "unexpected message: expected trace-generation job result"

def run (t : Shell.Transport.Transport) (cfg : Codec.ApalacheConfig)
    (spec : Codec.SpecConfig) (traceConfig : Codec.TraceConfig)
    (asyncMode : Bool := false) (maxPolls : Nat := 120)
    (shared : Option Shell.SharedTrace.Mapping := none) : IO (Except String Capture) := do
  if asyncMode && shared.isSome then return .error "shared trace transfer requires synchronous generation"
  let message := if asyncMode then Codec.ClientMessage.registerGenTracesAsync cfg none (some spec) traceConfig
    else Codec.ClientMessage.registerGenTraces cfg (shared.map (·.destination)) (some spec) traceConfig
  let request := Codec.encodeClient message
  Shell.Client.sendMsg t message
  match ← receive t with
  | .error error => return .error error
  | .ok (line, json, reply) =>
    if asyncMode then
      match reply with
      | .jobAccepted jobId .genTraces =>
        if jobId.isEmpty then return .error "empty async trace-generation job id"
        let result ← try awaitTraceJob t jobId request maxPolls [line]
          catch error => pure (.error (toString error))
        match result with
        | .error _ => cancelOwned t jobId
        | .ok _ => pure ()
        return result
      | .registerError error | .protocolError error => return .error error
      | _ => return .error "unexpected message: expected trace-generation job_accepted"
    else
      match reply with
      | .genTracesDone result =>
        if result.itfTraces.isEmpty then
          if let some mapping := shared then
            -- numTraces controls Apalache's max-error setting. One
            -- counterexample can have multiple artifacts with different
            -- metadata; preserve all under the independent artifact cap.
            match ← Shell.SharedTrace.load mapping result.itfTracePaths 64 with
            | .error error => return .error error
            | .ok (traces, transfer) => return .ok {
                request, replies := [line], traces, transfer := some transfer }
        match inlineTraces json with
        | .error error => return .error error
        | .ok traces => return .ok { request, replies := [line], traces }
      | .registerError error | .protocolError error => return .error error
      | _ => return .error "unexpected message: expected gen_traces_done"

private partial def pathChain (path : System.FilePath) : List System.FilePath :=
  match path.parent with
  | none => [path]
  | some parent => pathChain parent ++ [path]

/-- Refuse existing outputs and all symlink prefixes before connecting. -/
def checkOutput (out : String) : IO (Except String System.FilePath) := do
  try
    if out.isEmpty then return .error "missing required --out"
    let path : System.FilePath := out
    let cwd ← IO.currentDir
    let absolute := (if path.isAbsolute then path else cwd / path).normalize
    if absolute.parent.isNone then return .error "filesystem root is not an output directory"
    for prefixPath in pathChain absolute do
      match ← prefixPath.symlinkMetadata.toBaseIO with
      | .ok metadata =>
        if prefixPath == absolute then return .error "output already exists"
        if metadata.type != .dir then return .error "output parent is not an ordinary directory"
      | .error (.noFileOrDirectory ..) =>
        if prefixPath != absolute then return .error "output parent does not exist"
      | .error error => return .error (toString error)
    return .ok absolute
  catch error => return .error (toString error)

private def jsonBytes (json : Lean.Json) : ByteArray := (json.compress ++ "\n").toUTF8

def publish (out : System.FilePath) (endpoint : Lean.Json)
    (spec : Codec.SpecConfig) (capture : Capture) : IO (Except String Unit) := do
  let sources := Lean.Json.mkObj [("sources", .arr (spec.sources.map Lean.Json.str).toArray)]
  let mut files : List (String × ByteArray) := [
    ("request.json", jsonBytes capture.request),
    ("replies.jsonl", (String.intercalate "\n" capture.replies ++ "\n").toUTF8),
    ("sources.json", jsonBytes sources)]
  for (trace, index) in capture.traces.zipIdx do
    files := files ++ [(s!"trace-{index}.itf.json", jsonBytes trace)]
  let hashes := files.map fun (path, bytes) => Lean.Json.mkObj [
    ("path", .str path), ("sha256", .str (Core.ModelInterface.Sha256.digestHex bytes))]
  let receipt := Lean.Json.mkObj [
    ("schema", .str "mirrors.remote-trace-capture/v1"),
    ("endpoint", endpoint), ("traceCount", .num capture.traces.length),
    ("jobId", capture.jobId.map Lean.Json.str |>.getD .null),
    ("transfer", capture.transfer.getD .null),
    ("files", .arr hashes.toArray)]
  files := files ++ [("capture.json", jsonBytes receipt)]
  try IO.FS.createDir out
  catch error => return .error s!"cannot reserve output directory: {error}"
  let mut owned : List System.FilePath := []
  try
    for (name, bytes) in files do
      let path := out / name
      owned := path :: owned
      IO.FS.writeBinFile path bytes
    return .ok ()
  catch error =>
    for path in owned do
      try IO.FS.removeFile path catch _ => pure ()
    try IO.FS.removeDir out catch _ => pure ()
    return .error s!"cannot publish trace capture: {error}"

end Shell.TraceCapture
