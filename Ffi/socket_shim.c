// Minimal POSIX TCP socket shim for the pure-Lean HTTP/1.1 client
// (t14 spike decision, Docs 9.2): loopback-only, fd-based, no TLS.
// The Lean side owns all HTTP framing; this shim only moves bytes.
#include <lean/lean.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/* ---------- t30: Windows (MinGW-w64 / UCRT) compatibility ----------
 * The Linux path is behavior-identical to the pre-t30 code: the
 * DSH_* macros expand to exactly the original expressions on POSIX.
 * On Windows, sockets are SOCKET handles (unsigned), close(2) is
 * closesocket(2), nonblocking is ioctlsocket(FIONBIO), SO_RCVTIMEO
 * takes a DWORD in milliseconds, and Winsock needs WSAStartup. */
#if defined(_WIN32)
#  include <winsock2.h>
#  include <ws2tcpip.h>
#  include <windows.h>
#  include <errno.h>
#  include <signal.h>
#  include <sys/types.h>
#  ifndef _SSIZE_T_DEFINED
typedef long long ssize_t; /* MinGW usually provides it; guard anyway */
#    define _SSIZE_T_DEFINED
#  endif
#  define DSH_SOCK(fd) ((SOCKET)(uintptr_t)(fd))
#  define DSH_CLOSE(fd) closesocket((SOCKET)(uintptr_t)(fd))
#  ifndef MSG_NOSIGNAL
#    define MSG_NOSIGNAL 0 /* no SIGPIPE concept on Windows */
#  endif
static int dsh_wsa_ready = 0;
static void dsh_wsa_init(void) {
    if (!dsh_wsa_ready) {
        WSADATA d;
        WSAStartup(MAKEWORD(2, 2), &d);
        dsh_wsa_ready = 1;
    }
}
static int dsh_set_nonblock(uint64_t fd) {
    u_long on = 1;
    return ioctlsocket((SOCKET)(uintptr_t)fd, FIONBIO, &on);
}
static int dsh_clear_nonblock(uint64_t fd) {
    u_long off = 0;
    return ioctlsocket((SOCKET)(uintptr_t)fd, FIONBIO, &off);
}
#else /* POSIX */
#  include <unistd.h>
#  include <errno.h>
#  include <fcntl.h>
#  include <sys/socket.h>
#  include <netinet/in.h>
#  include <arpa/inet.h>
#  include <sys/select.h>
#  include <netdb.h>
#  define DSH_SOCK(fd) ((int)(fd))
#  define DSH_CLOSE(fd) close((int)(fd))
static int dsh_set_nonblock(uint64_t fd) {
    int flags = fcntl((int)fd, F_GETFL, 0);
    return fcntl((int)fd, F_SETFL, flags | O_NONBLOCK);
}
static int dsh_clear_nonblock(uint64_t fd) {
    int flags = fcntl((int)fd, F_GETFL, 0);
    return fcntl((int)fd, F_SETFL, flags & ~O_NONBLOCK);
}
#endif

/* lean_bytearray_cptr is static inline in lean.h; byte-array data
   lives directly after the object header. */
static inline uint8_t *dsh_ba_ptr(lean_object *o) {
    return lean_sarray_cptr((lean_object *)(uintptr_t)o);
}

static struct sockaddr_in loopback_addr(uint16_t port) {
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    addr.sin_addr.s_addr = htonl(0x7f000001u); // 127.0.0.1
    return addr;
}

LEAN_EXPORT uint64_t dsh_socket_tcp(void) {
#ifdef _WIN32
    dsh_wsa_init();
    SOCKET s = socket(AF_INET, SOCK_STREAM, 0);
    if (s == INVALID_SOCKET) return (uint64_t)(int64_t)-1;
    return (uint64_t)s;
#else
    return (uint64_t)(int64_t)socket(AF_INET, SOCK_STREAM, 0);
#endif
}

LEAN_EXPORT uint64_t dsh_connect_loopback(uint64_t fd, uint64_t port) {
    // nonblocking connect + select with a 5s deadline, then back to blocking
    dsh_set_nonblock(fd);
    struct sockaddr_in addr = loopback_addr((uint16_t)port);
    int rc = connect(DSH_SOCK(fd), (struct sockaddr*)&addr, sizeof(addr));
#ifdef _WIN32
    if (rc != 0 && WSAGetLastError() != WSAEWOULDBLOCK) return (uint64_t)(int64_t)-1;
#else
    if (rc != 0 && errno != EINPROGRESS) return -1;
#endif
    fd_set wset;
    FD_ZERO(&wset);
    FD_SET(DSH_SOCK(fd), &wset);
    struct timeval tv;
    tv.tv_sec = 5;
    tv.tv_usec = 0;
    if (select((int)fd + 1, NULL, &wset, NULL, &tv) <= 0) return (uint64_t)(int64_t)-1;
    int soerr = 0;
    socklen_t len = sizeof(soerr);
    if (getsockopt(DSH_SOCK(fd), SOL_SOCKET, SO_ERROR, (char *)&soerr, &len) != 0 || soerr != 0) return (uint64_t)(int64_t)-1;
    dsh_clear_nonblock(fd);
    return 0;
}

/* t15: bind the IPv4 wildcard 0.0.0.0 (Haskell serveTcp binds all
   interfaces when no host is given). */
LEAN_EXPORT uint64_t dsh_bind_any(uint64_t fd, uint64_t port) {
    int one = 1;
    setsockopt((int)fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons((uint16_t)port);
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    return (uint64_t)(int64_t)bind(DSH_SOCK(fd), (struct sockaddr*)&addr, sizeof(addr));
}

/* t15: connect to an IPv4 dotted address (Lean resolves "localhost").
   Same nonblocking+select discipline as dsh_connect_loopback. */
LEAN_EXPORT uint64_t dsh_connect_ipv4(uint64_t fd, lean_object const *ip, uint64_t port) {
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons((uint16_t)port);
    if (inet_pton(AF_INET, lean_string_cstr((lean_object *)ip), &addr.sin_addr) != 1)
        return (uint64_t)(int64_t)-1;
    dsh_set_nonblock(fd);
    int rc = connect(DSH_SOCK(fd), (struct sockaddr*)&addr, sizeof(addr));
#ifdef _WIN32
    if (rc != 0 && WSAGetLastError() != WSAEWOULDBLOCK) return (uint64_t)(int64_t)-1;
#else
    if (rc != 0 && errno != EINPROGRESS) return (uint64_t)(int64_t)-1;
#endif
    fd_set wset;
    FD_ZERO(&wset);
    FD_SET(DSH_SOCK(fd), &wset);
    struct timeval tv;
    tv.tv_sec = 5;
    tv.tv_usec = 0;
    if (select((int)fd + 1, NULL, &wset, NULL, &tv) <= 0) return (uint64_t)(int64_t)-1;
    int soerr = 0;
    socklen_t len = sizeof(soerr);
    if (getsockopt(DSH_SOCK(fd), SOL_SOCKET, SO_ERROR, (char *)&soerr, &len) != 0 || soerr != 0) return (uint64_t)(int64_t)-1;
    dsh_clear_nonblock(fd);
    return 0;
}

/* t15: textual peer address "ip:port" of a connected/accepted socket,
   for connection logging; -1 on error. */
LEAN_EXPORT uint64_t dsh_peer_desc(uint64_t fd, uint8_t *out, uint64_t cap, uint64_t unused) {
    (void)unused;
    struct sockaddr_in addr;
    socklen_t len = sizeof(addr);
    if (getpeername((int)fd, (struct sockaddr*)&addr, &len) != 0) return (uint64_t)(int64_t)-1;
    char buf[64];
    snprintf(buf, sizeof(buf), "%s:%u", inet_ntoa(addr.sin_addr), (unsigned)ntohs(addr.sin_port));
    size_t n = strlen(buf);
    if (n >= cap) n = cap ? cap - 1 : 0;
    memcpy(out, buf, n);
    out[n] = 0;
    return (uint64_t)n;
}

/* t27: bind to an explicit IPv4 dotted address (resolved by the Lean
   layer via getaddrinfo, mirroring Haskell serveTcpOn's AI_PASSIVE
   resolution). Never falls back to the wildcard on failure — the
   caller treats -1 as a hard error. */
LEAN_EXPORT uint64_t dsh_bind_addr(uint64_t fd, lean_object const *ip, uint64_t port) {
    int one = 1;
    setsockopt((int)fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons((uint16_t)port);
    if (inet_pton(AF_INET, lean_string_cstr((lean_object *)ip), &addr.sin_addr) != 1)
        return (uint64_t)(int64_t)-1;
    return (uint64_t)(int64_t)bind(DSH_SOCK(fd), (struct sockaddr*)&addr, sizeof(addr));
}

LEAN_EXPORT uint64_t dsh_bind_loopback(uint64_t fd, uint64_t port) {
    int one = 1;
    setsockopt((int)fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    struct sockaddr_in addr = loopback_addr((uint16_t)port);
    return (uint64_t)(int64_t)bind(DSH_SOCK(fd), (struct sockaddr*)&addr, sizeof(addr));
}

LEAN_EXPORT uint64_t dsh_listen_fd(uint64_t fd) {
    return (uint64_t)(int64_t)listen(DSH_SOCK(fd), 16);
}

LEAN_EXPORT uint64_t dsh_accept_fd(uint64_t fd) {
#ifdef _WIN32
    SOCKET c = accept(DSH_SOCK(fd), NULL, NULL);
    if (c == INVALID_SOCKET) return (uint64_t)(int64_t)-1;
    return (uint64_t)c;
#else
    return (uint64_t)(int64_t)accept((int)fd, NULL, NULL);
#endif
}

LEAN_EXPORT uint64_t dsh_local_port(uint64_t fd) {
    struct sockaddr_in addr;
    socklen_t len = sizeof(addr);
    if (getsockname(DSH_SOCK(fd), (struct sockaddr*)&addr, &len) != 0) return (uint64_t)(int64_t)-1;
    return (uint64_t)ntohs(addr.sin_port);
}

LEAN_EXPORT uint64_t dsh_send_all(uint64_t fd, lean_object const *buf, uint64_t len, uint64_t unused) {
    uint8_t const *p = dsh_ba_ptr((lean_object *)buf);
    uint64_t off = 0;
    while (off < len) {
        ssize_t n = send(DSH_SOCK(fd), p + off, len - off, MSG_NOSIGNAL);
        if (n < 0) {
            if (errno == EINTR) continue;
            return (uint64_t)(int64_t)-1;
        }
        off += (uint64_t)n;
    }
    return (uint64_t)off;
    (void)unused;
}

LEAN_EXPORT uint64_t dsh_recv_some(uint64_t fd, lean_object *buf, uint64_t cap, uint64_t unused) {
    uint8_t *p = dsh_ba_ptr(buf);
    for (;;) {
        ssize_t n = recv(DSH_SOCK(fd), p, cap, 0);
        if (n < 0 && errno == EINTR) continue;
        return (uint64_t)(int64_t)n; // 0 = EOF, max = error
        (void)unused;
    }
}

LEAN_EXPORT uint64_t dsh_set_rcvtimeo_ms(uint64_t fd, uint64_t ms) {
#ifdef _WIN32
    /* Windows SO_RCVTIMEO takes a DWORD in milliseconds */
    DWORD ms32 = (DWORD)ms;
    return (uint64_t)(int64_t)setsockopt(DSH_SOCK(fd), SOL_SOCKET, SO_RCVTIMEO,
                                         (const char *)&ms32, sizeof(ms32));
#else
    struct timeval tv;
    tv.tv_sec = ms / 1000;
    tv.tv_usec = (ms % 1000) * 1000;
    return (uint64_t)(int64_t)setsockopt((int)fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
#endif
}

LEAN_EXPORT void dsh_close_fd(uint64_t fd) {
    if (fd >= 0) DSH_CLOSE(fd);
}

/* ---------- t16: accept-loop polling ---------- */

/* Wait until fd is readable or ms milliseconds elapse (select).
 * Returns 1 readable, 0 timeout, -1 error. Lets the Lean accept loop
 * poll instead of blocking forever in accept(2), so heartbeat tasks
 * get scheduled and EINTR-free signal checks happen between waits. */
LEAN_EXPORT uint64_t dsh_wait_readable(uint64_t fd, uint64_t ms, uint64_t unused) {
    (void)unused;
    fd_set rset;
    FD_ZERO(&rset);
    FD_SET(DSH_SOCK(fd), &rset);
    struct timeval tv;
    tv.tv_sec = ms / 1000;
    tv.tv_usec = (ms % 1000) * 1000;
    int rc = select((int)fd + 1, &rset, NULL, NULL, &tv);
    if (rc < 0) return (uint64_t)(int64_t)-1;
    return (uint64_t)(rc > 0 ? 1 : 0);
}

/* ---------- t16: hostname resolution ---------- */

/* Resolve an IPv4 host name (or pass through dotted literals) into the
 * caller's ByteArray. Registry URLs carry arbitrary host names, so the
 * HTTP client needs getaddrinfo; IPv4-only to match the shim's
 * sockaddr_in surface. Returns the string length, or -1. */
LEAN_EXPORT uint64_t dsh_resolve_host(lean_object *name, lean_object *outobj,
                                      uint64_t cap, uint64_t unused) {
    (void)unused;
    uint8_t *out = dsh_ba_ptr(outobj);
    struct addrinfo hints, *res = NULL;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
#ifdef _WIN32
    dsh_wsa_init();
#endif
    int rc = getaddrinfo(lean_string_cstr(name), NULL, &hints, &res);
    if (rc != 0 || !res) return (uint64_t)(int64_t)-1;
    struct sockaddr_in *a = (struct sockaddr_in *)res->ai_addr;
    char ip[INET_ADDRSTRLEN];
    if (!inet_ntop(AF_INET, &a->sin_addr, ip, sizeof(ip))) {
        freeaddrinfo(res);
        return (uint64_t)(int64_t)-1;
    }
    freeaddrinfo(res);
    size_t n = strlen(ip);
    if (n >= cap) n = cap ? cap - 1 : 0;
    memcpy(out, ip, n);
    out[n] = 0;
    return (uint64_t)n;
}

/* ---------- t16: SIGINT/SIGTERM handling ---------- */

/* Set without SA_RESTART so a blocked accept()/recv() returns EINTR and
 * the Lean accept loop can observe the flag and run cleanup. Only
 * async-signal-safe operations inside the handler. */
#ifndef _WIN32
#  include <signal.h>
#endif

static volatile sig_atomic_t dsh_signaled = 0;

static void dsh_on_exit_signal(int sig) {
    (void)sig;
    dsh_signaled = 1;
}

LEAN_EXPORT void dsh_install_exit_signals(uint64_t unused) {
    (void)unused;
#ifdef _WIN32
    /* no sigaction/SA_RESTART on Windows: plain signal() sets the same
     * handler; console events (Ctrl+C) deliver SIGINT; service stop is
     * a hard terminate (documented in the deploy notes) */
    signal(SIGINT, dsh_on_exit_signal);
    signal(SIGTERM, dsh_on_exit_signal);
#else
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = dsh_on_exit_signal;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = 0; /* no SA_RESTART: interrupt blocking calls */
    sigaction(SIGINT, &sa, NULL);
    sigaction(SIGTERM, &sa, NULL);
#endif
}

LEAN_EXPORT uint64_t dsh_signal_fired(uint64_t unused) {
    (void)unused;
    return (uint64_t)dsh_signaled;
}

#ifdef _WIN32
/* ---------- t30: argv on native Windows ----------
 * /proc/self/cmdline does not exist there. Split GetCommandLineA with a
 * minimal tokenizer (double quotes group, backslash-escapes are NOT
 * handled — sufficient for this CLI's flag surface). Writes each
 * argument NUL-separated into out (caller's ByteArray), returns
 * (argc << 32) | total_bytes_written. */
LEAN_EXPORT uint64_t dsh_win_argv(lean_object *outobj, uint64_t cap, uint64_t unused) {
    (void)unused;
    uint8_t *out = dsh_ba_ptr(outobj);
    const char *cl = GetCommandLineA();
    uint64_t n = 0, argc = 0;
    int inq = 0, started = 0;
    for (const char *p = cl; ; p++) {
        char c = *p;
        if (c == '"') { inq = !inq; continue; }
        int sep = (c == 0) || (!inq && (c == ' ' || c == '\t'));
        if (!sep) {
            if (!started) { started = 1; }
            if (n + 1 < cap) out[n++] = (uint8_t)c;
        } else if (started) {
            if (n + 1 < cap) out[n++] = 0;
            argc++;
            started = 0;
            if (c == 0) break;
        } else if (c == 0) {
            break;
        }
    }
    if (n + 1 < cap) out[n] = 0;
    return (argc << 32) | n;
}
#else
/* POSIX: never called (getArgsIO reads /proc/self/cmdline); present so
 * the same Ffi.Socket decl links on both platforms. */
LEAN_EXPORT uint64_t dsh_win_argv(lean_object *outobj, uint64_t cap, uint64_t unused) {
    (void)outobj; (void)cap; (void)unused;
    return 0;
}
#endif

/* t16: terminate the process (the heartbeat task thread would
 * otherwise keep the runtime alive after the accept loop returns). */
LEAN_EXPORT void dsh_exit(uint64_t code, uint64_t unused) {
    (void)unused;
    exit((int)code);
}