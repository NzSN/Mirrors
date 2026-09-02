import Ffi.Socket
import Ffi.Tls
import Shell.Transport.Tcp
import Shell.Net.Http
import Shell.Transport.Stdio

/-!
# mTLS transport (t15, design 5.4 / 9.1)

Port of @Protocol.Transport.Tls@ (503 LOC Haskell, tls/crypton) onto the
OpenSSL shim (@Ffi/tls_shim.c@). The policy surface — the #1 code-review
target — lives in the shim and mirrors the Haskell rules exactly:

* TLS 1.3 only (min = max = TLS 1.3);
* mutual authentication: the server requires a client certificate
  (@FAIL_IF_NO_PEER_CERT@) and verifies it against the CA file;
* the client verifies the server chain against the CA file and pins the
  expected hostname (SAN DNS/IP) via @SSL_set1_host@;
* the server certificate must carry a non-empty SAN and its chain must
  validate against the CA file before the listener binds;
* key files readable by group/other are rejected (chmod 0600);
* certificates expiring within 7 days (or expired) log a warning.

@serveTlsOn@ / @connectTlsPinned@ keep the Haskell shapes: one session
per connection, handshake failures and mid-session drops logged and
survived, and the client can pin the peer's SHA-256 fingerprint.
-/

namespace Shell.Transport.Tls

open Shell.Transport

/-- Certificate/key/CA triple (paths, as in the Haskell CLI). -/
structure TlsFiles where
  certFile : System.FilePath
  keyFile : System.FilePath
  caFile : System.FilePath

private def fpOfRaw (run : ByteArray → UInt64 → BaseIO UInt64) : IO (Option String) := do
  let buf := ByteArray.mk ((List.replicate 65 0).toArray)
  let n ← liftM (run buf 64)
  if n == Ffi.tlsError then return none
  return some (String.fromUTF8? (buf.extract 0 64) |>.getD "")

/-- SHA-256 fingerprint (lowercase hex) of the first certificate in a
PEM file (Haskell @certFingerprintSHA256@). -/
def certFingerprintSHA256 (path : System.FilePath) : IO (Option String) :=
  fpOfRaw (Ffi.tlsCertFpFileRaw path.toString)

/-- SHA-256 fingerprint of the peer's leaf certificate on a live
session. -/
def peerCertFingerprintSHA256 (ssl : Ffi.TlsSsl) : IO (Option String) :=
  fpOfRaw (Ffi.tlsPeerFpRaw ssl)

/-- Days until the first certificate in a PEM file expires (negative if
expired); @none@ when the file has no certificates. -/
def certDaysRemaining (path : System.FilePath) : IO (Option Int) := do
  let d ← Ffi.tlsCertDaysRaw path.toString
  -- the C sentinel is (uint64)(int64)-1000000, i.e. 0 - 1000000 wrapped
  if d == (0 : UInt64) - 1000000 then return none
  -- M2 (review): the C side returns (uint64)(int64)days, so a negative
  -- (expired) count wraps into a huge UInt64; reinterpret signed here
  -- instead of via UInt64.toNat, which would turn -3 days into
  -- 2^64 - 3 and silently kill the expiry warning.
  if (d >>> 63) != 0 then
    -- high bit set: sign-extend the two's-complement value
    return some (Int.ofNat d.toNat - 18446744073709551616)
  else
    return some (Int.ofNat d.toNat)

/-- Warn (stderr) when the certificate expires within 7 days or is
already expired (Haskell @warnIfNearExpiry@). -/
def warnIfNearExpiry (label : String) (path : System.FilePath) : IO Unit := do
  match ← certDaysRemaining path with
  | some days =>
      if days < 7 then
        if days < 0 then
          IO.eprintln s!"warning: {label} certificate {path} is expired"
        else
          IO.eprintln s!"warning: {label} certificate {path} expires in {days} day(s)"
  | none => pure ()

/-- Server-side TLS policy (TLS 1.3 only, client certs required).
Fails with a human-readable message exactly where the Haskell
@mkServerParams@ does (key perms, credential load, CA file, SAN,
chain validation). -/
def mkServerCtx (files : TlsFiles) : IO (Except String Ffi.TlsCtx) := do
  warnIfNearExpiry "server" files.certFile
  let ctx ← Ffi.mkServerCtxRaw files.certFile.toString files.keyFile.toString
      files.caFile.toString
  let nul ← Ffi.isNull ctx
  if nul == 1 then return .error (← Ffi.tlsErrmsg) else return .ok ctx

/-- Client-side TLS policy (TLS 1.3 only; server chain + hostname
verified against the CA). The client certificate is required because
the server demands one. -/
def mkClientCtx (files : TlsFiles) : IO (Except String Ffi.TlsCtx) := do
  warnIfNearExpiry "client" files.certFile
  let ctx ← Ffi.mkClientCtxRaw files.certFile.toString files.keyFile.toString
      files.caFile.toString
  let nul ← Ffi.isNull ctx
  if nul == 1 then return .error (← Ffi.tlsErrmsg) else return .ok ctx

/-- An established TLS session plus its line-framing buffer. -/
structure TlsSession where
  ssl : Ffi.TlsSsl
  buf : IO.Ref ByteArray

/-- Best-effort graceful close: send @close_notify@, ignoring errors if
the peer already dropped. The SSL object itself is freed by the GC
finalizer backstop in the shim (design 9.7). -/
def tlsClose (t : TlsSession) : IO Unit := do
  try let _ ← Ffi.tlsClose t.ssl catch _ => pure ()

private def hasLf (b : ByteArray) : Bool :=
  let rec go (i : Nat) : Bool :=
    if i >= b.size then false else if b.get! i == 10 then true else go (i + 1)
  go 0

private partial def findLf (b : ByteArray) (i : Nat) : Option Nat :=
  if i >= b.size then none
  else if b.get! i == 10 then some i
  else findLf b (i + 1)

private def stripTrailingCrBytes (b : ByteArray) : ByteArray :=
  if b.size > 0 && b.get! (b.size - 1) == 13 then
    b.extract 0 (b.size - 1)
  else b

private def validatePartialLine (b : ByteArray) : IO Unit := do
  match findLf b 0 with
  | some i =>
      let payload := stripTrailingCrBytes (b.extract 0 i)
      if payload.size > maxProtocolLineBytes then
        throw (IO.userError s!"TLS line exceeds {maxProtocolLineBytes} UTF-8 bytes")
  | none =>
      let allowance :=
        if b.size > 0 && b.get! (b.size - 1) == 13 then 1 else 0
      if b.size > maxProtocolLineBytes + allowance then
        throw (IO.userError s!"TLS line exceeds {maxProtocolLineBytes} UTF-8 bytes")

/-- Line-framed @Transport@ over an established TLS session (the
Haskell recv-line-over-decrypted-stream loop). -/
def tlsTransport (t : TlsSession) : Transport :=
  let recvBuf := ByteArray.mk ((List.replicate 65536 0).toArray)
  { recv := do
      let mut acc ← t.buf.get
      validatePartialLine acc
      let mut found := true
      let mut eof := false
      while found && !eof do
        if hasLf acc then
          found := false
        else
          let n ← Ffi.tlsRead t.ssl recvBuf 65536
          if n == 0 || n == Ffi.tlsError then
            eof := true
          else
            acc := acc.append (recvBuf.extract 0 n.toNat)
            validatePartialLine acc
      if eof && acc.isEmpty then
        return none
      else
        match findLf acc 0 with
        | none =>
            t.buf.set (ByteArray.mk (#[] : Array UInt8))
            let payload := stripTrailingCrBytes acc
            return some (← decodeProtocolUtf8 payload)
        | some i =>
            let line := stripTrailingCrBytes (acc.extract 0 i)
            t.buf.set (acc.extract (i + 1) acc.size)
            return some (← decodeProtocolUtf8 line)
    send := fun s => do
        validateProtocolLine s
        let bs := (s ++ "\n").toUTF8
        let r ← Ffi.tlsWriteAll t.ssl bs bs.size.toUInt64
        if r == Ffi.tlsError then
          throw (IO.userError "tls send failed") }

private partial def loop (lfd : UInt64) (ctx : Ffi.TlsCtx)
    (session : Transport → IO Unit) : IO Unit := do
  -- poll instead of blocking in accept(2): check the signal flag
  -- every iteration (the signal may land on any thread, not
  -- necessarily the one inside select) and stop for cleanup
  let sig0 ← Ffi.signalFired
  if sig0 == 1 then
    return ()
  let ready ← Ffi.waitReadable lfd 200
  if ready == 1 then
    let cfd ← Ffi.acceptFd lfd
    if cfd == Ffi.fdError then
      let sig ← Ffi.signalFired
      if sig == 1 then
        return ()
      else
        IO.eprintln "tls: accept failed; continuing"
    else
      let ssl ← Ffi.tlsAcceptRaw ctx cfd
      let nul ← Ffi.sslIsNull ssl
      if nul == 1 then
        IO.eprintln s!"tls: handshake rejected ({← Ffi.tlsErrmsg})"
      else
        let t := { ssl, buf := ← IO.mkRef (ByteArray.mk (#[] : Array UInt8)) }
        try
          session (tlsTransport t)
        catch e =>
          IO.eprintln s!"tls: session ended: {e}"
        tlsClose t
      Ffi.closeFd cfd
  else if ready == Ffi.fdError then
    return ()
  loop lfd ctx session

/-- TLS accept loop (Haskell @serveTlsOn@ / @serveTlsConcurrentOn@,
sequential like @serveTcpOn@): accept a TCP connection, run the TLS 1.3
handshake with client-certificate verification, run exactly one session
on it, close, and keep accepting. Handshake failures and mid-session
drops are logged and survived. -/
partial def serveTlsOn (host : String) (port : Nat) (files : TlsFiles)
    (session : Transport → IO Unit) : IO Unit := do
  match ← mkServerCtx files with
  | .error e => throw (IO.userError s!"serveTlsOn: {e}")
  | .ok ctx =>
      match ← Shell.Transport.Tcp.listenTcp host port with
      | .error e => throw (IO.userError s!"serveTlsOn: {e}")
      | .ok (lfd, bound) =>
          IO.eprintln s!"tls: listening on {if host.isEmpty then "*" else host}:{bound} (mTLS, TLS 1.3)"
          loop lfd ctx session

/-- t33: concurrent variant of @serveTlsOn@ (Haskell
@serveTlsConcurrentOn@), WORKER-POOL model (Docs/worker-pool-design.md):
the accept loop only accepts and enqueues; a fixed pool of long-lived
workers (never completing in normal operation — the Windows
task-teardown race fires on task completion) each run the handshake +
session + close for one connection at a time. The shim's error buffer is
thread-local (FFI-hardening #2; the m4 interleaving caveat is retired),
so @dsh_tls_errmsg@ returns each calling thread's own failure message
and concurrent handshake failures cannot interleave. -/
private partial def serveTlsConcurrentOnImpl (errorContext host : String)
    (port : Nat) (files : TlsFiles)
    (session : String → Transport → IO Unit) (workers : Nat) : IO Unit := do
  match ← mkServerCtx files with
  | .error e => throw (IO.userError s!"{errorContext}: {e}")
  | .ok ctx =>
      match ← Shell.Transport.Tcp.listenTcp host port with
      | .error e => throw (IO.userError s!"{errorContext}: {e}")
      | .ok (lfd, bound) =>
          IO.eprintln s!"tls: listening on {if host.isEmpty then "*" else host}:{bound} (mTLS, TLS 1.3, worker pool, {max 1 workers} workers)"
          let q ← Shell.Transport.Tcp.ConnQueue.new
          Shell.Transport.Tcp.spawnPool workers q (fun cfd _peer => do
            -- t33 fix (impl-status §4): bound the handshake. A
            -- connected-but-silent client must not park a pool worker
            -- forever (t31's unbounded tasks absorbed this; the bounded
            -- pool does not). The shim treats the SO_RCVTIMEO read
            -- timeout as handshake failure, and the timeout is cleared
            -- right after success so session reads stay blocking
            -- (dsh_tls_read spins on WANT_READ otherwise).
            let _ ← Ffi.setRecvTimeoutMs cfd 10000
            let ssl ← Ffi.tlsAcceptRaw ctx cfd
            let nul ← Ffi.sslIsNull ssl
            if nul == 1 then
              IO.eprintln s!"tls: handshake rejected ({← Ffi.tlsErrmsg})"
            else
              let _ ← Ffi.setRecvTimeoutMs cfd 0
              let t := { ssl, buf := ← IO.mkRef (ByteArray.mk (#[] : Array UInt8)) }
              match ← peerCertFingerprintSHA256 ssl with
              | none =>
                  IO.eprintln
                    "tls: verified peer certificate has no available SHA-256 fingerprint"
              | some fingerprint =>
                  try
                    session fingerprint (tlsTransport t)
                  catch e =>
                    IO.eprintln s!"tls: session ended: {e}"
              tlsClose t
            Ffi.closeFd cfd)
          Shell.Transport.Tcp.loopAcceptPool lfd q

/--
Concurrent mTLS server whose callback receives the SHA-256 fingerprint of the
client leaf certificate after the TLS 1.3 handshake and client-CA validation
have succeeded. A verified connection without an extractable fingerprint is
closed without entering the session.
-/
partial def serveTlsConcurrentOnWithPeerFingerprint
    (host : String) (port : Nat) (files : TlsFiles)
    (session : String → Transport → IO Unit) (workers : Nat := 4) : IO Unit :=
  serveTlsConcurrentOnImpl "serveTlsConcurrentOnWithPeerFingerprint"
    host port files session workers

/--
Backward-compatible concurrent mTLS server. Existing callers and tests retain
the original callback shape; peer identity is intentionally discarded.
-/
partial def serveTlsConcurrentOn (host : String) (port : Nat) (files : TlsFiles)
    (session : Transport → IO Unit) (workers : Nat := 4) : IO Unit :=
  serveTlsConcurrentOnImpl "serveTlsConcurrentOn" host port files
    (fun _fingerprint transport => session transport) workers

/-- Shared connect: resolve, TCP connect, TLS 1.3 handshake with CA and
SAN validation. Returns the session's SSL object on success. -/
private def tlsHandshake (ctx : Ffi.TlsCtx) (host : String) (port : Nat) :
    IO (Except String Ffi.TlsSsl) := do
  let ip ← match ← Shell.Net.Http.resolveHost host with
    | .ok i => pure i
    | .error e => return .error e
  let fd ← Ffi.tcpSocket
  if fd == Ffi.fdError then return .error "socket creation failed"
  -- bounded reads: a peer that vanishes without close_notify must not
  -- wedge the client forever (SO_RCVTIMEO surfaces as a read error)
  let _ ← Ffi.setRecvTimeoutMs fd 5000
  let crc ← Ffi.connectIpv4 fd ip port.toUInt64
  if crc == Ffi.fdError then
    Ffi.closeFd fd
    return .error s!"connect to {host}:{port} failed"
  let ssl ← Ffi.tlsConnectRaw ctx host fd
  let nul ← Ffi.sslIsNull ssl
  if nul == 1 then
    Ffi.closeFd fd
    return .error s!"TLS handshake failed: {← Ffi.tlsErrmsg}"
  return .ok ssl

/-- Connect over mutually-authenticated TLS 1.3 with CA/SAN validation
but no fingerprint pin (Haskell @connectTls@ — used when neither
@--pin@ nor registry metadata provides a fingerprint). -/
def connectTls (ctx : Ffi.TlsCtx) (host : String) (port : Nat) :
    IO (Except String Transport) := do
  match ← tlsHandshake ctx host port with
  | .error e => return .error e
  | .ok ssl =>
      return .ok (tlsTransport ⟨ssl, ← IO.mkRef (ByteArray.mk (#[] : Array UInt8))⟩)

/-- Connect and pin the peer certificate fingerprint (Haskell
@connectTlsPinned@): after the handshake, the peer's SHA-256 fingerprint
must equal @expectedFp@, else the connection fails. t29: the comparison
is case-insensitive — hex fingerprints are conventionally printed
lowercase by this shim and UPPERCASE by the openssl CLI
(@x509 -fingerprint@), and a pasted pin from either source must both
work (the Haskell side has no normalization; this is a Lean robustness
improvement, not a parity change). -/
def connectTlsPinned (ctx : Ffi.TlsCtx) (host : String) (port : Nat)
    (expectedFp : String) : IO (Except String Transport) := do
  match ← tlsHandshake ctx host port with
  | .error e => return .error e
  | .ok ssl =>
      match ← peerCertFingerprintSHA256 ssl with
      | none => return .error "peer presented no certificate"
      | some fp =>
          if fp.toLower != expectedFp.toLower then
            return .error
              s!"certificate fingerprint mismatch for {host}:{port} (want {expectedFp}, got {fp})"
          else
            return .ok (tlsTransport ⟨ssl, ← IO.mkRef (ByteArray.mk (#[] : Array UInt8))⟩)

end Shell.Transport.Tls
