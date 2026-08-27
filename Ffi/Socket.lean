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

/-- t27: bind to an explicit IPv4 dotted address (no wildcard
fallback; failure is a hard error at the caller). -/
@[extern "dsh_bind_addr"]
opaque bindAddr : @& UInt64 → @& String → @& UInt64 → BaseIO UInt64

/-- t15: bind the IPv4 wildcard (all interfaces). -/
@[extern "dsh_bind_any"]
opaque bindAny : @& UInt64 → @& UInt64 → BaseIO UInt64

/-- t15: connect to an IPv4 dotted address. -/
@[extern "dsh_connect_ipv4"]
opaque connectIpv4 : @& UInt64 → @& String → @& UInt64 → BaseIO UInt64

/-- t15: textual "ip:port" of the socket's peer; @some "" never —
returns @none on failure. -/
@[extern "dsh_peer_desc"]
opaque peerDescRaw : @& UInt64 → @& ByteArray → UInt64 → BaseIO UInt64

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

/-- t16: resolve an IPv4 host name (getaddrinfo) into @buf@; returns
the dotted-address string length, or the fd sentinel on failure. -/
@[extern "dsh_resolve_host"]
opaque resolveHostRaw : @& String → @& ByteArray → UInt64 → BaseIO UInt64

/-- t16: wait until @fd@ is readable or @ms@ ms elapse; returns 1
readable / 0 timeout / fdError sentinel on select failure. -/
@[extern "dsh_wait_readable"]
opaque waitReadable : @& UInt64 → @& UInt64 → BaseIO UInt64

/-- t16: install SIGINT/SIGTERM handlers (no SA_RESTART, so blocked
accept/recv calls return EINTR); POSIX only, like the Haskell server.
t33 DID: returns UInt64 (not Unit) so the C shim's value-return
register is boxed as a plain scalar, never misread as a boxed result
(see closeFd's identical root-fix comment). -/
@[extern "dsh_install_exit_signals"]
opaque installExitSignals : BaseIO UInt64

/-- t16: @1@ once SIGINT or SIGTERM has been delivered. -/
@[extern "dsh_signal_fired"]
opaque signalFired : BaseIO UInt64

/-- t16: terminate the process with @code@ (POSIX exit(3); used after
signal cleanup because a live dedicated task keeps the runtime alive).
t33 DID: UInt64 return (never observed — exit never returns — but keeps
the extern prototype consistent with the uint64_t C shim). -/
@[extern "dsh_exit"]
opaque exitWith : UInt64 → BaseIO UInt64

/-- t30 (Windows only): argv via GetCommandLineA. Writes NUL-separated
args into the buffer; returns (argc <<< 32) ||| bytesWritten. The
Linux build never links this (getArgsIO reads /proc/self/cmdline
there); the decl exists so the same Shell.Cli source compiles on both
platforms. -/
@[extern "dsh_win_argv"]
opaque winArgvRaw : @& ByteArray → @& UInt64 → BaseIO UInt64

end Ffi