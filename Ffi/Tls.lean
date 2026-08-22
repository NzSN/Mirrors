import Lean

/-!
# Ffi.Tls — OpenSSL shim declarations (t15, design 5.4 / 9.1)

The C side (@Ffi/tls_shim.c@) is the entire TLS TCB: TLS 1.3 only,
mutual authentication (client certificates required on the server),
CA-anchored chain verification, SAN required on server certificates,
hostname (SAN) pinning on the client, and group/other-readable key
files rejected. This module only declares the surface.

Ownership: @TlsCtx@ and @TlsSsl@ are external objects freed by GC
finalizers registered in the shim — the only finalizer backstop in the
code base (design 9.7). @tlsClose@ performs a best-effort close_notify;
it never frees, so close-then-collect is safe.
-/

namespace Ffi

/-- Sentinel error value for the UInt64-returning functions. -/
def tlsError : UInt64 := 0xFFFFFFFFFFFFFFFF

/-- An OpenSSL @SSL_CTX@ (server or client policy), freed by GC.
Values only ever come from the shim; the constructor exists only so
the type is inhabited (required by @opaque@ extern declarations). -/
inductive TlsCtx where
  | mk

/-- An established TLS session over a connected socket, freed by GC. -/
inductive TlsSsl where
  | mk

instance : Nonempty TlsCtx := ⟨.mk⟩
instance : Nonempty TlsSsl := ⟨.mk⟩

/-- On failure these return a NULL-payload sentinel external; check
with @isNull@ and fetch the reason via @tlsErrmsg@. -/
@[extern "dsh_tls_server_ctx"]
opaque mkServerCtxRaw : @& String → @& String → @& String → BaseIO TlsCtx

@[extern "dsh_tls_client_ctx"]
opaque mkClientCtxRaw : @& String → @& String → @& String → BaseIO TlsCtx

/-- @1@ when the argument is a failure sentinel. -/
@[extern "dsh_tls_is_null"]
opaque isNull : @& TlsCtx → BaseIO UInt64

/-- @1@ when the argument is a failure sentinel. -/
@[extern "dsh_tls_is_null"]
opaque sslIsNull : @& TlsSsl → BaseIO UInt64

@[extern "dsh_tls_accept"]
opaque tlsAcceptRaw : @& TlsCtx → UInt64 → BaseIO TlsSsl

@[extern "dsh_tls_connect"]
opaque tlsConnectRaw : @& TlsCtx → @& String → UInt64 → BaseIO TlsSsl

@[extern "dsh_tls_write_all"]
opaque tlsWriteAll : @& TlsSsl → @& ByteArray → UInt64 → BaseIO UInt64

@[extern "dsh_tls_read"]
opaque tlsRead : @& TlsSsl → @& ByteArray → UInt64 → BaseIO UInt64

/-- Best-effort close_notify (never frees; GC owns the object). -/
@[extern "dsh_tls_close"]
opaque tlsClose : @& TlsSsl → BaseIO Unit

/-- Writes the 64-char lowercase hex SHA-256 of the peer leaf cert into
the buffer; returns @tlsError@ when the peer presented no certificate. -/
@[extern "dsh_tls_peer_fp"]
opaque tlsPeerFpRaw : @& TlsSsl → @& ByteArray → UInt64 → BaseIO UInt64

/-- Same for the first certificate in a PEM file. -/
@[extern "dsh_tls_cert_fp_file"]
opaque tlsCertFpFileRaw : @& String → @& ByteArray → UInt64 → BaseIO UInt64

/-- Days until the first certificate in a PEM file expires (negative if
expired); the sentinel @noCertDays@ means "no certificates in file". -/
@[extern "dsh_tls_cert_days"]
opaque tlsCertDaysRaw : @& String → BaseIO UInt64

@[extern "dsh_tls_errmsg"]
opaque tlsErrmsgRaw : @& ByteArray → UInt64 → BaseIO UInt64

def noCertDays : Int := -1000000

/-- Human-readable reason for the last shim failure. -/
def tlsErrmsg : IO String := do
  let buf := ByteArray.mk ((List.replicate 1024 0).toArray)
  let n ← tlsErrmsgRaw buf 1023
  let n := min n.toNat 1023
  return String.fromUTF8? (buf.extract 0 n) |>.getD ""

end Ffi