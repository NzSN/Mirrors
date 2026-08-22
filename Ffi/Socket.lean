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
-/

namespace Ffi

/-- Raw fd-based TCP socket operations (all loopback-only). Errors are
@-1@-style integers from the shim; @dsh_close_fd@ is total. -/
@[extern "dsh_socket_tcp"]
opaque tcpSocket : BaseIO Int

@[extern "dsh_connect_loopback"]
opaque connectLoopback : @& Int → @& Int → BaseIO Int

@[extern "dsh_bind_loopback"]
opaque bindLoopback : @& Int → @& Int → BaseIO Int

@[extern "dsh_listen_fd"]
opaque listenFd : @& Int → BaseIO Int

@[extern "dsh_accept_fd"]
opaque acceptFd : @& Int → BaseIO Int

@[extern "dsh_local_port"]
opaque localPort : @& Int → BaseIO Int

@[extern "dsh_send_all"]
opaque sendAll : @& Int → @& ByteArray → BaseIO Int

@[extern "dsh_recv_some"]
opaque recvSome : @& Int → @& ByteArray → BaseIO Int

@[extern "dsh_set_rcvtimeo_ms"]
opaque setRecvTimeoutMs : @& Int → @& Int → BaseIO Int

@[extern "dsh_close_fd"]
opaque closeFd : @& Int → BaseIO Unit

end Ffi
