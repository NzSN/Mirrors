// Minimal POSIX TCP socket shim for the pure-Lean HTTP/1.1 client
// (t14 spike decision, Docs 9.2): loopback-only, fd-based, no TLS.
// The Lean side owns all HTTP framing; this shim only moves bytes.
#include <lean/lean.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/select.h>

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
    return (uint64_t)(int64_t)socket(AF_INET, SOCK_STREAM, 0);
}

LEAN_EXPORT uint64_t dsh_connect_loopback(uint64_t fd, uint64_t port) {
    // nonblocking connect + select with a 5s deadline, then back to blocking
    int flags = fcntl((int)fd, F_GETFL, 0);
    fcntl((int)fd, F_SETFL, flags | O_NONBLOCK);
    struct sockaddr_in addr = loopback_addr((uint16_t)port);
    int rc = connect((int)fd, (struct sockaddr*)&addr, sizeof(addr));
    if (rc != 0 && errno != EINPROGRESS) return -1;
    fd_set wset;
    FD_ZERO(&wset);
    FD_SET((int)fd, &wset);
    struct timeval tv;
    tv.tv_sec = 5;
    tv.tv_usec = 0;
    if (select((int)fd + 1, NULL, &wset, NULL, &tv) <= 0) return (uint64_t)(int64_t)-1;
    int soerr = 0;
    socklen_t len = sizeof(soerr);
    if (getsockopt((int)fd, SOL_SOCKET, SO_ERROR, &soerr, &len) != 0 || soerr != 0) return (uint64_t)(int64_t)-1;
    fcntl((int)fd, F_SETFL, flags);
    return 0;
}

LEAN_EXPORT uint64_t dsh_bind_loopback(uint64_t fd, uint64_t port) {
    int one = 1;
    setsockopt((int)fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    struct sockaddr_in addr = loopback_addr((uint16_t)port);
    return (uint64_t)(int64_t)bind((int)fd, (struct sockaddr*)&addr, sizeof(addr));
}

LEAN_EXPORT uint64_t dsh_listen_fd(uint64_t fd) {
    return (uint64_t)(int64_t)listen((int)fd, 16);
}

LEAN_EXPORT uint64_t dsh_accept_fd(uint64_t fd) {
    return (uint64_t)(int64_t)accept((int)fd, NULL, NULL);
}

LEAN_EXPORT uint64_t dsh_local_port(uint64_t fd) {
    struct sockaddr_in addr;
    socklen_t len = sizeof(addr);
    if (getsockname((int)fd, (struct sockaddr*)&addr, &len) != 0) return (uint64_t)(int64_t)-1;
    return (uint64_t)ntohs(addr.sin_port);
}

LEAN_EXPORT uint64_t dsh_send_all(uint64_t fd, lean_object const *buf, uint64_t len, uint64_t unused) {
    uint8_t const *p = dsh_ba_ptr((lean_object *)buf);
    uint64_t off = 0;
    while (off < len) {
        ssize_t n = send((int)fd, p + off, len - off, MSG_NOSIGNAL);
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
        ssize_t n = recv((int)fd, p, cap, 0);
        if (n < 0 && errno == EINTR) continue;
        return (uint64_t)(int64_t)n; // 0 = EOF, max = error
        (void)unused;
    }
}

LEAN_EXPORT uint64_t dsh_set_rcvtimeo_ms(uint64_t fd, uint64_t ms) {
    struct timeval tv;
    tv.tv_sec = ms / 1000;
    tv.tv_usec = (ms % 1000) * 1000;
    return (uint64_t)(int64_t)setsockopt((int)fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
}

LEAN_EXPORT void dsh_close_fd(uint64_t fd) {
    if (fd >= 0) close((int)fd);
}