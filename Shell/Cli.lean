import Shell.Mirror.Session
import Shell.Transport.Stdio
import Shell.Transport.Tcp
import Shell.Transport.Tls
import Shell.Registry
import Shell.Client
import Shell.Apalache.Runner
import Codec.Json
import Codec.Consul

import Codec.Consul

/-!
# Main — the mirror CLI (Layer 3, design 5.4)

CLI parity with the Haskell @app/Main.hs@ surface:

- default (no args): the stdio mirror session (Phase 3/5, fully
  functional with the apalache-backed oracles when apalache is
  available).
- @--serve <port> [--bind <addr>]@: plain TCP mirror server.
- @--server <port> --tls --cert --key --ca [--registry URL] [--jobs n]
  [--bind addr]@: mTLS mirror server; with @--registry@ (or
  @MODELMIRRORS_REGISTRY@) it registers with Consul, heartbeats the
  TTL check every 10s, and deregisters best-effort on SIGINT/SIGTERM
  and on normal exit (Phase 6).
- @validate ...@: client mode — direct @--host@ and @--port@ or registry
  discovery over mTLS with optional @--pin@ (Phase 6).

Option parsers are ports of the hand-rolled Haskell parsers
(@Protocol.ServerOpts@ / @Protocol.ValidateOpts@), kept pure so the
test suite can cover them directly.
-/

/-! ## argv -/

/-- The Lean 4.33 IO refactor dropped IO.getArgs; read argv from
/proc/self/cmdline (POSIX — same platform caveat as the signal
handling). -/
def getArgsIO : IO (List String) := do
  let r ← try pure (some (← IO.FS.readFile "/proc/self/cmdline")) catch _ => pure none
  match r with
  | none => return []
  | some s =>
      return ((s.splitOn (String.singleton (Char.ofNat 0))).drop 1).filter (fun x => !x.isEmpty)

/-! ## --serve / --server option parsing (Protocol.ServerOpts port) -/

structure ServerOpts where
  port : Nat
  cert : String
  key : String
  ca : String
  registry : Option String
  jobs : Nat
  bind : Option String
  deriving Repr

private structure ServerOptsC where
  port : Option Nat := none
  tls : Bool := false
  cert : Option String := none
  key : Option String := none
  ca : Option String := none
  registry : Option String := none
  jobs : Option Nat := none
  bind : Option String := none

private def reqString (name : String) (cur : Option String)
    (set : String → List String → Except String ServerOptsC)
    (rest : List String) : Except String ServerOptsC :=
  match rest with
  | [] => .error s!"option {name} requires an argument"
  | v :: more =>
      if cur.isSome then .error s!"duplicate --{name}"
      else set v more

private def reqInt (name : String) (cur : Option Nat)
    (set : Nat → List String → Except String ServerOptsC)
    (rest : List String) : Except String ServerOptsC :=
  match rest with
  | [] => .error s!"option {name} requires an argument"
  | v :: more =>
      match v.toNat? with
      | some n =>
          if cur.isSome then .error s!"duplicate --{name}" else set n more
      | none => .error s!"invalid --{name}: {v}"

private def parseServeNum (p : String) (b : Option String) :
    Except String (Nat × Option String) :=
  match p.toNat? with
  | some n => if n > 0 then .ok (n, b) else .error s!"invalid port: {p}"
  | none => .error s!"invalid port: {p}"

/-- Parse @--serve@ tokens: @<port>@ or @<port> --bind <addr>@. -/
def parseServeCli (argv : List String) : Except String (Nat × Option String) :=
  match argv with
  | [p] => parseServeNum p none
  | [p, "--bind", addr] => parseServeNum p (some addr)
  | _ => .error "usage: ModelMirrors --serve <port> [--bind <addr>]"

private def optOr (name : String) : Option String → Except String String
  | some v => .ok v
  | none => .error s!"missing required --{name}"

/-- Parse @--server@ tokens: positional port plus @--tls --cert --key
--ca [--registry] [--jobs] [--bind]@ in any order (order-independent,
rejects unknown options, duplicates, and non-numeric values). -/
private partial def serverOptsGo (s : ServerOptsC) : List String → Except String ServerOptsC
  | [] => pure s
  | a :: as =>
      match a with
      | "--tls" =>
          if s.tls then throw "duplicate --tls" else serverOptsGo { s with tls := true } as
      | "--cert" => reqString "cert" s.cert (fun v r => serverOptsGo { s with cert := some v } r) as
      | "--key" => reqString "key" s.key (fun v r => serverOptsGo { s with key := some v } r) as
      | "--ca" => reqString "ca" s.ca (fun v r => serverOptsGo { s with ca := some v } r) as
      | "--registry" => reqString "registry" s.registry (fun v r => serverOptsGo { s with registry := some v } r) as
      | "--bind" => reqString "bind" s.bind (fun v r => serverOptsGo { s with bind := some v } r) as
      | "--jobs" => reqInt "jobs" s.jobs (fun v r => serverOptsGo { s with jobs := some v } r) as
      | other =>
          if other.startsWith "--" then throw s!"unknown option: {other}"
          else match other.toNat? with
            | some n =>
                if s.port.isSome then throw s!"duplicate port argument: {other}"
                else serverOptsGo { s with port := some n } as
            | none => throw s!"invalid port: {other}"

def parseServerOpts (argv : List String) : Except String ServerOpts := do
  let s ← serverOptsGo {} argv
  let some port := s.port | throw "missing required port (expected a positive integer)"
  if port == 0 then throw "missing required port (expected a positive integer)"
  unless s.tls do throw "missing required --tls"
  let cert ← optOr "cert" s.cert
  let key ← optOr "key" s.key
  let ca ← optOr "ca" s.ca
  return { port, cert, key, ca, registry := s.registry,
           jobs := s.jobs.getD 4, bind := s.bind }

/-! ## validate option parsing (Protocol.ValidateOpts port) -/

structure ValidateOpts where
  host : String := ""
  port : Nat := 0
  hostSet : Bool := false
  portSet : Bool := false
  spec : String := ""
  deps : List String := []
  bound : Nat := 10
  inv : Option String := none
  init : Option String := none
  next : Option String := none
  cinit : Option String := none
  tls : Bool := false
  cert : Option String := none
  key : Option String := none
  ca : Option String := none
  pin : Option String := none
  registry : Option String := none
  deriving Repr

private def arg (name : String) : List String →
    (String → List String → Except String ValidateOpts) → Except String ValidateOpts
  | [], _ => .error s!"option {name} requires an argument"
  | v :: as, k => k v as

private def validateFinalize (o : ValidateOpts) : Except String ValidateOpts :=
  match o.registry with
  | some _ =>
      if o.spec.isEmpty then .error "missing required --spec"
      else if o.hostSet then .error "--registry cannot be combined with --host"
      else if o.portSet then .error "--registry cannot be combined with --port"
      else if o.pin.isSome && !o.tls then .error "--pin requires --tls"
      else if !o.tls then .error "--registry requires --tls"
      else match o.cert, o.key, o.ca with
        | some _, some _, some _ => .ok o
        | _, _, _ => .error "--registry requires --cert, --key, and --ca"
  | none =>
      if o.host.isEmpty then .error "missing required --host"
      else if o.port == 0 then .error "missing required --port"
      else if o.spec.isEmpty then .error "missing required --spec"
      else if o.pin.isSome && !o.tls then .error "--pin requires --tls"
      else if o.tls then match o.cert, o.key, o.ca with
        | some _, some _, some _ => .ok o
        | _, _, _ => .error "--tls requires --cert, --key, and --ca"
      else .ok o

private partial def validateGo (o : ValidateOpts) : List String → Except String ValidateOpts
  | [] => validateFinalize o
  | a :: as =>
      match a with
      | "--host" => arg a as (fun v r => validateGo { o with host := v, hostSet := true } r)
      | "--port" => arg a as (fun v r =>
          match v.toNat? with
          | some p => validateGo { o with port := p, portSet := true } r
          | none => .error s!"invalid --port: {v}")
      | "--spec" => arg a as (fun v r => validateGo { o with spec := v } r)
      | "--dep" => arg a as (fun v r => validateGo { o with deps := o.deps ++ [v] } r)
      | "--bound" => arg a as (fun v r =>
          match v.toNat? with
          | some n => validateGo { o with bound := n } r
          | none => .error s!"invalid --bound: {v}")
      | "--inv" => arg a as (fun v r => validateGo { o with inv := some v } r)
      | "--init" => arg a as (fun v r => validateGo { o with init := some v } r)
      | "--next" => arg a as (fun v r => validateGo { o with next := some v } r)
      | "--cinit" => arg a as (fun v r => validateGo { o with cinit := some v } r)
      | "--tls" => validateGo { o with tls := true } as
      | "--cert" => arg a as (fun v r => validateGo { o with cert := some v } r)
      | "--key" => arg a as (fun v r => validateGo { o with key := some v } r)
      | "--ca" => arg a as (fun v r => validateGo { o with ca := some v } r)
      | "--pin" => arg a as (fun v r => validateGo { o with pin := some v } r)
      | "--registry" => arg a as (fun v r => validateGo { o with registry := some v } r)
      | other => .error s!"unknown option: {other}"

def parseValidateOpts (argv : List String) : Except String ValidateOpts :=
  validateGo {} argv

/-! ## server modes -/

private def mirrorSession (t : Shell.Transport.Transport) : IO Unit :=
  Shell.Mirror.run t Shell.Apalache.syncOracles

/-- Plain TCP mirror server (Haskell @serveCli@). -/
def serveCli (argv : List String) : IO UInt32 := do
  match parseServeCli argv with
  | .error e => IO.eprintln e; return 2
  | .ok (port, bind) =>
      Shell.Transport.Tcp.serveTcpOn (bind.getD "") port mirrorSession
      return 0

/-- The heartbeat loop (Haskell @heartbeatLoop@): every 10s, forever,
errors swallowed. Runs as a task next to the signal-aware accept loop
(which polls, so the task stays schedulable). -/
private partial def heartbeatLoop (url : Shell.Registry.RegistryUrl) (sid : String) :
    IO Unit := do
  Shell.Registry.heartbeatOnce url sid
  IO.sleep 10000
  heartbeatLoop url sid

/-- mTLS mirror server (Haskell @serveOne@): register with the
registry when configured, start the heartbeat task, serve, deregister
on exit; SIGINT/SIGTERM trigger deregistration and a clean exit (the
signal-aware accept loop returns when the flag is set). Concurrency
note: the accept loop is sequential (one session at a time); @--jobs@
is accepted for CLI parity and reserved for the Phase 4 job store. -/
def serveOne (opts : ServerOpts) : IO UInt32 := do
  Ffi.installExitSignals
  let files : Shell.Transport.Tls.TlsFiles :=
    { certFile := opts.cert, keyFile := opts.key, caFile := opts.ca }
  let regEnv ← IO.getEnv "MODELMIRRORS_REGISTRY"
  let regUrl := match opts.registry with
    | some u => some u
    | none => regEnv
  let mReg ←
    match regUrl with
    | none => pure none
    | some s =>
      match Shell.Registry.parseRegistryUrl s with
      | .error e =>
          IO.eprintln s!"warning: bad --registry URL ({e}); serving unregistered"
          pure none
      | .ok url => do
          -- a discoverable server must be able to publish its pin
          match ← Shell.Transport.Tls.certFingerprintSHA256 opts.cert with
          | none =>
              IO.eprintln
                s!"warning: cannot register (no certificate in {opts.cert}); serving unregistered"
              pure none
          | some fp =>
              let host ← Shell.Registry.advertisedHost
              let sid := Shell.Registry.serviceId host opts.port
              let ok ← Shell.Registry.registerService url
                { serviceId := sid, host := host, port := opts.port,
                  certFingerprint := some fp }
              if ok then
                let _ ← IO.asTask (prio := Task.Priority.dedicated)
                  (heartbeatLoop url sid)
                pure (some (url, sid))
              else
                IO.eprintln "warning: service registration failed; serving unregistered"
                pure none
  let bind := opts.bind.getD ""
  let rc ←
    try
      Shell.Transport.Tls.serveTlsOn bind opts.port files mirrorSession
      pure (0 : UInt32)
    catch _ => pure (2 : UInt32)
  -- finally-block parity: best-effort deregistration on the way out
  match mReg with
  | some (url, sid) => Shell.Registry.deregisterService url sid
  | none => pure ()
  Ffi.exitWith (rc.toUInt64)
  return rc

/-! ## validate mode (client) -/

private def needCert (o : ValidateOpts) : String :=
  o.cert.getD "registry requires --cert (parser invariant violated)"
private def needKey (o : ValidateOpts) : String :=
  o.key.getD "registry requires --key (parser invariant violated)"
private def needCa (o : ValidateOpts) : String :=
  o.ca.getD "registry requires --ca (parser invariant violated)"

/-- One discovered peer plus its advertised fingerprint (Haskell
@DiscoveredPeer@). -/
structure DiscoveredPeer where
  host : String
  port : Nat
  fingerprint : Option String

/-- The pin to use for a candidate: explicit @--pin@ wins over
registry metadata (Haskell @candidateFingerprint@). -/
def candidateFingerprint (explicitPin : Option String) (peer : DiscoveredPeer) :
    Option String :=
  match explicitPin with
  | some _ => explicitPin
  | none => peer.fingerprint

/-- Try each candidate in order; first success wins, else the
concatenated diagnostics (Haskell @tryCandidates@). -/
partial def tryCandidates (cs : List DiscoveredPeer)
    (f : DiscoveredPeer → IO (Except String Shell.Transport.Transport)) :
    IO (Except String Shell.Transport.Transport) := do
  match cs with
  | [] => return .error "no candidates discovered"
  | c :: rest =>
      match ← f c with
      | .ok t => return .ok t
      | .error err =>
          match ← tryCandidates rest f with
          | .ok t => return .ok t
          | .error errs => return .error (err ++ "; " ++ errs)

/-- Registry-discovered transport (Haskell @registryTransport@):
mTLS to each healthy candidate, pinning @--pin@ or the advertised
fingerprint when present. -/
def registryTransport (opts : ValidateOpts) (url : Shell.Registry.RegistryUrl) :
    IO (Option Shell.Transport.Transport) := do
  let infos ← Shell.Registry.discoverServices url
  let peers := infos.map (fun si => (⟨si.host, si.port, si.certFingerprint⟩ : DiscoveredPeer))
  let clientFiles : Shell.Transport.Tls.TlsFiles :=
    { certFile := needCert opts, keyFile := needKey opts, caFile := needCa opts }
  let r ← tryCandidates peers (fun peer => do
    match ← Shell.Transport.Tls.mkClientCtx clientFiles with
    | .error e => return .error e
    | .ok ctx =>
        match candidateFingerprint opts.pin peer with
        | some fp => Shell.Transport.Tls.connectTlsPinned ctx peer.host peer.port fp
        | none => Shell.Transport.Tls.connectTls ctx peer.host peer.port)
  match r with
  | .ok t => return (some t)
  | .error errs =>
      IO.eprintln ("registry discovery failed: " ++ errs)
      return none

/-- Direct transport (Haskell @validateDirectTransport@): plain TCP by
default, mTLS with @--tls@ (pinning with @--pin@). -/
def validateDirectTransport (opts : ValidateOpts) :
    IO (Except String Shell.Transport.Transport) := do
  if opts.tls then
    let files : Shell.Transport.Tls.TlsFiles :=
      { certFile := needCert opts, keyFile := needKey opts, caFile := needCa opts }
    match ← Shell.Transport.Tls.mkClientCtx files with
    | .error e => return .error e
    | .ok ctx =>
        match opts.pin with
        | some fp => Shell.Transport.Tls.connectTlsPinned ctx opts.host opts.port fp
        | none => Shell.Transport.Tls.connectTls ctx opts.host opts.port
  else
    Shell.Transport.Tcp.connectTcp opts.host opts.port

/-- Map one validate session to the exit codes (Haskell
@reportValidate@): 0 valid, 1 invalid, 2 infrastructure failure. -/
def reportValidate (act : IO (Except String Codec.ValidateResult)) : IO UInt32 := do
  let r ← try act catch e => pure (.error (toString e))
  match r with
  | .error e => IO.eprintln e; return 2
  | .ok .valid => IO.println "VALID"; return 0
  | .ok (.invalid msg) => IO.println "INVALID"; IO.println msg; return 1

/-- The validate-only CLI (Haskell @validateCli@). -/
def validateCli (argv : List String) : IO UInt32 := do
  match parseValidateOpts argv with
  | .error e => IO.eprintln e; return 2
  | .ok opts =>
      -- read the spec and its inline dependencies locally; the server
      -- never sees the client's filesystem
      let readOne (p : String) : IO (Option String) := do
        try pure (some (← IO.FS.readFile p)) catch _ => pure none
      let rec readAll : List String → IO (Option (List String))
        | [] => pure (some [])
        | p :: ps => do
            match ← readOne p with
            | none => pure none
            | some c =>
                match ← readAll ps with
                | none => pure none
                | some cs => pure (some (c :: cs))
      let some contents ← readAll (opts.spec :: opts.deps)
        | IO.eprintln "cannot read spec/deps"
          return 2
      let sources := contents
      let cfg : Codec.ApalacheConfig :=
        { constInit := opts.cinit, initPredicate := opts.init,
          invariant := opts.inv.getD "", lengthBound := opts.bound,
          nextPredicate := opts.next, paramVars := "",
          specPath := (opts.spec.splitOn "/").getLastD "" }
      let spec : Codec.SpecConfig := { sources := sources }
      let mT ← match opts.registry with
        | none =>
            match ← validateDirectTransport opts with
            | .error e => IO.eprintln e; pure none
            | .ok t => pure (some t)
        | some s =>
            match Shell.Registry.parseRegistryUrl s with
            | .error e => IO.eprintln e; pure none
            | .ok url => registryTransport opts url
      match mT with
      | none => return 2
      | some t =>
          reportValidate (Shell.Client.runClientValidate t cfg opts.bound (some spec))