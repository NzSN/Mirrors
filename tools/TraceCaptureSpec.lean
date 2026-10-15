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

private def asyncStopTests : IO Unit := do
  let cfg : Codec.ApalacheConfig := {
    constInit := none, initPredicate := none, invariant := "Inv", lengthBound := 3,
    nextPredicate := none, paramVars := "parameters", specPath := "M.tla" }
  let spec : Codec.SpecConfig := { sources := ["---- MODULE M ----\n====\n"] }
  let tc : Codec.TraceConfig := { numTraces := 1, view := none }
  let encoded (message : Codec.MirrorMessage) := (Codec.encodeMirror message).compress
  let runCase (name : String) (reply : Option String) (want : String)
      (budget : Nat := 1) (cancel : Bool := false)
      (throwRecv : Bool := false) (throwCancel : Bool := false) : IO Unit := do
    let sent ← IO.mkRef ([] : List String)
    let received ← IO.mkRef (0 : Nat)
    let transport : Shell.Transport.Transport := {
      send := fun line => do
        sent.modify (· ++ [line])
        if throwCancel && line == (Codec.encodeClient (.cancelJob "owned")).compress then
          throw (IO.userError "secondary cancellation failure")
      recv := do
        let index ← received.get
        received.set (index + 1)
        if index == 0 then return some (encoded (.jobAccepted "owned" .genTraces))
        if throwRecv then throw (IO.userError "scripted receive failure")
        return if index == 1 then reply else none }
    let result ← Shell.TraceCapture.run transport cfg spec tc true budget
    match result with
    | .ok _ => throw (IO.userError s!"{name}: terminal failure accepted")
    | .error error =>
        unless error.contains want do throw (IO.userError s!"{name}: wrong diagnostic: {error}")
        if error.contains "secondary cancellation failure" then
          throw (IO.userError s!"{name}: cancellation replaced the primary diagnostic")
    let expected := [Codec.ClientMessage.registerGenTracesAsync cfg none (some spec) tc] ++
      (if budget == 0 then [] else [.awaitJob "owned" (some 30)]) ++
      (if cancel then [.cancelJob "owned"] else [])
    unless (← sent.get) == expected.map (fun message => (Codec.encodeClient message).compress) do
      throw (IO.userError s!"{name}: unexpected follow-up writes: {← sent.get}")
  let cases : List (String × Option String × String) := [
    ("wrong job", some (encoded (.jobStatus "other" .running)), "job id mismatch"),
    ("wrong result", some (encoded (.jobResult "owned" (.validate .valid))), "validation result"),
    ("protocol error", some (encoded (.protocolError "peer terminal")), "peer terminal"),
    ("register error", some (encoded (.registerError "peer rejected")), "peer rejected"),
    ("malformed JSON", some "{", "bad json"),
    ("malformed reply", some "{}", "bad mirror message"),
    ("EOF", none, "connection closed"),
    ("cancelled", some (encoded (.jobStatus "owned" .cancelled)), "cancelled"),
    ("unknown", some (encoded (.jobStatus "owned" .unknown)), "unknown or evicted"),
    ("done without result", some (encoded (.jobStatus "owned" .done)), "ended without a result"),
    ("failed without result", some (encoded (.jobStatus "owned" .failed)), "ended without a result"),
    ("infrastructure error", some (encoded (.jobResult "owned" (.infraError "backend failed"))), "backend failed")]
  for (name, reply, want) in cases do runCase name reply want
  runCase "throwing receive" none "scripted receive failure" 1 false true
  runCase "local poll budget" (some (encoded (.jobStatus "owned" .running))) "poll budget" 1 true
  runCase "zero poll budget" none "poll budget" 0 true
  runCase "cancel failure is secondary" (some (encoded (.jobStatus "owned" .pending)))
    "poll budget" 1 true false true

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
  asyncStopTests
  IO.println "TRACE CAPTURE SPEC GREEN"
  sharedTests
  return 0
