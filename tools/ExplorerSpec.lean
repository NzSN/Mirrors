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

Four tiers:

1. **HTTP spike (design 9.2)**: the pure-Lean HTTP/1.1 client against a
   Lean mini-server on an ephemeral loopback port — JSON body
   round-trip with Content-Length, chunked transfer decoding, connect
   refusal to a dead port, and recv-timeout on a silent peer.
2. **Transcript parity (Phase 0)**: every recorded line of
   test/fixtures/explorer_transcripts.jsonl must round-trip through the
   request encoder (byte-identical) and the response decoder.
3. **Scripted RPC regressions**: all invariant IDs, rejected/unknown assumptions
   and checks, and ambiguous mutation failures against a fake loopback peer.
4. **Integration (APALACHE_MC only)**: a real explorer server, the
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

private def chunkRegressions (fails : Failures) : IO Unit := do
  let bytes := "汉".toUTF8
  let split := "1\r\n".toUTF8 |>.append (bytes.extract 0 1)
    |>.append "\r\n2\r\n".toUTF8 |>.append (bytes.extract 1 3)
    |>.append "\r\n0\r\n\r\n".toUTF8
  check fails "chunked: Unicode crosses chunk boundaries"
    (Shell.Net.Http.decodeChunked split == .ok "汉")
  check fails "chunked: invalid UTF-8 rejected"
    (!(Shell.Net.Http.decodeChunked ("1\r\n".toUTF8 |>.append (bytes.extract 0 1)
      |>.append "\r\n0\r\n\r\n".toUTF8)).isOk)
  for raw in ["1\r\naXX0\r\n\r\n", "\r\n\r\n", "z\r\n", "0\r\nbad-trailer\r\n\r\n"] do
    check fails "chunked: malformed framing rejected" (!(Shell.Net.Http.decodeChunked raw.toUTF8).isOk)
  let framed := "6;fixture=yes\r\n\r\n0\r\nx\r\n0\r\nX-Fixture: yes\r\n\r\n".toUTF8
  check fails "chunked: terminator-like data and trailers"
    (Shell.Net.Http.decodeChunked framed == .ok "\r\n0\r\nx")
  for count in [:framed.size] do
    check fails "chunked: incomplete prefixes need more bytes"
      (match Shell.Net.Http.parseChunkedPrefix (framed.extract 0 count) with
       | .ok none => true
       | _ => false)
  let following := "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n".toUTF8
  check fails "chunked: following response bytes preserved"
    (match Shell.Net.Http.parseChunkedPrefix (framed.append following) with
     | .ok (some (payload, consumed)) =>
         payload == "\r\n0\r\nx".toUTF8 && consumed == framed.size
     | _ => false)

private def httpRegressions (fails : Failures) (port : Nat) : IO Unit := do
  let body := "{\"value\":\"汉🙂\"}"
  match ← Shell.Net.Http.post port "/rpc" body with
  | .error e => check fails "http: Unicode one-shot" false e
  | .ok response => check fails "http: Unicode one-shot" (response.body == body) response.body
  match ← Shell.Net.Http.openConn port 3000 with
  | .error e => check fails "http: Unicode keep-alive connect" false e
  | .ok conn =>
      try
        for text in [body, "{\"value\":\"second\"}"] do
          match ← Shell.Net.Http.postKa conn port "/rpc" text with
          | .error e => check fails "http: Unicode keep-alive framing" false e
          | .ok response =>
              check fails "http: Unicode keep-alive framing" (response.body == text) response.body
        match ← Shell.Net.Http.postKa conn port "/chunked-split" body with
        | .error e => check fails "http: split chunk terminator" false e
        | .ok response => check fails "http: split chunk terminator" (response.body == body) response.body
        match ← Shell.Net.Http.postKa conn port "/rpc" body with
        | .error e => check fails "http: request after chunked response" false e
        | .ok response => check fails "http: request after chunked response" (response.body == body) response.body
      finally Shell.Net.Http.closeConn conn
  let tasks ← (List.range 8).mapM fun worker =>
    IO.asTask (prio := Task.Priority.dedicated) do
      let .ok conn ← Shell.Net.Http.openConn port 15000
        | throw (IO.userError "parallel HTTP connection failed")
      let text := String.ofList (List.replicate 24000 (Char.ofNat (65 + worker)))
      let mut mismatches := 0
      try
        for iteration in [:64] do
          let response ← if iteration % 2 == 0 then
            Shell.Net.Http.post port "/race" text (timeoutMs := 15000)
          else Shell.Net.Http.postKa conn port "/race" text
          match response with
          | .ok response => if response.body != text then mismatches := mismatches + 1
          | .error _ => mismatches := mismatches + 1
      finally Shell.Net.Http.closeConn conn
      return mismatches
  for task in tasks do
    match ← IO.wait task with
    | .ok count => check fails "http: concurrent response isolation" (count == 0) (toString count)
    | .error e => check fails "http: concurrent response isolation" false (toString e)

/-- HTTP spike against a python3 loopback peer: JSON echo with
Content-Length, chunked decoding, recv-timeout on a silent endpoint,
and connect refusal on a dead port. -/
def httpSpike (fails : Failures) : IO Unit := do
  -- t30: python3 on windows-dev is the useless WindowsApps stub;
  -- use python there
  let py := if System.Platform.isWindows then "python" else "python3"
  let proc ← IO.Process.spawn
    { cmd := py, args := #["tools/http_test_server.py"],
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
  httpRegressions fails port
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

/-! ## 3. Scripted explorer decision and retry regressions -/

/-- Scripted RPC fixtures exercise the production flow without a model checker. -/
private def withRpcFixture (mode : String)
    (act : Shell.Apalache.Explorer.RpcClient → String → IO Unit) : IO Unit := do
  let dir := ".lake/tmp/explorer-logic"
  IO.FS.createDirAll dir
  let audit := dir ++ "/" ++ mode ++ ".jsonl"
  IO.FS.writeFile audit ""
  let py := if System.Platform.isWindows then "python" else "python3"
  let child ← IO.Process.spawn
    { cmd := py, args := #["tools/explorer_test_server.py", mode, audit],
      stdin := .piped, stdout := .piped, stderr := .inherit }
  let client ← Shell.Apalache.Explorer.newRpcClient
    ((← child.stdout.getLine).trimAscii.toString.toNat?.getD 0)
  try act client audit
  finally
    if let some conn ← client.conn.get then Shell.Net.Http.closeConn conn
    try child.kill catch _ => pure ()
    let _ ← child.wait
    pure ()

private def rpcRequests (path : String) : IO (List Json) := do
  let lines := (← IO.FS.readFile path).splitOn "\n" |>.filter (!·.isEmpty)
  lines.mapM fun line => match Json.parse line with
    | .ok json => pure json
    | .error error => throw (IO.userError error)

private def methodIs (name : String) (request : Json) : Bool :=
  request.getObjValAs? String "method" == .ok name

private def parameterNat (key : String) (request : Json) : Nat :=
  ((request.getObjVal? "params").bind (·.getObjValAs? Nat key)).toOption.getD 9999

private def strictExplorerRegressions (fails : Failures) : IO Unit := do
  for interactive in [false, true] do
    for report in [
        "{\"proto_step\":\"report_state\",\"state\":{\"x\":999,\"x\":1}}",
        "{\"proto_step\":\"report_state\",\"state\":{\"x\":999,\"\\u0078\":1}}",
        "{\"proto_step\":\"private-input-value\"}",
        "{\"private-input-value\":",
        "{\"proto_step\":\"report_state\",\"state\":{\"x\":1e-10000000000}}",
        "{\"proto_step\":\"report_state\",\"state\":{\"x\":\"\\ud800\"}}",
        "{\"proto_step\":\"report_state\",\"state\":{\"x\":1},\"ignored\":" ++
          String.ofList (List.replicate 129 '[') ++ "0" ++
          String.ofList (List.replicate 129 ']') ++ "}"] do
      withRpcFixture "clean" fun client audit => do
        let report := if interactive then report.replace "report_state" "explore_assume_state"
          else report
        let pending ← IO.mkRef [report]
        let replies ← IO.mkRef ([] : List Json)
        let transport : Shell.Transport.Transport := {
          scope := .remote
          recv := pending.modifyGet fun xs => (xs.head?, xs.drop 1)
          send := fun line => do
            let .ok json := Json.parse line | throw (IO.userError "bad mirror JSON")
            replies.modify (· ++ [json]) }
        if interactive then
          Shell.Apalache.exploreSessionFlowWithClient transport client ["fixture"] [] []
        else Shell.Apalache.exploreFlowWithClient transport client ["fixture"] [] [] 1
        let actual ← replies.get
        let expected := if interactive then ["explorer_ready", "protocol_error"]
          else ["spec_validated", "initial_state", "protocol_error"]
        check fails "explorer: malformed report receives only bounded error"
          (actual.map (fun j => (j.getObjValAs? String "proto_step").toOption.getD "") ==
            expected &&
           actual.getLast?.any (fun j => j.getObjValAs? String "error" ==
             .ok Shell.Mirror.invalidClientMessageError))
          (String.intercalate "\n" (actual.map Json.compress))
        let requests ← rpcRequests audit
        check fails "explorer: malformed report does not assume state or check invariants"
          (!(requests.any (methodIs "assumeState")) &&
           !(requests.any (methodIs "checkInvariant")))

private def rpcCleanupRegressions (fails : Failures) : IO Unit := do
  withRpcFixture "clean" fun peer _ => do
    for throws in [false, true] do
      let saved ← IO.mkRef (none : Option Shell.Apalache.Explorer.RpcClient)
      try
        Shell.Apalache.Explorer.withRpcClient peer.port fun client => do
          saved.set (some client)
          let result ← Shell.Apalache.Explorer.health client
          check fails "RPC scope: health succeeds" result.isOk
          if throws then throw (IO.userError "fixture scope failure")
      catch _ => check fails "RPC scope: expected exception" throws
      let some client ← saved.get | throw (IO.userError "client was not saved")
      check fails "RPC scope: connection cleared on success and exception"
        (← client.conn.get).isNone
      Shell.Apalache.Explorer.closeRpcClient client
    -- EOF framing may already close a connection before its owner finalizes it.
    let .ok old ← Shell.Net.Http.openConn peer.port 1000
      | throw (IO.userError "fixture connection failed")
    Shell.Net.Http.closeConn old
    let .ok live ← Shell.Net.Http.openConn peer.port 1000
      | throw (IO.userError "replacement connection failed")
    try
      Shell.Net.Http.closeConn old
      let closedResult ← Shell.Net.Http.postKa old peer.port "/rpc" "{}"
      check fails "HTTP: closed connection is not reused" (!closedResult.isOk)
      let reply ← Shell.Net.Http.postKa live peer.port "/rpc"
        "{\"id\":1,\"method\":\"health\",\"params\":[]}"
      check fails "HTTP: repeated close preserves replacement descriptor" reply.isOk
    finally Shell.Net.Http.closeConn live

private def automaticExplorerRegressions (fails : Failures) : IO Unit := do
  let first := ["spec_validated", "initial_state"]
  let second := first ++ ["step_ok", "next_step"]
  for (mode, steps, wanted) in [
      ("clean", 2, second ++ ["step_ok", "all_steps_done"]),
      ("later-violated", 1, first ++ ["step_mismatch"]),
      ("unknown", 1, first ++ ["protocol_error"]),
      ("rpc-error", 1, first ++ ["protocol_error"]),
      ("disabled-state", 1, first ++ ["protocol_error"]),
      ("unknown-state", 1, first ++ ["protocol_error"]),
      ("disabled-init", 1, ["protocol_error"]),
      ("unknown-init", 1, ["protocol_error"]),
      ("unknown-next", 2, first ++ ["step_ok", "protocol_error"]),
      ("action-violated", 2, second ++ ["step_mismatch"])] do
    withRpcFixture mode fun client audit => do
      let report := (Codec.encodeClient (.reportState [("x", .vint 1)])).compress
      let pending ← IO.mkRef [report, report]
      let tags ← IO.mkRef ([] : List String)
      let transport : Shell.Transport.Transport := {
        scope := .remote
        recv := do
          match ← pending.get with
          | [] => return none
          | first :: rest => pending.set rest; return some first
        send := fun line => do
          let .ok json := Json.parse line | throw (IO.userError "bad mirror JSON")
          let .ok tag := json.getObjValAs? String "proto_step"
            | throw (IO.userError "missing mirror tag")
          tags.modify (· ++ [tag]) }
      Shell.Apalache.exploreFlowWithClient transport client ["scripted fixture"] ["InvA", "InvB"] [] steps
      let actual ← tags.get
      check fails s!"automatic explorer: {mode}" (actual == wanted) (reprStr actual)
      let requests ← rpcRequests audit
      if mode == "clean" then
        check fails "automatic explorer: all backend invariant IDs checked"
          ((requests.filter (methodIs "checkInvariant")).map (parameterNat "invariantId") == [3, 7, 3, 7, 11])
        check fails "automatic explorer: backend transition IDs used"
          ((requests.filter (methodIs "assumeTransition")).map (parameterNat "transitionId") == [5, 9])
        check fails "automatic explorer: state and action invariant kinds"
          ((requests.filter (methodIs "checkInvariant")).map (fun request =>
            ((request.getObjVal? "params").bind (·.getObjValAs? String "kind")).toOption) ==
            [some "STATE", some "STATE", some "STATE", some "STATE", some "ACTION"])
      if mode == "later-violated" then
        check fails "automatic explorer: second invariant checked"
          ((requests.filter (methodIs "checkInvariant")).map (parameterNat "invariantId") == [3, 7])
      if mode == "disabled-init" || mode == "unknown-init" then
        check fails "automatic explorer: rejected initializer does not advance"
          ((requests.filter (methodIs "nextStep")).isEmpty)
      if mode == "disabled-state" || mode == "unknown-state" then
        check fails "automatic explorer: rejected assumption does not check invariants"
          ((requests.filter (methodIs "checkInvariant")).isEmpty)
  withRpcFixture "drop-mutation" fun client audit => do
    let result ← Shell.Apalache.Explorer.nextStep client "fixture"
    check fails "RPC: ambiguous mutation failure is returned" (!result.isOk)
    let state ← Shell.Apalache.Explorer.rpcCall client "query" (.mkObj [])
    check fails "RPC: lost-response mutation applied exactly once"
      ((state.toOption.bind fun json => (json.getObjValAs? Nat "appliedSteps").toOption) == some 1)
    let requests ← rpcRequests audit
    check fails "RPC: mutation is not retried"
      ((requests.filter (methodIs "nextStep")).length == 1)
  withRpcFixture "drop-health" fun client audit => do
    let result ← Shell.Apalache.Explorer.health client
    check fails "RPC: read-only retry recovers" result.isOk
    let requests ← rpcRequests audit
    check fails "RPC: health retried exactly once"
      ((requests.filter (methodIs "health")).length == 2)

/-! ## 4. Integration: HourClock explorer end-to-end (APALACHE_MC only) -/

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

def main (args : List String) : IO UInt32 := do
  let fails ← IO.mkRef ([] : List String)
  if args == ["--assertion-failure-control"] then
    check fails "deliberate assertion failure control" false
  else
    chunkRegressions fails
    httpSpike fails
    transcriptParity fails
    strictExplorerRegressions fails
    rpcCleanupRegressions fails
    automaticExplorerRegressions fails
    let control ← IO.Process.output {
      cmd := (← IO.appPath).toString, args := #["--assertion-failure-control"] }
    check fails "runner: failed assertion exits nonzero"
      (control.exitCode == 1 && control.stdout.contains "deliberate assertion failure control")
    let apalache? ← IO.getEnv "APALACHE_MC"
    match apalache? with
    | none => IO.println "explorer integration: skipped (APALACHE_MC not set)"
    | some _ =>
        integrationSession fails
        integrationExplore fails
  let fs ← fails.get
  if fs.isEmpty then
    IO.println "EXPLORER SPEC: all green"
    return 0
  else
    IO.println s!"EXPLORER SPEC: {fs.length} failures"
    for f in fs do
      IO.println s!"  FAIL {f}"
    return 1
