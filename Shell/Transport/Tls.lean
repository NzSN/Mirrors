import Ffi.Socket
import Ffi.Tls
import Shell.Transport.Tcp
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
  return some d.toNat

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
  try Ffi.tlsClose t.ssl catch _ => pure ()

private def hasLf (b : ByteArray) : Bool :=
  let rec go (i : Nat) : Bool :=
    if i >= b.size then false else if b.get! i == 10 then true else go (i + 1)
  go 0

private partial def findLf (b : ByteArray) (i : Nat) : Option Nat :=
  if i >= b.size then none
  else if b.get! i == 10 then some i
  else findLf b (i + 1)

/-- Line-framed @Transport@ over an established TLS session (the
Haskell recv-line-over-decrypted-stream loop). -/
def tlsTransport (t : TlsSession) : Transport :=
  let recvBuf := ByteArray.mk ((List.replicate 65536 0).toArray)
  { recv := do
      let mut acc ← t.buf.get
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
      if eof && acc.isEmpty then
        return none
      else
        let rec findLf (i : Nat) : Option Nat :=
          if i >= acc.size then none
          else if acc.get! i == 10 then some i
          else findLf (i + 1)
        match findLf 0 with
        | none =>
            t.buf.set (ByteArray.mk (#[] : Array UInt8))
            return some ((String.fromUTF8? acc |>.getD ""))
        | some i =>
            let line := acc.extract 0 i
            t.buf.set (acc.extract (i + 1) acc.size)
            return some (Shell.Transport.stripEol (String.fromUTF8? line |>.getD ""))
    send := fun s => do
        let bs := (s ++ "\n").toUTF8
        let r ← Ffi.tlsWriteAll t.ssl bs bs.size.toUInt64
        if r == Ffi.tlsError then
          throw (IO.userError "tls send failed") }

private partial def loop (lfd : UInt64) (ctx : Ffi.TlsCtx)
    (session : Transport → IO Unit) : IO Unit := do
  let cfd ← Ffi.acceptFd lfd
  if cfd == Ffi.fdError then
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

/-- Connect and pin the peer certificate fingerprint (Haskell
@connectTlsPinned@): after the handshake, the peer's SHA-256 fingerprint
must equal @expectedFp@, else the connection fails. -/
def connectTlsPinned (ctx : Ffi.TlsCtx) (host : String) (port : Nat)
    (expectedFp : String) : IO (Except String Transport) := do
  let ip := if host == "localhost" then "127.0.0.1" else host
  let fd ← Ffi.tcpSocket
  if fd == Ffi.fdError then return .error "socket creation failed"
  let crc ← Ffi.connectIpv4 fd ip port.toUInt64
  if crc == Ffi.fdError then
    Ffi.closeFd fd
    return .error s!"connect to {host}:{port} failed"
  let ssl ← Ffi.tlsConnectRaw ctx host fd
  let nul ← Ffi.sslIsNull ssl
  if nul == 1 then
    Ffi.closeFd fd
    return .error s!"TLS handshake failed: {← Ffi.tlsErrmsg}"
  else
    match ← peerCertFingerprintSHA256 ssl with
        | none =>
            Ffi.closeFd fd
            return .error "peer presented no certificate"
        | some fp =>
            if fp != expectedFp then
              Ffi.tlsClose ssl
              Ffi.closeFd fd
              return .error
                s!"certificate fingerprint mismatch for {host}:{port} (want {expectedFp}, got {fp})"
            else
              return .ok (tlsTransport ⟨ssl, ← IO.mkRef (ByteArray.mk (#[] : Array UInt8))⟩)

end Shell.Transport.Tls