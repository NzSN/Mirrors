import Shell.Cli

private def sharedTests : IO Unit := do
  let mapping : Shell.SharedTrace.Mapping := {
    serverRoot := "C:/Exports", localRoot := "/unused", leaf := "capture-123" }
  unless (mapping.filename "C:\\Exports\\capture-123\\oracle.itf.json") == .ok "oracle.itf.json" do
    throw (IO.userError "Windows mapping did not preserve its artifact name")
  for path in ["C:/Exports/capture-124/oracle.itf.json", "C:/Exports/capture-123/../oracle.itf.json",
      "C:/Exports/capture-123/sub/oracle.itf.json", "C:/Exports/capture-123/.secret.itf.json",
      "C:/Exports/capture-123/oracle.txt"] do
    if (mapping.filename path).isOk then throw (IO.userError "unsafe shared reply path admitted")
  for root in ["relative", "C:/Exports/../other", "C:/Exports?", ""] do
    if (Shell.SharedTrace.serverRoot root).isOk then throw (IO.userError "unsafe server root admitted")
  let cwd ← IO.currentDir
  let root := cwd / ".lake" / "build" / s!"shared-trace-test-{← IO.rand 0 1000000000}"
  IO.FS.createDir root
  try
    let directory := root / "capture-123"
    Shell.SharedTrace.reserveDestination root (some directory.toString)
    let existingRejected ← try
        Shell.SharedTrace.reserveDestination root (some directory.toString)
        pure false
      catch _ => pure true
    unless existingRejected do throw (IO.userError "existing server destination accepted")
    let escapeRejected ← try
        Shell.SharedTrace.reserveDestination root (some (root / ".." / "capture-123").toString)
        pure false
      catch _ => pure true
    unless escapeRejected do throw (IO.userError "escaping server destination accepted")
    let padding := String.ofList (List.replicate 80000 'x')
    let json := Lean.Json.mkObj [
      ("#meta", Lean.Json.mkObj [("padding", .str padding)]),
      ("vars", .arr #[.str "x"]), ("params", .arr #[]),
      ("states", .arr #[Lean.Json.mkObj [("x", .num 1)]])]
    IO.FS.writeFile (directory / "oracle.itf.json") json.compress
    let mapping := { mapping with localRoot := root }
    let path := mapping.destination ++ "/oracle.itf.json"
    match ← Shell.SharedTrace.load mapping [path] 1 with
    | .error e => throw (IO.userError e)
    | .ok (traces, receipt) =>
        unless traces == [json] && (receipt.getObjVal? "artifacts").isOk do
          throw (IO.userError "large shared artifact metadata or receipt changed")
    if (← Shell.SharedTrace.load mapping [path, path] 2).isOk then
      throw (IO.userError "duplicate shared artifacts accepted")
    if (← Shell.SharedTrace.load mapping [path] 0).isOk then
      throw (IO.userError "shared artifact count bound ignored")
    IO.FS.writeFile (directory / "oracle1.itf.json")
      (Lean.Json.mkObj [
        ("#meta", Lean.Json.mkObj [("padding", .str padding), ("description", .str "different timestamp")]),
        ("vars", .arr #[.str "x"]), ("params", .arr #[]),
        ("states", .arr #[Lean.Json.mkObj [("x", .num 1)]])]).compress
    let reply := Codec.MirrorMessage.genTracesDone {
      itfTracePaths := [path, mapping.destination ++ "/oracle1.itf.json"], itfTraces := [] }
    let transport : Shell.Transport.Transport := {
      send := fun _ => pure ()
      recv := pure (some (Codec.encodeMirror reply).compress) }
    let cfg : Codec.ApalacheConfig := {
      constInit := none, initPredicate := none, invariant := "", lengthBound := 1,
      nextPredicate := none, paramVars := "", specPath := "M.tla" }
    let asyncDestination := Codec.ClientMessage.registerGenTracesAsync cfg
      (some "C:/Exports/capture-123") none { numTraces := 1, view := none }
    unless Shell.SharedTrace.asyncDestinationRequested (Codec.encodeClient asyncDestination).compress do
      throw (IO.userError "async destination admission was not rejected")
    let asyncInline := Codec.ClientMessage.registerGenTracesAsync cfg
      none none { numTraces := 1, view := none }
    if Shell.SharedTrace.asyncDestinationRequested (Codec.encodeClient asyncInline).compress then
      throw (IO.userError "ordinary async inline request was rejected")
    match ← Shell.TraceCapture.run transport cfg { sources := [] }
        { numTraces := 1, view := none } false 1 (some mapping) with
    | .error e => throw (IO.userError e)
    | .ok capture => unless capture.traces.length == 2 do
        throw (IO.userError "one counterexample's distinct metadata artifacts were lost")
    IO.FS.createDir (directory / "directory.itf.json")
    if (← Shell.SharedTrace.load mapping [mapping.destination ++ "/directory.itf.json"] 1).isOk then
      throw (IO.userError "nonregular artifact accepted")
    if !System.Platform.isWindows then
      let link := directory / "link.itf.json"
      let linked ← IO.Process.output { cmd := "ln", args := #["-s", (directory / "oracle.itf.json").toString, link.toString] }
      if linked.exitCode != 0 then throw (IO.userError "symlink fixture creation failed")
      if (← Shell.SharedTrace.load mapping [mapping.destination ++ "/link.itf.json"] 1).isOk then
        throw (IO.userError "symlink artifact accepted")
    IO.FS.writeFile (directory / "oracle.itf.json") "{\"vars\":[],\"vars\":[]}"
    if (← Shell.SharedTrace.load mapping [path] 1).isOk then
      throw (IO.userError "duplicate JSON fields accepted from shared artifact")
  finally IO.FS.removeDirAll root
  IO.println "SHARED TRACE SPEC GREEN"

/-! Pure option admission and owned-job correlation regressions. The Python
CLI suite separately exercises sockets, source capture, and publication. -/
def main : IO UInt32 := do
  let base := ["--host", "127.0.0.1", "--port", "8999", "--spec", "M.tla", "--out", "capture"]
  let valid := parseTraceGenOpts (base ++ ["--num-traces", "2", "--param-var", "parameters"])
  match valid with
  | .error error => IO.eprintln error; return 1
  | .ok opts =>
    if opts.numTraces != 2 || opts.paramVar != "parameters" || opts.out != "capture" then
      IO.eprintln "trace options changed values"; return 1
  for extra in [["--num-traces", "0"], ["--num-traces", "65"], ["--out", "again"],
      ["--max-polls", "1"], ["--async", "--max-polls", "0"], ["--bound", "0"], ["--unknown"]] do
    if (parseTraceGenOpts (base ++ extra)).isOk then
      IO.eprintln s!"invalid trace options accepted: {extra}"; return 1
  for extra in [["--shared-server-root", "C:/Exports"],
      ["--shared-server-root", "C:/Exports", "--shared-local-root", "/tmp"]] do
    if (parseTraceGenOpts (base ++ extra)).isOk then
      IO.eprintln "shared options accepted without paired roots and pinned mTLS"; return 1
  let secure := base ++ ["--tls", "--cert", "c", "--key", "k", "--ca", "a", "--pin", String.ofList (List.replicate 64 '1'),
    "--shared-server-root", "C:/Exports", "--shared-local-root", "/tmp"]
  unless (parseTraceGenOpts secure).isOk do IO.eprintln "valid shared options rejected"; return 1
  if (parseTraceGenOpts (secure ++ ["--async"])).isOk then
    IO.eprintln "async shared mode admitted"; return 1
  let sent ← IO.mkRef ([] : List String)
  let replies ← IO.mkRef [
    "{\"proto_step\":\"job_accepted\",\"jobId\":\"owned\",\"kind\":\"gen_traces\"}",
    "{\"proto_step\":\"job_status\",\"jobId\":\"other\",\"phase\":\"running\"}"]
  let transport : Shell.Transport.Transport := {
    send := fun line => sent.modify (· ++ [line])
    recv := do
      let queue ← replies.get
      match queue with
      | [] => pure none
      | head :: tail => replies.set tail; pure (some head) }
  let cfg : Codec.ApalacheConfig := {
    constInit := none, initPredicate := none, invariant := "Inv", lengthBound := 3,
    nextPredicate := none, paramVars := "parameters", specPath := "M.tla" }
  let result ← Shell.TraceCapture.run transport cfg { sources := ["---- MODULE M ----\n====\n"] }
    { numTraces := 1, view := none } true 2
  match result with
  | .ok _ => IO.eprintln "wrong job correlation accepted"; return 1
  | .error error =>
    if error != "async trace-generation job id mismatch" then IO.eprintln error; return 1
  let messages := (← sent.get).filterMap fun line =>
    (Lean.Json.parse line).toOption.bind fun json => (json.getObjValAs? String "proto_step").toOption
  if messages != ["register_trace_gen_async", "await_job", "cancel_job"] then
    IO.eprintln s!"owned-job cleanup messages differ: {messages}"; return 1
  IO.println "TRACE CAPTURE SPEC GREEN"
  sharedTests
  return 0
