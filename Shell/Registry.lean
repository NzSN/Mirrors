import Shell.Net.Http
import Shell.Transport.Stdio
import Codec.Consul
import Lean

/-!
# Consul registry client (t16, design 5.4)

Port of the Haskell @Protocol.Registry@ (ModelMirros@3496251):
register a mirror service with a 30s TTL check, heartbeat it every
10s, deregister best-effort, and discover healthy peers. Failures are
reported, not thrown: registration returns @false@, discovery fails
closed with @[]@, heartbeat/deregister swallow errors — a registry
outage must never kill the caller's accept loop (a lapsed TTL simply
removes the service from discovery).

The registry is plain HTTP per design 9.2 (no TLS on this path), so
this rides the pure-Lean HTTP client; host names resolve via
getaddrinfo because registry URLs are configurable (the Haskell CLI
makes no loopback assumption, and neither do we).
-/

namespace Shell.Registry

open Consul (ServiceInfo)

/-- Registry base URL, e.g. @http://127.0.0.1:8500@ (Haskell
@RegistryUrl@ — an opaque string; only plain @http://host:port@ is
supported per 9.2). -/
structure RegistryUrl where
  /-- Host as written in the URL. -/
  host : String
  /-- Port as written in the URL (8500 when absent). -/
  port : Nat
  deriving Repr, DecidableEq

/-- Parse @http://host[:port]/@ (scheme optional, trailing path
ignored). Plain HTTP only (9.2). -/
def parseRegistryUrl (s : String) : Except String RegistryUrl :=
  if s.startsWith "https://" then
    .error ("https registry URLs are not supported (plain HTTP per design 9.2): " ++ s)
  else
    let noScheme : String := if s.startsWith "http://" then (s.drop 7).toString else s
    let authority := (noScheme.splitOn "/").headD ""
    if authority.isEmpty then
      .error ("registry URL needs a host: " ++ s)
    else
      match authority.splitOn ":" with
      | [h] => .ok { host := h, port := 8500 }
      | [h, p] =>
          match p.toNat? with
          | some n => .ok { host := h, port := n }
          | none => .error ("bad registry port: " ++ p)
      | _ => .error ("bad registry authority: " ++ authority)

private def reqOk (r : Except String Shell.Net.Http.HttpResponse) : Bool :=
  match r with
  | .ok resp => resp.status >= 200 && resp.status < 300
  | .error _ => false

/-- Register with a 30s TTL check (Haskell @registerService@);
@false@ on any failure. -/
def registerService (url : RegistryUrl) (info : ServiceInfo) : IO Bool := do
  let body := toString (Lean.Json.compress (Consul.encodeRegisterBody info))
  let r ← Shell.Net.Http.putTo url.host url.port
    (Consul.requestPath (.register info)) body
  return reqOk r

/-- One TTL heartbeat (Haskell @heartbeatLoop@ step; the loop itself
is the caller's job so it can stay cancellable). Errors swallowed. -/
def heartbeatOnce (url : RegistryUrl) (sid : String) : IO Unit := do
  let _ ← Shell.Net.Http.putTo url.host url.port
    (Consul.requestPath (.passCheck sid)) ""
  pure ()

/-- Best-effort deregistration; errors swallowed. -/
def deregisterService (url : RegistryUrl) (sid : String) : IO Unit := do
  let _ ← Shell.Net.Http.putTo url.host url.port
    (Consul.requestPath (.deregister sid)) ""
  pure ()

/-- Discover healthy mirror services; fails closed: any registry or
parsing error yields @[]@ (Haskell @discoverServices@). -/
def discoverServices (url : RegistryUrl) : IO (List ServiceInfo) := do
  let r ← Shell.Net.Http.requestTo "GET" url.host url.port
    (Consul.requestPath .discover) ""
  match r with
  | .error _ => return []
  | .ok resp =>
      if !(resp.status >= 200 && resp.status < 300) then return []
      match Lean.Json.parse resp.body with
      | .error _ => return []
      | .ok j =>
          -- GET via the one-shot POST framing is fine (Consul ignores
          -- the method); decode each entry, fail closed per entry
          match j with
          | .arr entries =>
              let mut out := []
              for e in entries do
                match Consul.decEntry e with
                | .ok ss => out := out ++ ss
                | .error _ => pure ()
              return out
          | _ => return []

/-! ## Server-side wiring (Haskell @serveOne@ registry block) -/

/-- The advertised hostname for registration (Haskell @advertisedHost@:
@uname -n@). POSIX only. -/
def advertisedHost : IO String := do
  let env ← IO.getEnv "HOSTNAME"
  match env with
  | some h => return h
  | none =>
      -- uname -n via /proc is not portable; fall back to uname(1)
      let out ← IO.Process.output { cmd := "uname", args := #["-n"] }
      let h := Shell.Transport.stripEol out.stdout
      return if h.isEmpty then "unknown" else h

/-- Service id: @modelmirrors-<host>-<port>@ (Haskell @sid@). -/
def serviceId (host : String) (port : Nat) : String :=
  s!"modelmirrors-{host}-{port}"

end Shell.Registry