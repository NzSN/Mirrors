import Shell.Net.Http
import Shell.Apalache.Explorer
import Shell.Apalache.Runner
import Shell.Transport.Mock
import Shell.Mirror.Session
import Codec.Json
import Core.Value
import Lean.Data.Json

/-!
# t14 gate: explorer HTTP + JSON-RPC spike, transcript parity, and the
HourClock explorer end-to-end.

Three tiers:

1. **HTTP spike (design 9.2)**: the pure-Lean HTTP/1.1 client against a
   Lean mini-server on an ephemeral loopback port — JSON body
   round-trip with Content-Length, chunked transfer decoding, connect
   refusal to a dead port, and recv-timeout on a silent peer.
2. **Transcript parity (Phase 0)**: every recorded line of
   test/fixtures/explorer_transcripts.jsonl must round-trip through the
   request encoder (byte-identical) and the response decoder.
3. **Integration (APALACHE_MC only)**: a real explorer server, the
   register_explore_session flow, and the register_explore mirror loop,
   both over a mock transport, on HourClock.
-/

open Lean

abbrev Failures := IO.Ref (List String)

def check (fails : Failures) (name : String) (ok : Bool) (detail : String := "") : IO Unit := do
  if !ok then
    if detail.isEmpty then fails.modify (fun fs => fs ++ [name])
    else fails.modify (fun fs => fs ++ [s!"{name}: {detail}"])

/-- The explorer-variant HourClock (same as the Haskell suite's
test/specs/HourClock.tla, copied to test/fixtures/HourClock.tla):
apalache's JSON-RPC loadSpec runs the Snowcat type checker, which
needs @type annotations. -/
def loadHcSrc : IO String := do
  IO.FS.readFile "test/fixtures/HourClock.tla"

/-! ## 1. The HTTP spike -/

private def spikeUnused : Nat := 0

/-- HTTP spike against a python3 loopback peer: JSON echo with
Content-Length, chunked decoding, recv-timeout on a silent endpoint,
and connect refusal on a dead port. -/
def httpSpike (fails : Failures) : IO Unit := do
  let proc ← IO.Process.spawn
    { cmd := "python3", args := #["tools/http_test_server.py"],
      stdin := .null, stdout := .piped, stderr := .null }
  let outH := (proc.stdout : IO.FS.Handle)
  let portLine ← outH.getLine
  let portS := portLine.trim
  let port := portS.toNat?.getD 0
  check fails "http: server port" (port > 0) portS
  let body := "{\"jsonrpc\":\"2.0\",\"method\":\"health\",\"params\":[]}"
  -- (a) Content-Length echo of a JSON body
  match ← Shell.Net.Http.post port "/rpc" body (timeoutMs := 5000) with
  | .error e => check fails "http: content-length echo" false e
  | .ok resp => do
      check fails "http: content-length status" (resp.status == 200) (toString resp.status)
      check fails "http: content-length body" (resp.body == body) resp.body
  -- (b) chunked echo
  match ← Shell.Net.Http.post port "/chunked" body (timeoutMs := 5000) with
  | .error e => check fails "http: chunked decode" false e
  | .ok resp => check fails "http: chunked decode" (resp.body == body) resp.body
  -- (d) silent peer: recv timeout (bound 300 ms, peer waits 2 s)
  match ← Shell.Net.Http.post port "/silent" body (timeoutMs := 300) with
  | .ok _ => check fails "http: recv timeout" false "unexpected success"
  | .error _ => check fails "http: recv timeout" true
  -- (c) dead port: connect refused surfaces as an error
  let dead ← Shell.Apalache.Explorer.freePort
  match ← Shell.Net.Http.post dead "/rpc" body (timeoutMs := 3000) with
  | .ok _ => check fails "http: dead port" false "unexpected success"
  | .error _ => check fails "http: dead port" true
  try proc.kill catch _ => pure ()
  let _ ← proc.wait

/-! ## 2. Transcript parity (Phase 0 recordings) -/

private def transcriptParity (fails : Failures) : IO Unit := do
  let raw ← IO.FS.readFile "test/fixtures/explorer_transcripts.jsonl"
  let mut n := 0
  for line in (raw.splitOn "\n").filter (fun l => !l.isEmpty) do
    n := n + 1
    match Lean.Json.parse line with
    | .error e => check fails s!"transcript[{n}]: line json" false e
    | .ok lj =>
        let method := match lj.getObjVal? "method" with
          | .ok (.str m) => m | _ => "?"
        let reqS := match lj.getObjVal? "request" with
          | .ok (.str s) => s | _ => ""
        let respS := match lj.getObjVal? "response" with
          | .ok (.str s) => s | _ => ""
        match Lean.Json.parse reqS with
        | .error e => check fails s!"transcript[{n}]: request json" false e
        | .ok rj =>
            let id := match rj.getObjVal? "id" with
              | .ok (.num k) => k.mantissa.toNat | _ => 0
            let params := match rj.getObjVal? "params" with
              | .ok p => p | _ => .null
            let rebuilt := Lean.Json.compress
              (Shell.Apalache.Explorer.rpcRequestJson method params id)
            check fails s!"transcript[{n}]: request bytes ({method})" (rebuilt == reqS)
              s!"rebuilt {rebuilt}"
        match Lean.Json.parse respS with
        | .error e => check fails s!"transcript[{n}]: response json" false e
        | .ok pj =>
            match Shell.Apalache.Explorer.decodeRpcResponse pj with
            | .ok _ => check fails s!"transcript[{n}]: response decode ({method})" true
            | .error err =>
                check fails s!"transcript[{n}]: response decode ({method})" false
                  (Shell.Apalache.Explorer.rpcErrorText err)
  check fails "transcripts: nonempty" (n > 0) (toString n)

/-! ## 3. Integration: HourClock explorer end-to-end (APALACHE_MC only) -/

private def sendClient (t : Shell.Transport.Transport) (m : Codec.ClientMessage) :
    IO Unit :=
  t.send (Lean.Json.compress (Codec.encodeClient m))

private def readMirror (t : Shell.Transport.Transport) :
    IO (Except String Codec.MirrorMessage) := do
  match ← t.recv with
  | none => return .error "transport closed"
  | some line =>
      match Lean.Json.parse line with
      | .error e => return .error e
      | .ok j => return (Codec.decodeMirror j).mapError (fun e => e.msg)

private def expectMirror (fails : Failures) (t : Shell.Transport.Transport)
    (name : String) (p : Codec.MirrorMessage → Bool) : IO Bool := do
  match ← readMirror t with
  | .error e => check fails name false e; return false
  | .ok m =>
      if p m then return true
      else
        check fails name false (Lean.Json.compress (Codec.encodeMirror m))
        return false

private def integrationSession (fails : Failures) : IO Unit := do
  let (server, client) ← Shell.Transport.mockPair
  let _task ← IO.asTask (prio := Task.Priority.dedicated)
    (do let src ← loadHcSrc; Shell.Apalache.exploreSessionFlow server [src] ["Inv"] ["Export"])
  let okR ← expectMirror fails client "session: explorerReady"
    (fun m => match m with
      | .explorerReady i n s => i >= 1 && n >= 1 && s >= 1
      | _ => false)
  if okR then
    sendClient client .exploreQueryState
    let okQ ← expectMirror fails client "session: exploreState"
      (fun m => match m with
        | .exploreState st => st.length > 0
        | _ => false)
    check fails "session: state has vars" okQ
    sendClient client (.exploreAssumeTransition 0)
    let _ ← expectMirror fails client "session: transition status"
      (fun m => match m with
        | .exploreTransitionStatus s => s == "ENABLED" || s == "DISABLED" || s == "UNKNOWN"
        | _ => false)
    sendClient client .exploreNextStep
    let _ ← expectMirror fails client "session: step done"
      (fun m => match m with
        | .exploreStepDone k => k >= 1
        | _ => false)
    sendClient client (.exploreCheckInvariant 0)
    let _ ← expectMirror fails client "session: invariant status"
      (fun m => match m with
        | .exploreInvariantStatus s => s == "SATISFIED" || s == "VIOLATED"
        | _ => false)
    sendClient client .exploreDone
    let _ ← expectMirror fails client "session: done"
      (fun m => match m with | .exploreSessionDone => true | _ => false)

private def readStateMsg (fails : Failures) (t : Shell.Transport.Transport)
    (name : String) : IO (Option ValueMap) := do
  match ← readMirror t with
  | .error e => check fails name false e; return none
  | .ok m =>
      match m with
      | .initialState _ st => return some st
      | .nextStep _ st => return some st
      | other =>
          check fails name false (Lean.Json.compress (Codec.encodeMirror other))
          return none

private def integrationExplore (fails : Failures) : IO Unit := do
  let (server, client) ← Shell.Transport.mockPair
  let _task ← IO.asTask (prio := Task.Priority.dedicated)
    (do let src ← loadHcSrc; Shell.Apalache.exploreFlow server [src] ["Inv"] [] 2)
  let _ ← expectMirror fails client "explore: spec validated"
    (fun m => match m with | .specValidated _ => true | _ => false)
  match ← readStateMsg fails client "explore: initial state" with
  | none => pure ()
  | some st0 =>
      sendClient client (.reportState st0)
      let _ ← expectMirror fails client "explore: step ok 0"
        (fun m => match m with | .stepOk => true | _ => false)
      match ← readStateMsg fails client "explore: next state" with
      | none => pure ()
      | some st1 =>
          sendClient client (.reportState st1)
          let _ ← expectMirror fails client "explore: step ok 1"
            (fun m => match m with | .stepOk => true | _ => false)
          let _ ← expectMirror fails client "explore: all steps done"
            (fun m => match m with | .allStepsDone => true | _ => false)

def main : IO Unit := do
  let fails ← IO.mkRef ([] : List String)
  httpSpike fails
  transcriptParity fails
  let apalache? ← IO.getEnv "APALACHE_MC"
  match apalache? with
  | none => IO.println "explorer integration: skipped (APALACHE_MC not set)"
  | some _ =>
      integrationSession fails
      integrationExplore fails
  let fs ← fails.get
  if fs.isEmpty then
    IO.println "EXPLORER SPEC: all green"
  else
    IO.println s!"EXPLORER SPEC: {fs.length} failures"
    for f in fs do
      IO.println s!"  FAIL {f}"