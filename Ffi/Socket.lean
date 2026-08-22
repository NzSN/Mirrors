import Lean

/-!
# Ffi.Socket — minimal loopback TCP sockets (t14 spike, design 9.2)

**Decision (t14): pure-Lean HTTP/1.1 client over a tiny C socket shim,
not libcurl FFI.** The explorer's HTTP surface is loopback-only JSON
POSTs (@http://localhost:<port>/rpc@) with Content-Length or chunked
bodies — no TLS, no redirects, no auth, no connection pooling — so a
~150-line POSIX shim (fd socket/connect/bind/listen/accept/send/recv,
loopback only, documented as trusted TCB per design 5.4) plus
HTTP/1.1 framing implemented in auditable Lean is strictly smaller TCB
than binding libcurl (process-global init, easy-handle lifetimes,
share objects). TLS remains FFI territory for the TCP+mTLS transport
(t15) and does not touch this shim.

All results are unboxed @UInt64@ (the unboxed FFI ABI; @Int@ would be
a boxed object and requires a boxing C shim): sentinel errors use
@UInt64.max@ as "-1".
-/

namespace Ffi

/-- Sentinel for fd-style failures (the C side's -1). -/
def fdError : UInt64 := 0xFFFFFFFFFFFFFFFF

@[extern "dsh_socket_tcp"]
opaque tcpSocket : BaseIO UInt64

@[extern "dsh_connect_loopback"]
opaque connectLoopback : @& UInt64 → @& UInt64 → BaseIO UInt64

@[extern "dsh_bind_loopback"]
opaque bindLoopback : @& UInt64 → @& UInt64 → BaseIO UInt64

@[extern "dsh_listen_fd"]
opaque listenFd : @& UInt64 → BaseIO UInt64

@[extern "dsh_accept_fd"]
opaque acceptFd : @& UInt64 → BaseIO UInt64

@[extern "dsh_local_port"]
opaque localPort : @& UInt64 → BaseIO UInt64

@[extern "dsh_send_all"]
opaque sendAll : @& UInt64 → @& ByteArray → UInt64 → BaseIO UInt64

@[extern "dsh_recv_some"]
opaque recvSome : @& UInt64 → @& ByteArray → UInt64 → BaseIO UInt64

@[extern "dsh_set_rcvtimeo_ms"]
opaque setRecvTimeoutMs : @& UInt64 → @& UInt64 → BaseIO UInt64

@[extern "dsh_close_fd"]
opaque closeFd : @& UInt64 → BaseIO Unit

end Ffi