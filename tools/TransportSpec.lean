import Shell.Transport.Tcp
import Shell.Transport.Tls
import Shell.Transport.Stdio

/-!
# t15 gate: TCP + mTLS transports

Three tiers:
1. policy unit tests on the OpenSSL shim (context creation rules,
   fingerprints vs the openssl CLI, expiry arithmetic);
2. TCP end-to-end (echo session, ephemeral port, drop survival);
3. mTLS end-to-end (TLS 1.3 mutual auth, fingerprint pinning, negative
   cases: wrong pin, TLS 1.2-only peer via openssl s_client, untrusted
   client certificate, certificate-less client).

The servers run in child processes (@--tcp-serve@ / @--tls-serve@) so
the gate needs no Lean concurrency: one connection per client case,
sequential, matching the one-session-per-connection design.

The throwaway PKI is generated with the @openssl@ CLI at test time; the
gate skips itself when the binary is missing.
-/

open Shell.Transport Shell.Transport.Tcp Shell.Transport.Tls

structure Failures where
  ref : IO.Ref Nat

def newFailures : IO Failures := return { ref := (← IO.mkRef 0) }

def check (f : Failures) (name : String) (ok : Bool) : IO Unit := do
  if ok then IO.println s!"ok: {name}"
  else
    f.ref.modify (· + 1)
    IO.println s!"FAIL: {name}"

def runCmd (cmd : String) (args : Array String) : IO String := do
  let out ← IO.Process.output { cmd, args }
  return out.stdout ++ out.stderr

def expectOk (f : Failures) (name : String) (e : Except String α) : IO (Option α) := do
  match e with
  | .ok v =>
      check f name true
      return some v
  | .error err =>
      check f (name ++ " (" ++ err ++ ")") false
      return none

def expectErr (f : Failures) (name : String) (e : Except String α) : IO Unit := do
  match e with
  | .error _ => check f name true
  | .ok _ => check f name false

/-- One exchange per connection: read a line, echo it, end the session
(the accept loop then closes the socket and takes the next client). -/
def echoSession (t : Transport) : IO Unit := do
  match ← t.recv with
  | some l => t.send ("echo:" ++ l)
  | none => pure ()

/-- One session per connection; drops are logged and survived. -/
partial def acceptLoop (lfd : UInt64) (mk : UInt64 → IO (Option Transport)) : IO Unit := do
  let cfd ← Ffi.acceptFd lfd
  if cfd == Ffi.fdError then
    IO.eprintln "accept failed; continuing"
  else
    match ← (try mk cfd catch e => IO.eprintln s!"setup failed: {e}"; pure none) with
    | some t =>
        try echoSession t catch e => IO.eprintln s!"session ended: {e}"
    | none => IO.eprintln "connection skipped"
    Ffi.closeFd cfd
  acceptLoop lfd mk

def tcpServe : IO Unit := do
  match ← listenTcp "localhost" 0 with
  | .error e => throw (IO.userError e)
  | .ok (lfd, bound) =>
      IO.println s!"PORT {bound}"
      (← IO.getStdout).flush
      acceptLoop lfd (fun cfd =>
        return some (tcpTransport ⟨cfd, ← IO.mkRef (ByteArray.mk (#[] : Array UInt8))⟩))

def tlsServe (dir : String) : IO Unit := do
  let files : TlsFiles := { certFile := s!"{dir}/server.crt",
                            keyFile := s!"{dir}/server.key",
                            caFile := s!"{dir}/ca.crt" }
  match ← mkServerCtx files with
  | .error e => throw (IO.userError e)
  | .ok ctx =>
      match ← listenTcp "localhost" 0 with
      | .error e => throw (IO.userError e)
      | .ok (lfd, bound) =>
          IO.println s!"PORT {bound}"
          (← IO.getStdout).flush
          acceptLoop lfd (fun cfd => do
            let ssl ← Ffi.tlsAcceptRaw ctx cfd
            let nul ← Ffi.sslIsNull ssl
            if nul == 1 then
              IO.eprintln s!"tls: handshake rejected ({← Ffi.tlsErrmsg})"
              return none
            else
              return some (tlsTransport ⟨ssl, ← IO.mkRef (ByteArray.mk (#[] : Array UInt8))⟩))

/-- Wait for the child server to report its ephemeral port. -/
def readPort (out : IO.FS.Handle) : IO Nat := do
  let mut line := ""
  let mut tries := 100
  while tries > 0 do
    line ← out.getLine
    let clean := Shell.Transport.stripEol line
    if clean.startsWith "PORT" then
      let p := (clean.splitOn " ").getLast?.getD ""
      match p.toNat? with
      | some n => return n
      | none => throw (IO.userError s!"bad PORT line: {line}")
    tries := tries - 1
  throw (IO.userError "server child never reported a port")

partial def tryConnect (host : String) (port : Nat) (tries : Nat) :
    IO (Except String Transport) := do
  if tries == 0 then return .error "connect retries exhausted"
  match ← connectTcp host port with
  | .ok t => return .ok t
  | .error _ =>
      IO.sleep 200
      tryConnect host port (tries - 1)

partial def tryConnectTls (ctx : Ffi.TlsCtx) (host : String) (port : Nat) (fp : String)
    (tries : Nat) : IO (Except String Transport) := do
  if tries == 0 then return .error "connect retries exhausted"
  match ← connectTlsPinned ctx host port fp with
  | .ok t => return .ok t
  | .error e =>
      if e.startsWith "certificate fingerprint mismatch" || tries == 1 then
        return .error e
      else
        IO.sleep 200
        tryConnectTls ctx host port fp (tries - 1)

def mainTests : IO UInt32 := do
  let f ← newFailures
  let ov ← IO.Process.output { cmd := "openssl", args := #["version"] }
  if ov.exitCode != 0 then
    IO.println "transport spec: skipped (openssl CLI missing)"
    return 0

  -- throwaway PKI
  let dir : String := ".lake/build/tmp-pki"
  let _ ← IO.FS.createDirAll dir
  let path (n : String) : String := s!"{dir}/{n}"
  let ca : Array String := #["/CN=Test CA"]
  let _ ← runCmd "openssl" #["req", "-x509", "-newkey", "rsa:2048", "-nodes",
    "-keyout", path "ca.key", "-out", path "ca.crt", "-days", "30",
    "-subj", ca[0]!, "-addext", "basicConstraints=critical,CA:TRUE"]
  let _ ← runCmd "openssl" #["req", "-newkey", "rsa:2048", "-nodes",
    "-keyout", path "server.key", "-out", path "server.csr", "-subj", "/CN=localhost"]
  IO.FS.writeFile (path "server.ext") "subjectAltName=DNS:localhost,IP:127.0.0.1\n"
  let ext : String := path "server.ext"
  let sign (csr : String) (out : String) (days : String) (extra : Array String) : IO Bool := do
    let o ← IO.Process.output
      { cmd := "openssl", args := #["x509", "-req", "-in", csr,
        "-CA", path "ca.crt", "-CAkey", path "ca.key", "-CAcreateserial",
        "-out", out, "-days", days] ++ extra }
    return o.exitCode == 0
  let signOth (csr : String) (out : String) (days : String) : IO Bool := do
    let o ← IO.Process.output
      { cmd := "openssl", args := #["x509", "-req", "-in", csr,
        "-CA", path "other.crt", "-CAkey", path "other.key", "-CAcreateserial",
        "-out", out, "-days", days] }
    return o.exitCode == 0
  check f "pki: server cert signed" (← sign (path "server.csr") (path "server.crt") "365" #[ "-extfile", ext ])
  let _ ← runCmd "openssl" #["req", "-newkey", "rsa:2048", "-nodes",
    "-keyout", path "client.key", "-out", path "client.csr", "-subj", "/CN=test-client"]
  check f "pki: client cert signed" (← sign (path "client.csr") (path "client.crt") "365" #[])
  let _ ← runCmd "openssl" #["req", "-newkey", "rsa:2048", "-nodes",
    "-keyout", path "nosan.key", "-out", path "nosan.csr", "-subj", "/CN=nosan"]
  check f "pki: nosan cert signed" (← sign (path "nosan.csr") (path "nosan.crt") "365" #[])
  let _ ← runCmd "openssl" #["req", "-x509", "-newkey", "rsa:2048", "-nodes",
    "-keyout", path "other.key", "-out", path "other.crt", "-days", "30",
    "-subj", "/CN=Other CA", "-addext", "basicConstraints=critical,CA:TRUE"]
  let _ ← runCmd "openssl" #["req", "-newkey", "rsa:2048", "-nodes",
    "-keyout", path "rogue.key", "-out", path "rogue.csr", "-subj", "/CN=rogue"]
  check f "pki: rogue cert signed" (← signOth (path "rogue.csr") (path "rogue.crt") "365")
  let _ ← runCmd "openssl" #["req", "-newkey", "rsa:2048", "-nodes",
    "-keyout", path "soon.key", "-out", path "soon.csr", "-subj", "/CN=soon"]
  check f "pki: soon-expiry cert signed" (← sign (path "soon.csr") (path "soon.crt") "2" #[ "-extfile", ext ])
  for k in ["ca.key", "server.key", "client.key", "nosan.key", "rogue.key",
            "soon.key", "other.key"] do
    let _ ← runCmd "chmod" #["600", path k]

  let good : TlsFiles := { certFile := path "server.crt", keyFile := path "server.key",
                           caFile := path "ca.crt" }
  let clientFiles : TlsFiles := { certFile := path "client.crt",
                                  keyFile := path "client.key",
                                  caFile := path "ca.crt" }
  let rogueFiles : TlsFiles := { certFile := path "rogue.crt",
                                 keyFile := path "rogue.key",
                                 caFile := path "ca.crt" }

  -- tier 1: policy unit tests
  let _ ← expectOk f "server ctx (good PKI)" (← mkServerCtx good)
  expectErr f "server ctx rejected: no SAN" (← mkServerCtx
    { certFile := path "nosan.crt", keyFile := path "nosan.key", caFile := path "ca.crt" })
  let _ ← runCmd "chmod" #["640", path "nosan.key"]
  expectErr f "server ctx rejected: group-readable key" (← mkServerCtx
    { certFile := path "server.crt", keyFile := path "nosan.key", caFile := path "ca.crt" })
  let _ ← runCmd "chmod" #["600", path "nosan.key"]
  let clientCtx? ← expectOk f "client ctx (good PKI)" (← mkClientCtx clientFiles)
  -- fingerprint parity with the openssl CLI
  let cli ← IO.Process.output
    { cmd := "openssl", args := #["x509", "-in", path "server.crt",
      "-noout", "-fingerprint", "-sha256"] }
  let raw := (cli.stdout.splitOn "=").getLast?.getD ""
  let cliFp := (String.ofList (raw.toList.filter (fun c => c != ':' && c != '\n' && c != '\r'))).toLower
  match ← certFingerprintSHA256 (System.FilePath.mk (path "server.crt")) with
  | some fp =>
      if fp != cliFp then IO.eprintln s!"dbg fp lean={fp} cli={cliFp}"
      check f "fingerprint matches openssl CLI" (fp == cliFp && fp.length == 64)
  | none => check f "fingerprint matches openssl CLI" false
  match ← certDaysRemaining (System.FilePath.mk (path "soon.crt")) with
  | some d => check f "soon cert days in [1,2]" (d == 1 || d == 2)
  | none => check f "soon cert days in [1,2]" false
  match ← certDaysRemaining (System.FilePath.mk (path "server.crt")) with
  | some d => check f "long cert days > 300" (d > 300)
  | none => check f "long cert days > 300" false

  -- tier 2: TCP (server in a child process)
  let tcpChild ← IO.Process.spawn
    ({ cmd := ".lake/build/bin/transport_spec", args := #["--tcp-serve"],
       stdout := .piped } : IO.Process.SpawnArgs)
  let tcpOut := (tcpChild.stdout : IO.FS.Handle)
  let tcpPort ← readPort tcpOut
  match ← tryConnect "localhost" tcpPort 25 with
  | .error e => check f ("tcp echo (" ++ e ++ ")") false
  | .ok t =>
      t.send "hello"
      let r ← t.recv
      check f "tcp echo round trip" (r == some "echo:hello")
  match ← tryConnect "localhost" tcpPort 25 with
  | .error e => check f ("tcp drop survival (" ++ e ++ ")") false
  | .ok t2 =>
      t2.send "again"
      let r2 ← t2.recv
      check f "tcp server survived peer drop" (r2 == some "echo:again")
  let _ ← tcpChild.kill

  -- tier 3: mTLS
  let some clientCtx := clientCtx?
    | IO.eprintln "client ctx unavailable; skipping TLS tier"
      let n0 ← f.ref.get
      return if n0 > 0 then 1 else 0
  let some fp ← certFingerprintSHA256 (System.FilePath.mk (path "server.crt"))
    | check f "server fingerprint" false
      return 1
  let tlsChild ← IO.Process.spawn
    ({ cmd := ".lake/build/bin/transport_spec", args := #["--tls-serve", dir],
       stdout := .piped } : IO.Process.SpawnArgs)
  let tlsOut := (tlsChild.stdout : IO.FS.Handle)
  let tp ← readPort tlsOut
  match ← tryConnectTls clientCtx "localhost" tp fp 25 with
  | .error e => check f ("mtls echo (" ++ e ++ ")") false
  | .ok t =>
      t.send "secure-hello"
      let r ← t.recv
      check f "mtls echo round trip (TLS 1.3, pinned fp)" (r == some "echo:secure-hello")
  let head62 : String := (fp.take 62).toString
  let wrongFp : String := head62 ++ (if (fp.take 2).toString == "00" then "11" else "00")
  expectErr f "mtls wrong fingerprint rejected" (← connectTlsPinned clientCtx "localhost" tp wrongFp)
  let rogueCtx? ← expectOk f "rogue client ctx (locally valid)" (← mkClientCtx rogueFiles)
  match rogueCtx? with
  | some rogueCtx =>
      match ← tryConnectTls rogueCtx "localhost" tp fp 3 with
      | .error _ => check f "mtls untrusted client cert rejected by server" true
      | .ok t =>
          -- TLS 1.3 lets the client finish before seeing the server's
          -- rejection; the exchange itself must fail instead
          let dead ←
            try
              t.send "rogue"
              let r ← t.recv
              pure (r.isNone)
            catch _ => pure true
          check f "mtls untrusted client cert rejected by server" dead
  | none => pure ()
  -- policy probes via openssl s_client with a real data exchange: the
  -- server must not echo unless the full policy is satisfied
  let probe (label : String) (extra : Array String) : IO Unit := do
    let o ← IO.Process.output
      { cmd := "bash", args := #["-c",
        s!"echo probe-line | timeout 5 openssl s_client -connect 127.0.0.1:{tp} " ++
          String.intercalate " " extra.toList ++ " 2>&1"] }
    check f label !(o.stdout ++ o.stderr).contains "echo:probe-line"
  probe "tls1.2-only peer rejected (no echo)"
    #["-tls1_2", "-CAfile", path "ca.crt", "-cert", path "client.crt", "-key", path "client.key"]
  probe "certificate-less client rejected (no echo)"
    #["-tls1_3", "-CAfile", path "ca.crt"]
  let _ ← tlsChild.kill

  let fails ← f.ref.get
  if fails == 0 then
    IO.println "TRANSPORT SPEC: all green"
    return 0
  else
    IO.println s!"TRANSPORT SPEC: {fails} failure(s)"
    return 1
def main (args : List String) : IO UInt32 := do
  match args with
  | ["--tcp-serve"] => tcpServe; return 0
  | ["--tls-serve", dir] => tlsServe dir; return 0
  | _ => mainTests