import Shell.Cli
import Shell.Transport.Tcp
import Shell.Transport.Tls
import Shell.Jobs.Store
import Codec.Json
import Lean

/-!
# t31 async live gate — REAL async flows over live servers

Spawns the actual `mirror` binary in `--serve` (plain TCP) and
`--server --tls` (mTLS) modes and drives the async job protocol over
real connections against real apalache (`APALACHE_MC`-gated; skips
itself otherwise):

(a) register_validate_async DeterministicCounter bound 3 →
    job_accepted → await_job → job_result VALID, congruent with the
    sync register_validate reply on a second connection (§6.4 outcome
    congruence, empirical);
(b) register_gen_traces_async Counter → await → job_result with
    non-empty generated traces;
(c) cancel: long trace-gen accepted, cancel_job → jobCancelled phase;
(d) query_job on a bogus id → jobUnknown;
(e) two concurrent jobs on ONE connection plus a job on a SECOND
    connection concurrently (the point of the async server mode);
(f) the mTLS variant of (a).
-/

abbrev Failures := IO.Ref (List String)

def checkA (fails : Failures) (name : String) (ok : Bool) (detail : String := "") :
    IO Unit := do
  if !ok then
    if detail.isEmpty then fails.modify (· ++ [name])
    else fails.modify (· ++ [s!"{name}: {detail}"])

def mirrorBin : String :=
  ".lake/build/bin/mirror" ++ (if System.Platform.isWindows then ".exe" else "")

/-! ## client helpers -/

def csend (c : Shell.Transport.Transport) (m : Codec.ClientMessage) : IO Unit :=
  c.send (toString (Lean.Json.compress (Codec.encodeClient m)))

def crecv (c : Shell.Transport.Transport) : IO (Except String Codec.MirrorMessage) := do
  let some l ← c.recv | return .error "connection closed"
  match Lean.Json.parse l with
  | .error e => return .error e
  | .ok j => pure ((Codec.decodeMirror j).mapError (fun (e : Codec.DecodeError) => e.msg))

def expectAccepted (c : Shell.Transport.Transport) : IO (Except String String) := do
  match ← crecv c with
  | .error e => return .error s!"recv: {e}"
  | .ok (.jobAccepted jid _) => return .ok jid
  | .ok m => return .error s!"expected job_accepted, got {repr m}"

def awaitValid (c : Shell.Transport.Transport) (jid : String) :
    IO (Except String Codec.ValidateResult) := do
  csend c (.awaitJob jid none)
  match ← crecv c with
  | .error e => return .error e
  | .ok (.jobResult _ (.validate v)) => return .ok v
  | .ok m => return .error s!"expected job_result(validate), got {repr m}"

/-- Poll-connect until the server is listening (max ~5s). -/
partial def waitServer (host : String) (port : Nat) (tries : Nat) :
    IO (Except String Shell.Transport.Transport) := do
  match ← Shell.Transport.Tcp.connectTcp host port with
  | .ok t => return .ok t
  | .error e =>
      if tries == 0 then return .error s!"server never came up: {e}"
      else do
        IO.sleep 200
        waitServer host port (tries - 1)

/-! ## specs under test -/

def dcCfg : Codec.ApalacheConfig where
  constInit := none
  initPredicate := none
  invariant := ""
  lengthBound := 3
  nextPredicate := none
  paramVars := ""
  specPath := "test/specs/DeterministicCounter.tla"

def counterCfg : Codec.ApalacheConfig where
  constInit := some "CInit"
  initPredicate := none
  invariant := "TraceComplete"
  lengthBound := 5
  nextPredicate := none
  paramVars := "parameters"
  specPath := "test/specs/Counter.tla"

/-! ## scenarios over a live TCP server -/

def scenarioTcp (fails : Failures) : IO Unit := do
  -- spawn the real server (async sessions, shared store)
  let srv ← IO.Process.spawn
    ({ cmd := mirrorBin, args := #["--serve", "19100"],
       stdin := .null : IO.Process.SpawnArgs })
  let c1 ← match ← waitServer "127.0.0.1" 19100 25 with
    | .ok t => pure t
    | .error e => checkA fails "tcp server up" false e; return ()
  -- (a) async validate + sync congruence
  csend c1 (.registerValidateAsync dcCfg 3 none)
  match ← expectAccepted c1 with
  | .error e => checkA fails "a: accepted" false e
  | .ok jid =>
    match ← awaitValid c1 jid with
    | .error e => checkA fails "a: await valid" false e
    | .ok (.valid) =>
        -- sync register_validate on a second connection for congruence
        match ← Shell.Transport.Tcp.connectTcp "127.0.0.1" 19100 with
        | .error e => checkA fails "a: second conn" false e
        | .ok c2 =>
            csend c2 (.registerValidate dcCfg 3 none)
            match ← crecv c2 with
            | .ok (.specValidated .valid) =>
                checkA fails "a: sync/async congruence" true
            | .ok m => checkA fails "a: sync congruence" false (toString (repr m))
            | .error e => checkA fails "a: sync congruence recv" false e
    | .ok v => checkA fails "a: await valid" false (toString (repr v))
  -- (b) async trace generation
  csend c1 (.registerGenTracesAsync counterCfg none none { numTraces := 1, view := none })
  match ← expectAccepted c1 with
  | .error e => checkA fails "b: accepted" false e
  | .ok jid =>
    csend c1 (.awaitJob jid none)
    match ← crecv c1 with
    | .error e => checkA fails "b: await recv" false e
    | .ok (.jobResult _ (.genTraces r)) =>
        checkA fails "b: trace paths" (!r.itfTracePaths.isEmpty)
          (toString (repr r.itfTracePaths))
    | .ok m => checkA fails "b: result" false (toString (repr m))
  -- (c) cancel a long trace-gen
  csend c1 (.registerGenTracesAsync counterCfg none none { numTraces := 10, view := none })
  match ← expectAccepted c1 with
  | .error e => checkA fails "c: accepted" false e
  | .ok jid =>
    csend c1 (.cancelJob jid)
    match ← crecv c1 with
    | .ok (.jobStatus _ .cancelled) => checkA fails "c: cancelled phase" true
    | .ok m => checkA fails "c: cancelled phase" false (toString (repr m))
    | .error e => checkA fails "c: recv" false e
  -- (d) bogus id
  csend c1 (.queryJob "bogus-job-id")
  match ← crecv c1 with
  | .ok (.jobStatus _ .unknown) => checkA fails "d: unknown id" true
  | .ok m => checkA fails "d: unknown id" false (toString (repr m))
  | .error e => checkA fails "d: recv" false e
  -- (8) bounds outside [1,100] rejected on the async path
  csend c1 (.registerValidateAsync dcCfg 0 none)
  match ← crecv c1 with
  | .ok (.registerError e) =>
      checkA fails "8: bound 0 rejected" (e.contains "outside allowed range") e
  | .ok m => checkA fails "8: bound 0" false (toString (repr m))
  | .error e => checkA fails "8: bound 0 recv" false e
  csend c1 (.registerValidateAsync dcCfg 101 none)
  match ← crecv c1 with
  | .ok (.registerError e) =>
      checkA fails "8: bound 101 rejected" (e.contains "outside allowed range") e
  | .ok m => checkA fails "8: bound 101" false (toString (repr m))
  | .error e => checkA fails "8: bound 101 recv" false e
  -- (e) concurrency: two jobs on c1 + one on a second connection
  match ← Shell.Transport.Tcp.connectTcp "127.0.0.1" 19100 with
  | .error e => checkA fails "e: second conn" false e
  | .ok c2 => do
    csend c1 (.registerValidateAsync dcCfg 3 none)
    csend c1 (.registerGenTracesAsync counterCfg none none { numTraces := 1, view := none })
    csend c2 (.registerValidateAsync dcCfg 3 none)
    let r1 ← expectAccepted c1
    let r2 ← expectAccepted c1
    let r3 ← expectAccepted c2
    checkA fails "e: three accepted"
      (r1.isOk && r2.isOk && r3.isOk)
      s!"{repr r1} {repr r2} {repr r3}"
    if let .ok j1 := r1 then
      -- §5.5 cross-connection visibility: the OTHER connection can
      -- query this job id (any non-unknown phase proves visibility)
      csend c2 (.queryJob j1)
      match ← crecv c2 with
      | .ok (.jobStatus _ ph) =>
          let vis := match ph with | .unknown => false | _ => true
          checkA fails "e: cross-conn visibility" vis (toString (repr ph))
      | .ok (.jobResult _ _) => checkA fails "e: cross-conn visibility" true
      | .ok m => checkA fails "e: cross-conn visibility" false (toString (repr m))
      | .error e => checkA fails "e: cross-conn recv" false e
      match ← awaitValid c1 j1 with
      | .error e => checkA fails "e: job1" false e
      | .ok v =>
        let okv := match v with | .valid => true | _ => false
        checkA fails "e: job1 valid" okv (toString (repr v))
    if let .ok j3 := r3 then
      match ← awaitValid c2 j3 with
      | .error e => checkA fails "e: job3 (2nd conn)" false e
      | .ok v =>
        let okv := match v with | .valid => true | _ => false
        checkA fails "e: job3 valid" okv (toString (repr v))
    if let .ok j2 := r2 then
      csend c1 (.awaitJob j2 none)
      match ← crecv c1 with
      | .ok (.jobResult _ (.genTraces r)) =>
          checkA fails "e: job2 traces" (!r.itfTracePaths.isEmpty)
      | .ok m => checkA fails "e: job2" false (toString (repr m))
      | .error e => checkA fails "e: job2 recv" false e
  -- done
  try srv.kill catch _ => pure ()
  let _ ← srv.wait

/-! ## (f) mTLS variant -/

def runCmd (cmd : String) (args : Array String) : IO (Except String String) := do
  let out ← IO.Process.output { cmd := cmd, args := args }
  if out.exitCode == 0 then return .ok out.stdout
  else return .error out.stderr

def scenarioMtls (fails : Failures) : IO Unit := do
  let dir := ".lake/build/tmp-async-pki"
  let _ ← runCmd "rm" #["-rf", dir]
  let _ ← runCmd "mkdir" #["-p", dir]
  let p (n : String) : String := dir ++ "/" ++ n
  let steps : Array (String × Array String) :=
    #[("openssl", #["req", "-x509", "-newkey", "rsa:2048", "-nodes",
        "-keyout", p "ca.key", "-out", p "ca.crt", "-days", "30",
        "-subj", "/CN=Async CA", "-addext", "basicConstraints=critical,CA:TRUE"]),
      ("openssl", #["req", "-newkey", "rsa:2048", "-nodes",
        "-keyout", p "server.key", "-out", p "server.csr", "-subj", "/CN=localhost"]),
      ("openssl", #["req", "-newkey", "rsa:2048", "-nodes",
        "-keyout", p "client.key", "-out", p "client.csr", "-subj", "/CN=async-client"])]
  for (c, a) in steps do
    let _ ← runCmd c a
  IO.FS.writeFile (p "server.ext") "subjectAltName=DNS:localhost,IP:127.0.0.1\n"
  let s1 ← runCmd "openssl" #["x509", "-req", "-in", p "server.csr",
    "-CA", p "ca.crt", "-CAkey", p "ca.key", "-CAcreateserial",
    "-out", p "server.crt", "-days", "365", "-extfile", p "server.ext"]
  let _ ← runCmd "openssl" #["x509", "-req", "-in", p "client.csr",
    "-CA", p "ca.crt", "-CAkey", p "ca.key", "-CAcreateserial",
    "-out", p "client.crt", "-days", "365"]
  let s1bad := match s1 with | .error _ => true | .ok _ => false
  if s1bad then
    checkA fails "f: pki generation" false (toString (repr s1))
    return
  let srv ← IO.Process.spawn
    ({ cmd := mirrorBin,
       args := #["--server", "19101", "--tls", "--jobs", "4",
                 "--cert", p "server.crt", "--key", p "server.key",
                 "--ca", p "ca.crt"],
       stdin := .null : IO.Process.SpawnArgs })
  -- wait for the TLS listener by polling the plain TCP side (connect
  -- then drop; the TLS handshake is expected to fail on a plain conn)
  let mut up := false
  let mut tries : Nat := 25
  while !up && tries > 0 do
    match ← Shell.Transport.Tcp.connectTcp "127.0.0.1" 19101 with
    | .ok _ => up := true
    | .error _ => IO.sleep 200; tries := tries - 1
  if !up then checkA fails "f: server up" false "never listened"
  match ← Shell.Transport.Tls.mkClientCtx
      { certFile := p "client.crt", keyFile := p "client.key", caFile := p "ca.crt" } with
  | .error e => checkA fails "f: client ctx" false e
  | .ok ctx =>
    match ← Shell.Transport.Tls.connectTls ctx "localhost" 19101 with
    | .error e =>
        checkA fails "f: mTLS connect" false e
        try srv.kill catch _ => pure (); let _ ← srv.wait
    | .ok c =>
        csend c (.registerValidateAsync dcCfg 3 none)
        match ← expectAccepted c with
        | .error e => checkA fails "f: accepted" false e
        | .ok jid =>
          match ← awaitValid c jid with
          | .error e => checkA fails "f: await valid" false e
          | .ok v =>
            let okv := match v with | .valid => true | _ => false
            checkA fails "f: await valid" okv (toString (repr v))
        try srv.kill catch _ => pure ()
        let _ ← srv.wait

/-- §5.6 capacity: a --jobs 1 server runs ONE live job; a second
submission while the first is live fails with the queue-full
register_error (the store's parity-tested capacity semantics). -/
def scenarioCapacity (fails : Failures) (p : String → String) : IO Unit := do
  let srv ← IO.Process.spawn
    ({ cmd := mirrorBin,
       args := #["--server", "19102", "--tls", "--jobs", "1",
                 "--cert", p "server.crt", "--key", p "server.key",
                 "--ca", p "ca.crt"],
       stdin := .null : IO.Process.SpawnArgs })
  let mut up := false
  let mut tries : Nat := 25
  while !up && tries > 0 do
    match ← Shell.Transport.Tcp.connectTcp "127.0.0.1" 19102 with
    | .ok _ => up := true
    | .error _ => IO.sleep 200; tries := tries - 1
  if !up then checkA fails "6: server up" false "never listened"
  match ← Shell.Transport.Tls.mkClientCtx
      { certFile := p "client.crt", keyFile := p "client.key", caFile := p "ca.crt" } with
  | .error e =>
      checkA fails "6: client ctx" false e
      try srv.kill catch _ => pure (); let _ ← srv.wait
  | .ok ctx =>
    match ← Shell.Transport.Tls.connectTls ctx "localhost" 19102 with
    | .error e =>
        checkA fails "6: mTLS connect" false e
        try srv.kill catch _ => pure (); let _ ← srv.wait
    | .ok c =>
        csend c (.registerValidateAsync dcCfg 3 none)
        match ← expectAccepted c with
        | .error e =>
            checkA fails "6: first accepted" false e
            try srv.kill catch _ => pure (); let _ ← srv.wait
        | .ok jid =>
            -- job 1 is live (apalache runs for seconds): the second
            -- submit must hit the capacity bound synchronously
            csend c (.registerValidateAsync dcCfg 3 none)
            match ← crecv c with
            | .ok (.registerError e) =>
                checkA fails "6: queue full" (e.contains "queue full") e
            | .ok m => checkA fails "6: queue full" false (toString (repr m))
            | .error e => checkA fails "6: recv" false e
            match ← awaitValid c jid with
            | .error e => checkA fails "6: first job" false e
            | .ok v =>
                let okv := match v with | .valid => true | _ => false
                checkA fails "6: first job valid" okv (toString (repr v))
            try srv.kill catch _ => pure ()
            let _ ← srv.wait

def main : IO UInt32 := do
  let fails ← IO.mkRef ([] : List String)
  match ← IO.getEnv "APALACHE_MC" with
  | none => IO.eprintln "SKIP async_spec (APALACHE_MC not set)"; return 0
  | some _ =>
      IO.eprintln "[async: tcp scenarios]"
      scenarioTcp fails
      IO.eprintln "[async: mTLS scenario]"
      scenarioMtls fails
      IO.eprintln "[async: capacity scenario (--jobs 1)]"
      let p (n : String) : String := ".lake/build/tmp-async-pki/" ++ n
      scenarioCapacity fails p
      let fs ← fails.get
      if fs.isEmpty then
        IO.eprintln "ASYNC SPEC: all green"
        return 0
      else
        for f in fs do IO.eprintln s!"FAIL {f}"
        IO.eprintln s!"ASYNC SPEC: {fs.length} failure(s)"
        return 1