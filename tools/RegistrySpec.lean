import Shell.Cli
import Shell.Registry
import Shell.Net.Http
import Lean

/-!
# t16 gate: registry/discovery + signal handling

1. pure option-parser parity units (ServerOpts/ValidateOpts/URL);
2. discovery candidate logic (candidateFingerprint, tryCandidates);
3. live mock-Consel flows: register / heartbeat / deregister recorded,
   discovery parsing incl. per-entry fail-closed, dead registry ->
   empty list;
4. SIGTERM e2e: a real @mirror --server --registry@ child registers,
   then deregisters and exits 0 on SIGTERM.

Skips itself when the openssl CLI is missing (the SIGTERM tier needs a
throwaway PKI).
-/

structure Failures where
  ref : IO.Ref Nat

def newFailures : IO Failures := return { ref := (← IO.mkRef 0) }

def check (f : Failures) (name : String) (ok : Bool) : IO Unit := do
  if ok then IO.println s!"ok: {name}"
  else
    f.ref.modify (· + 1)
    IO.println s!"FAIL: {name}"

def isErr {α : Type} : Except String α → Bool
  | .error _ => true
  | .ok _ => false

def runCmd (cmd : String) (args : Array String) : IO String := do
  let out ← IO.Process.output { cmd, args }
  return out.stdout ++ out.stderr

/-- A minimal in-memory transport for tryCandidates units. -/
def fakeTransport : Shell.Transport.Transport :=
  { recv := pure none, send := fun _ => pure () }

def main : IO UInt32 := do
  let f ← newFailures
  let ov ← IO.Process.output { cmd := "openssl", args := #["version"] }
  let haveOpenssl := ov.exitCode == 0

  -- tier 1: parsers
  check f "serve cli: ok" (parseServeCli ["9000"] ==
    .ok (9000, none))
  check f "serve cli: bind" (parseServeCli ["9000", "--bind", "127.0.0.1"] ==
    .ok (9000, some "127.0.0.1"))
  check f "serve cli: bad port" ((parseServeCli ["x"]) |> isErr)
  let so1 := parseServerOpts
    ["9000", "--tls", "--cert", "c", "--key", "k", "--ca", "a",
     "--registry", "http://r", "--jobs", "2"]
  check f "server opts: happy" (so1.map (fun o => (o.port, o.jobs)) ==
    .ok (9000, 2))
  let so2 := parseServerOpts ["9000", "--tls", "--cert", "c", "--key", "k", "--ca", "a"]
  check f "server opts: defaults jobs=4" (so2.map (fun o => o.jobs) == .ok 4)
  check f "server opts: no tls" ((parseServerOpts ["9000", "--cert", "c", "--key", "k", "--ca", "a"]) |> isErr)
  let so3 := parseServerOpts ["9000", "9001", "--tls", "--cert", "c", "--key", "k", "--ca", "a"]
  check f "server opts: dup port" (so3 |> isErr)
  let so4 := parseServerOpts ["9000", "--tls", "--cert", "c", "--key", "k", "--ca", "a", "--bogus"]
  check f "server opts: unknown" (so4 |> isErr)
  let vo1 := parseValidateOpts ["--host", "h", "--port", "1", "--spec", "s"]
  check f "validate: direct happy" (vo1.map (fun o => (o.host, o.bound)) == .ok ("h", 10))
  let vo2 := parseValidateOpts ["--registry", "http://r", "--spec", "s"]
  check f "validate: registry needs tls" (vo2 |> isErr)
  let vo3 := parseValidateOpts
    ["--registry", "http://r", "--spec", "s", "--tls", "--cert", "c",
     "--key", "k", "--ca", "a", "--host", "h"]
  check f "validate: registry+host rejected" (vo3 |> isErr)
  let vo4 := parseValidateOpts ["--host", "h", "--port", "1", "--spec", "s", "--pin", "aa"]
  check f "validate: pin requires tls" (vo4 |> isErr)
  -- URL parsing
  check f "url: bare host" (Shell.Registry.parseRegistryUrl "consul:8500" ==
    .ok { host := "consul", port := 8500 })
  check f "url: scheme + path" (Shell.Registry.parseRegistryUrl "http://127.0.0.1:8500/" ==
    .ok { host := "127.0.0.1", port := 8500 })
  check f "url: default port" (Shell.Registry.parseRegistryUrl "http://consul" ==
    .ok { host := "consul", port := 8500 })
  check f "url: https rejected" ((Shell.Registry.parseRegistryUrl "https://consul") |> isErr)
  check f "url: bad port" ((Shell.Registry.parseRegistryUrl "http://consul:x") |> isErr)

  -- tier 2: candidate logic
  check f "candidateFingerprint: pin wins" (candidateFingerprint (some "aa")
    ⟨"h", 1, some "bb"⟩ == some "aa")
  check f "candidateFingerprint: registry fp" (candidateFingerprint none
    ⟨"h", 1, some "bb"⟩ == some "bb")
  check f "candidateFingerprint: none" (candidateFingerprint none
    ⟨"h", 1, none⟩ == none)
  match ← tryCandidates [] (fun _ => pure (.error "x")) with
  | .error e => check f "tryCandidates: empty" (e == "no candidates discovered")
  | .ok _ => check f "tryCandidates: empty" false
  match ← tryCandidates [⟨"bad", 1, none⟩, ⟨"good", 2, none⟩]
      (fun p => pure (if p.host == "good" then .ok fakeTransport else .error "down")) with
  | .ok _ => check f "tryCandidates: order + diagnostics" true
  | .error _ => check f "tryCandidates: order + diagnostics" false

  -- tier 3: live mock consul
  let dir : String := ".lake/build/tmp-reg"
  let _ ← IO.FS.createDirAll dir
  let log := dir ++ "/requests.log"
  let discover := dir ++ "/discover.json"
  let portfile := dir ++ "/port"
  let _ ← runCmd "rm" #["-f", log, portfile]
  IO.FS.writeFile discover "[]"
  let mock ← IO.Process.spawn
    ({ cmd := "python3",
       args := #["tools/mock_consul.py", portfile, log, discover] } :
      IO.Process.SpawnArgs)
  let mut tries := 50
  let mut mport : Option Nat := none
  while tries > 0 && mport.isNone do
    let pf ← try pure (some (← IO.FS.readFile portfile)) catch _ => pure none
    match pf with
    | some s =>
        let p := Shell.Transport.stripEol s
        match p.toNat? with
        | some n => mport := some n
        | none => pure ()
    | none => pure ()
    IO.sleep 100
    tries := tries - 1
  match mport with
  | none =>
      check f "mock consul started" false
      let _ ← mock.kill
      return 1
  | some rport =>
      check f "mock consul started" true
      let url : Shell.Registry.RegistryUrl := { host := "localhost", port := rport }
      let info : Consul.ServiceInfo :=
        { serviceId := "sid-1", host := "mh", port := 9000,
          certFingerprint := some "ab" }
      let ok ← Shell.Registry.registerService url info
      check f "registerService ok" ok
      Shell.Registry.heartbeatOnce url "sid-1"
      Shell.Registry.deregisterService url "sid-1"
      IO.sleep 200
      let reqs ← try IO.FS.readFile log catch _ => pure ""
      check f "register request recorded"
        (reqs.contains "PUT /v1/agent/service/register")
      check f "heartbeat request recorded"
        (reqs.contains "PUT /v1/agent/check/pass/service:sid-1")
      check f "deregister request recorded"
        (reqs.contains "PUT /v1/agent/service/deregister/sid-1")
      -- discovery parsing (incl. fail-closed entries)
      IO.FS.writeFile discover
        "[{\"Service\":{\"ID\":\"a\",\"Address\":\"h1\",\"Port\":1,
           \"Meta\":{\"cert-sha256\":\"ff\"}}},
          {\"Service\":{\"ID\":\"b\",\"Address\":\"\",\"Port\":2}},
          {\"Service\":{\"ID\":\"c\",\"Address\":\"h3\",\"Port\":\"notanumber\"}},
          {\"Service\":{\"ID\":\"d\",\"Address\":\"h4\",\"Port\":4}}]"
      let infos ← Shell.Registry.discoverServices url
      check f "discover parses + drops empty + fails closed"
        (infos == [{ serviceId := "a", host := "h1", port := 1,
                      certFingerprint := some "ff" },
                    { serviceId := "d", host := "h4", port := 4,
                      certFingerprint := none }])
      -- dead registry fails closed
      let dead ← Shell.Registry.discoverServices { host := "localhost", port := 1 }
      check f "dead registry -> []" dead.isEmpty

      -- tier 4: SIGTERM deregistration e2e with the real server binary
      if haveOpenssl then
        -- throwaway PKI (same shape as the transport spec's)
        let p (n : String) : String := dir ++ "/" ++ n
        let _ ← runCmd "openssl" #["req", "-x509", "-newkey", "rsa:2048", "-nodes",
          "-keyout", p "ca.key", "-out", p "ca.crt", "-days", "30",
          "-subj", "/CN=Test CA", "-addext", "basicConstraints=critical,CA:TRUE"]
        let _ ← runCmd "openssl" #["req", "-newkey", "rsa:2048", "-nodes",
          "-keyout", p "server.key", "-out", p "server.csr", "-subj", "/CN=localhost"]
        IO.FS.writeFile (p "server.ext") "subjectAltName=DNS:localhost,IP:127.0.0.1\n"
        let s ← IO.Process.output
          { cmd := "openssl", args := #["x509", "-req", "-in", p "server.csr",
            "-CA", p "ca.crt", "-CAkey", p "ca.key", "-CAcreateserial",
            "-out", p "server.crt", "-days", "365", "-extfile", p "server.ext"] }
        let _ ← runCmd "openssl" #["req", "-newkey", "rsa:2048", "-nodes",
          "-keyout", p "client.key", "-out", p "client.csr", "-subj", "/CN=tc"]
        let _ ← IO.Process.output
          { cmd := "openssl", args := #["x509", "-req", "-in", p "client.csr",
            "-CA", p "ca.crt", "-CAkey", p "ca.key", "-CAcreateserial",
            "-out", p "client.crt", "-days", "365"] }
        for k in ["ca.key", "server.key", "client.key"] do
          let _ ← runCmd "chmod" #["600", p k]
        if s.exitCode == 0 then
          let _ ← runCmd "rm" #["-f", log]
          -- concrete port so the child is simple to probe
          let srv2 ← IO.Process.spawn
            ({ cmd := ".lake/build/bin/mirror",
               args := #["--server", "19007", "--tls", "--cert", p "server.crt",
                         "--key", p "server.key", "--ca", p "ca.crt",
                         "--registry", s!"http://localhost:{rport}"] } :
              IO.Process.SpawnArgs)
          let mut t2 := 50
          let mut registered := false
          while t2 > 0 && !registered do
            let lf ← try pure (some (← IO.FS.readFile log)) catch _ => pure none
            match lf with
            | some l => registered := l.contains "PUT /v1/agent/service/register"
            | none => pure ()
            IO.sleep 100
            t2 := t2 - 1
          check f "server child registered with consul" registered
          -- SIGTERM (not SIGKILL): the handler must deregister+exit 0
          let _ ← runCmd "kill" #["-TERM", toString srv2.pid]
          let st ← srv2.wait
          IO.sleep 300
          let l2 ← try IO.FS.readFile log catch _ => pure ""
          check f "SIGTERM -> deregistered + exit 0"
            (l2.contains "PUT /v1/agent/service/deregister/" && st == 0)
        else
          IO.eprintln "pki generation failed; skipping SIGTERM tier"

      let _ ← mock.kill

  let fails ← f.ref.get
  if fails == 0 then
    IO.println "REGISTRY SPEC: all green"
    return 0
  else
    IO.println s!"REGISTRY SPEC: {fails} failure(s)"
    return 1