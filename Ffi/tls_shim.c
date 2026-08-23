/* t15: minimal OpenSSL shim for the mTLS transport (design 5.4/9.1).
 *
 * Surface deliberately tiny and line-auditable:
 *   - server/client SSL_CTX creation with the locked-down policy:
 *     TLS 1.3 ONLY, client certificates REQUIRED (server side),
 *     CA-anchored chain verification, SAN required on the server cert,
 *     key file must not be group/other readable;
 *   - accept/connect (handshake), read/write, graceful shutdown;
 *   - fingerprint + expiry helpers (SHA-256 hex, days remaining).
 *
 * Ownership: SSL_CTX and SSL objects are returned to Lean as external
 * objects whose finalizer frees them (the only GC finalizer backstop in
 * the code base, per design 9.7). dsh_tls_close only performs a
 * best-effort close_notify shutdown; memory is released by the
 * finalizer, so close-then-GC is safe.
 *
 * Errors: NULL / -1 returns; human-readable reason via dsh_tls_errmsg.
 */
#include <lean/lean.h>
#include <openssl/ssl.h>
#include <openssl/err.h>
#include <openssl/x509.h>
#include <openssl/x509v3.h>
#include <openssl/pem.h>
#include <openssl/bio.h>
#include <sys/stat.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <string.h>
#include <stdint.h>
#include <time.h>
#include <stdio.h>

/* ---------- external-object classes (finalizer backstop, 9.7) ---------- */

static lean_external_class *g_ctx_class = NULL;
static lean_external_class *g_ssl_class = NULL;

static void ctx_finalizer(void *p) { SSL_CTX_free((SSL_CTX *)p); }
static void ssl_finalizer(void *p) {
    SSL *s = (SSL *)p;
    /* B1 (review): failure sentinels are NULL-payload externals of this
     * class; SSL_shutdown(NULL) is not a no-op and would segfault in the
     * GC finalizer. Guard first. */
    if (!s) return;
    /* best effort; the socket itself is closed by the Lean layer */
    SSL_shutdown(s);
    SSL_free(s);
}
static void noop_foreach(void *p, lean_object *o) { (void)p; (void)o; }

static lean_external_class *ctx_class(void) {
    if (!g_ctx_class)
        g_ctx_class = lean_register_external_class(ctx_finalizer, noop_foreach);
    return g_ctx_class;
}
static lean_external_class *ssl_class(void) {
    if (!g_ssl_class)
        g_ssl_class = lean_register_external_class(ssl_finalizer, noop_foreach);
    return g_ssl_class;
}

/* ---------- Option boxing helpers ---------- */

/* Failure sentinel: an external object with NULL payload. Lean checks
   via dsh_tls_is_null (avoids hand-building Option ctors at the ABI
   boundary, which is representation-sensitive). */
static lean_object *mk_null_ext(lean_external_class *cls) {
    return lean_alloc_external(cls, NULL);
}

/* ---------- error reporting ---------- */

/* m4 (review): g_err is a single global — valid under today's
 * single-threaded, sequential accept-loop usage (one handshake at a
 * time, errmsg consumed immediately after a failed call). Before any
 * concurrent handshake path lands, make this thread-local. */
static char g_err[512];

static void set_err(const char *msg) {
    unsigned long e = ERR_peek_last_error();
    if (e) {
        char buf[256];
        ERR_error_string_n(e, buf, sizeof(buf));
        snprintf(g_err, sizeof(g_err), "%s: %s", msg, buf);
    } else {
        snprintf(g_err, sizeof(g_err), "%s", msg);
    }
    ERR_clear_error();
}

LEAN_EXPORT uint64_t dsh_tls_errmsg(lean_object *outobj, uint64_t cap, uint64_t unused) {
    (void)unused;
    uint8_t *out = lean_sarray_cptr(outobj);
    size_t n = strlen(g_err);
    if (n >= cap) n = cap ? cap - 1 : 0;
    memcpy(out, g_err, n);
    out[n] = 0;
    return (uint64_t)n;
}

/* ---------- policy checks shared by both roles ---------- */

static int key_perms_ok(const char *key_file) {
    struct stat st;
    if (stat(key_file, &st) != 0) { set_err("key file not found"); return 0; }
    if (st.st_mode & (S_IRGRP|S_IWGRP|S_IXGRP|S_IROTH|S_IWOTH|S_IXOTH)) {
        snprintf(g_err, sizeof(g_err),
                 "key file %s must not be accessible by group/other (chmod 0600)",
                 key_file);
        return 0;
    }
    return 1;
}

static STACK_OF(X509) *load_chain(const char *file) {
    BIO *b = BIO_new_file(file, "rb");
    if (!b) { set_err("cannot open certificate file"); return NULL; }
    STACK_OF(X509) *sk = sk_X509_new_null();
    X509 *x;
    while ((x = PEM_read_bio_X509(b, NULL, NULL, NULL)) != NULL)
        sk_X509_push(sk, x);
    BIO_free(b);
    if (sk_X509_num(sk) == 0) {
        sk_X509_free(sk);
        snprintf(g_err, sizeof(g_err), "no certificates in %s", file);
        return NULL;
    }
    return sk;
}

/* m2 (review): only DNS and IP SAN entries count; email/URI/other
 * GeneralNames must not satisfy the SAN-required policy. */
static int leaf_has_san(X509 *leaf) {
    GENERAL_NAMES *sans = X509_get_ext_d2i(leaf, NID_subject_alt_name, NULL, NULL);
    int found = 0;
    if (sans) {
        for (int i = 0; i < sk_GENERAL_NAME_num(sans); i++) {
            GENERAL_NAME *gn = sk_GENERAL_NAME_value(sans, i);
            if (gn->type == GEN_DNS || gn->type == GEN_IPADD) { found = 1; break; }
        }
        GENERAL_NAMES_free(sans);
    }
    return found;
}

static X509_STORE *open_store(const char *ca_file) {
    X509_STORE *st = X509_STORE_new();
    if (!st) { set_err("X509_STORE_new failed"); return NULL; }
    if (X509_STORE_load_file(st, ca_file) != 1) {
        X509_STORE_free(st);
        snprintf(g_err, sizeof(g_err), "no certificates in CA file %s", ca_file);
        return NULL;
    }
    return st;
}

/* Verify a chain (leaf first, as stored in the PEM file) against the
 * CA store: every link must verify, ending at a trusted CA. Mirrors the
 * Haskell validateServerCertChain structural check. */
static int chain_validates(X509_STORE *store, STACK_OF(X509) *chain) {
    X509_STORE_CTX *c = X509_STORE_CTX_new();
    if (!c) { set_err("X509_STORE_CTX_new failed"); return 0; }
    /* startup validation is TRUST and SHAPE only: expiry is a
     * warn-only path (warnIfNearExpiry / the expired-cert negative
     * test), so the time check is disabled here. Handshake-time
     * verification stays strict. */
    X509_STORE_set_flags(store, X509_V_FLAG_NO_CHECK_TIME);
    /* untrusted = everything after the leaf; the leaf goes in slots */
    STACK_OF(X509) *untrusted = sk_X509_new_null();
    for (int i = 1; i < sk_X509_num(chain); i++)
        sk_X509_push(untrusted, sk_X509_value(chain, i));
    int ok = X509_STORE_CTX_init(c, store, sk_X509_value(chain, 0), untrusted) == 1
          && X509_verify_cert(c) == 1;
    X509_STORE_CTX_free(c);
    sk_X509_free(untrusted);
    if (!ok) set_err("certificate chain does not validate against the CA file");
    return ok;
}

static SSL_CTX *base_ctx(const SSL_METHOD *m) {
    SSL_CTX *c = SSL_CTX_new(m);
    if (!c) { set_err("SSL_CTX_new failed"); return NULL; }
    /* TLS 1.3 only — the #1 reviewed policy knob (design 9.1) */
    if (!SSL_CTX_set_min_proto_version(c, TLS1_3_VERSION) ||
        !SSL_CTX_set_max_proto_version(c, TLS1_3_VERSION)) {
        SSL_CTX_free(c);
        set_err("cannot pin protocol version to TLS 1.3");
        return NULL;
    }
    return c;
}

/* ---------- server context ---------- */

LEAN_EXPORT lean_object *dsh_tls_server_ctx(lean_object *cert, lean_object *key,
                                            lean_object *ca, uint64_t unused) {
    (void)unused;
    const char *certf = lean_string_cstr(cert);
    const char *keyf = lean_string_cstr(key);
    const char *caf = lean_string_cstr(ca);

    /* M1 (review): the key-permission policy applies to BOTH roles;
     * previously it was client-only, so the server loaded any
     * group-readable key file. */
    if (!key_perms_ok(keyf)) return mk_null_ext(ctx_class());

    STACK_OF(X509) *chain = load_chain(certf);
    /* m3 (review): fail with the real error when the cert file is
     * missing/unreadable/empty instead of falling through to a
     * misleading "no SAN". load_chain has already set g_err. */
    if (!chain) return mk_null_ext(ctx_class());
    X509 *leaf = sk_X509_value(chain, 0);
    if (!leaf_has_san(leaf)) {
        snprintf(g_err, sizeof(g_err),
                 "server certificate %s has no Subject Alternative Name (DNS or IP)", certf);
        sk_X509_pop_free(chain, X509_free);
        return mk_null_ext(ctx_class());
    }
    X509_STORE *store = open_store(caf);
    if (!store) { sk_X509_pop_free(chain, X509_free); return mk_null_ext(ctx_class()); }
    int chain_ok = chain_validates(store, chain);
    sk_X509_pop_free(chain, X509_free);
    if (!chain_ok) { X509_STORE_free(store); return mk_null_ext(ctx_class()); }

    SSL_CTX *c = base_ctx(TLS_server_method());
    if (SSL_CTX_use_certificate_chain_file(c, certf) != 1 ||
        SSL_CTX_use_PrivateKey_file(c, keyf, SSL_FILETYPE_PEM) != 1 ||
        SSL_CTX_check_private_key(c) != 1) {
        SSL_CTX_free(c); X509_STORE_free(store);
        set_err("cannot load server credentials");
        return mk_null_ext(ctx_class());
    }
    if (SSL_CTX_load_verify_locations(c, caf, NULL) != 1) {
        SSL_CTX_free(c); X509_STORE_free(store);
        set_err("cannot load CA file for verification");
        return mk_null_ext(ctx_class());
    }
    /* client certificates REQUIRED: reject handshakes without one */
    SSL_CTX_set_verify(c, SSL_VERIFY_PEER | SSL_VERIFY_FAIL_IF_NO_PEER_CERT, NULL);
    X509_STORE_free(store); /* CTX holds its own reference */
    return lean_alloc_external(ctx_class(), c);
}

/* ---------- client context ---------- */

LEAN_EXPORT lean_object *dsh_tls_client_ctx(lean_object *cert, lean_object *key,
                                            lean_object *ca, uint64_t unused) {
    (void)unused;
    const char *certf = lean_string_cstr(cert);
    const char *keyf = lean_string_cstr(key);
    const char *caf = lean_string_cstr(ca);
    if (!key_perms_ok(keyf)) return mk_null_ext(ctx_class());

    SSL_CTX *c = base_ctx(TLS_client_method());
    if (!c) return mk_null_ext(ctx_class());
    if (SSL_CTX_use_certificate_chain_file(c, certf) != 1 ||
        SSL_CTX_use_PrivateKey_file(c, keyf, SSL_FILETYPE_PEM) != 1 ||
        SSL_CTX_check_private_key(c) != 1) {
        SSL_CTX_free(c);
        set_err("cannot load client credentials");
        return mk_null_ext(ctx_class());
    }
    if (SSL_CTX_load_verify_locations(c, caf, NULL) != 1) {
        SSL_CTX_free(c);
        set_err("cannot load CA file for verification");
        /* m7 (review): a CTX failure must carry the CTX class, not the
         * SSL class (is_null accepts both, but keep it honest) */
        return mk_null_ext(ctx_class());
    }
    /* server chain verified against the CA; hostname (SAN) is pinned
     * per-connection via SSL_set1_host in dsh_tls_connect */
    SSL_CTX_set_verify(c, SSL_VERIFY_PEER, NULL);
    return lean_alloc_external(ctx_class(), c);
}

/* m8 (review): only ever applied to values produced by this shim
 * (external objects or the NULL sentinel); a hypothetical call on the
 * .mk constructor inhabitant would be a programming error. */
LEAN_EXPORT uint64_t dsh_tls_is_null(lean_object *o, uint64_t unused) {
    (void)unused;
    lean_external_class *cls = lean_get_external_class(o);
    void *p = lean_get_external_data(o);
    return (cls == ctx_class() || cls == ssl_class()) && p == NULL ? 1 : 0;
}

/* ---------- handshake / IO ---------- */

LEAN_EXPORT lean_object *dsh_tls_accept(lean_object *ctx, uint64_t fd, uint64_t unused) {
    (void)unused;
    SSL_CTX *c = (SSL_CTX *)lean_get_external_data(ctx);
    SSL *s = SSL_new(c);
    if (!s) { set_err("SSL_new failed"); return mk_null_ext(ssl_class()); }
    if (SSL_set_fd(s, (int)fd) != 1) { SSL_free(s); set_err("SSL_set_fd failed"); return mk_null_ext(ssl_class()); }
    int r = SSL_accept(s);
    if (r != 1) {
        set_err("TLS accept (handshake) failed");
        SSL_free(s);
        return mk_null_ext(ssl_class());
    }
    return lean_alloc_external(ssl_class(), s);
}

LEAN_EXPORT lean_object *dsh_tls_connect(lean_object *ctx, lean_object *host,
                                         uint64_t fd, uint64_t unused) {
    (void)unused;
    SSL_CTX *c = (SSL_CTX *)lean_get_external_data(ctx);
    SSL *s = SSL_new(c);
    if (!s) { set_err("SSL_new failed"); return mk_null_ext(ssl_class()); }
    if (SSL_set_fd(s, (int)fd) != 1) { SSL_free(s); set_err("SSL_set_fd failed"); return mk_null_ext(ssl_class()); }
    /* M3 (review): hostname/IP pinning parity with the Haskell tls
     * package (x509-validation): X509_check_host (what SSL_set1_host
     * drives) never matches iPAddress SANs, and OpenSSL falls back to
     * the Subject CN when no dNSName SAN exists. Pin via the verify
     * params instead: IP literal -> set1_ip_asc, else set1_host, and
     * NEVER_CHECK_SUBJECT in both cases (SAN-only policy).
     *
     * Accepted divergence: wildcard matching. X509_check_host matches a
     * wildcard in the LEFTMOST label only; x509-validation matches a
     * wildcard anywhere within a label. Stricter is fail-closed and
     * safe; documented rather than reimplemented. */
    {
        X509_VERIFY_PARAM *param = SSL_get0_param(s);
        struct in_addr a4;
        struct in6_addr a6;
        const char *h = lean_string_cstr(host);
        int ok;
        if (inet_pton(AF_INET, h, &a4) == 1 || inet_pton(AF_INET6, h, &a6) == 1)
            ok = X509_VERIFY_PARAM_set1_ip_asc(param, h) == 1;
        else
            ok = X509_VERIFY_PARAM_set1_host(param, h, 0) == 1;
        if (!ok) { SSL_free(s); set_err("cannot set expected peer name"); return mk_null_ext(ssl_class()); }
        X509_VERIFY_PARAM_set_hostflags(param, X509_CHECK_FLAG_NEVER_CHECK_SUBJECT);
    }
    int r = SSL_connect(s);
    if (r != 1) {
        set_err("TLS connect (handshake) failed");
        SSL_free(s);
        return mk_null_ext(ssl_class());
    }
    return lean_alloc_external(ssl_class(), s);
}

LEAN_EXPORT uint64_t dsh_tls_write_all(lean_object *ssl, lean_object *bufobj, uint64_t len,
                                       uint64_t unused) {
    (void)unused;
    SSL *s = (SSL *)lean_get_external_data(ssl);
    const uint8_t *buf = lean_sarray_cptr(bufobj);
    uint64_t off = 0;
    while (off < len) {
        int n = SSL_write(s, buf + off, (size_t)(len - off));
        if (n <= 0) { set_err("TLS write failed"); return (uint64_t)(int64_t)-1; }
        off += (uint64_t)n;
    }
    return off;
}

LEAN_EXPORT uint64_t dsh_tls_read(lean_object *ssl, lean_object *bufobj, uint64_t cap,
                                  uint64_t unused) {
    (void)unused;
    SSL *s = (SSL *)lean_get_external_data(ssl);
    uint8_t *buf = lean_sarray_cptr(bufobj);
    /* m5 (review): WANT_READ/WANT_WRITE spin assumes a BLOCKING fd
     * (every socket this shim sees is blocking). Do not set
     * O_NONBLOCK on fds passed here without reworking this loop. */
    for (;;) {
        int n = SSL_read(s, buf, (size_t)cap);
        if (n > 0) return (uint64_t)n;
        int err = SSL_get_error(s, n);
        if (err == SSL_ERROR_ZERO_RETURN) return 0; /* clean EOF */
        if (err == SSL_ERROR_WANT_READ || err == SSL_ERROR_WANT_WRITE) continue;
        set_err("TLS read failed");
        return (uint64_t)(int64_t)-1;
    }
}

/* best-effort close_notify; memory freed by the GC finalizer.
 * m7 (interop t17): on a blocking fd SSL_shutdown blocks waiting for the
 * peer's close_notify even after ours was sent — and the session loop has
 * usually already consumed the peer's via SSL_read, so the sequential
 * accept server wedges here until the peer's TCP socket dies (MirrorECMA
 * re-opens one connection per scenario, so the whole matrix stalls).
 * Make the shutdown unidirectional and non-blocking: flip the BIOs to
 * nbio, send our close_notify, restore. */
LEAN_EXPORT uint64_t dsh_tls_close(lean_object *ssl, uint64_t unused) {
    (void)unused;
    SSL *s = (SSL *)lean_get_external_data(ssl);
    BIO *rbio = SSL_get_rbio(s);
    BIO *wbio = SSL_get_wbio(s);
    /* every fd this shim sees is blocking (see dsh_tls_read), so a plain
     * set/restore is safe; BIO_get_nbio is a header macro, not a symbol */
    if (rbio != NULL) BIO_set_nbio(rbio, 1);
    if (wbio != NULL) BIO_set_nbio(wbio, 1);
    SSL_shutdown(s);
    if (rbio != NULL) BIO_set_nbio(rbio, 0);
    if (wbio != NULL) BIO_set_nbio(wbio, 0);
    ERR_clear_error();
    return 0;
}

/* ---------- fingerprints / expiry ---------- */

static int sha256_hex(const unsigned char *d, size_t n, uint8_t *out) {
    unsigned char h[32];
    if (!EVP_Digest(d, n, h, NULL, EVP_sha256(), NULL)) return -1;
    static const char hx[] = "0123456789abcdef";
    for (int i = 0; i < 32; i++) {
        out[2 * i] = (uint8_t)hx[h[i] >> 4];
        out[2 * i + 1] = (uint8_t)hx[h[i] & 15];
    }
    out[64] = 0;
    return 0;
}

static int fp_of_x509(X509 *x, uint8_t *out) {
    unsigned char *der = NULL;
    int n = i2d_X509(x, &der);
    if (n <= 0) { set_err("i2d_X509 failed"); return -1; }
    int r = sha256_hex(der, (size_t)n, out);
    OPENSSL_free(der);
    return r;
}

/* SHA-256 fingerprint of the peer's leaf certificate on a live
 * connection; -1 if the peer presented no certificate. */
LEAN_EXPORT uint64_t dsh_tls_peer_fp(lean_object *ssl, lean_object *outobj, uint64_t unused) {
    (void)unused;
    uint8_t *out65 = lean_sarray_cptr(outobj);
    SSL *s = (SSL *)lean_get_external_data(ssl);
    X509 *peer = SSL_get1_peer_certificate(s);
    if (!peer) { set_err("peer presented no certificate"); return (uint64_t)(int64_t)-1; }
    int r = fp_of_x509(peer, out65);
    X509_free(peer);
    return r == 0 ? 0 : (uint64_t)(int64_t)-1;
}

/* SHA-256 fingerprint of the first certificate in a PEM file;
 * -1 if the file has none. */
LEAN_EXPORT uint64_t dsh_tls_cert_fp_file(lean_object *path, lean_object *outobj, uint64_t unused) {
    (void)unused;
    uint8_t *out65 = lean_sarray_cptr(outobj);
    STACK_OF(X509) *chain = load_chain(lean_string_cstr(path));
    if (!chain) return (uint64_t)(int64_t)-1;
    int r = fp_of_x509(sk_X509_value(chain, 0), out65);
    sk_X509_pop_free(chain, X509_free);
    return r == 0 ? 0 : (uint64_t)(int64_t)-1;
}

/* Days until the first certificate in a PEM file expires (negative if
 * expired); -1000000 if the file has no certificates. */
LEAN_EXPORT uint64_t dsh_tls_cert_days(lean_object *path, uint64_t unused) {
    (void)unused;
    STACK_OF(X509) *chain = load_chain(lean_string_cstr(path));
    if (!chain) return (uint64_t)(int64_t)-1000000;
    X509 *leaf = sk_X509_value(chain, 0);
    const ASN1_TIME *not_after = X509_get0_notAfter(leaf);
    struct tm tmv;
    time_t expiry;
    if (!ASN1_TIME_to_tm(not_after, &tmv)) {
        sk_X509_pop_free(chain, X509_free);
        set_err("bad notAfter in certificate");
        return (uint64_t)(int64_t)-1000000;
    }
    expiry = timegm(&tmv);
    time_t now = time(NULL);
    sk_X509_pop_free(chain, X509_free);
    long days = (long)((expiry - now) / 86400);
    return (uint64_t)(int64_t)days;
}