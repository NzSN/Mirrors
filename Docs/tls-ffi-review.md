# TLS FFI shim security review (t25, design doc section 9.1 target #1)

Scope: Ffi/tls_shim.c, Ffi/Tls.lean, Shell/Transport/Tls.lean,
tools/TransportSpec.lean, against the Haskell reference
(Protocol/Transport/Tls.hs, tls/crypton) at ModelMirros@3496251.
Review method: full manual read of all four files; OpenSSL 3.x
semantics checked against the documented behavior of
SSL_CTX_set_min/max_proto_version, SSL_CTX_set_verify, SSL_set1_host,
X509_check_host, SSL_get1_peer_certificate, SSL_set_fd ownership,
and the Lean external-object ABI.

Verdict: 1 blocker, 3 major, 8 minor. The core policy (TLS 1.3 pin,
mandatory client certs on the server ctx, CA-anchored verification,
fingerprint correctness) is enforced in the right places; the blocker
is a GC-time crash in the failure sentinel path, and the majors are a
missing server-side key-permission check (with a vacuous test), an
expired-certificate warning that can never fire, and a hostname/IP
SAN parity gap.

## Findings

### BLOCKER

**B1. Failure sentinels crash the GC finalizer (NULL SSL into
SSL_shutdown).** dsh_tls_accept and dsh_tls_connect return
mk_null_ext(ssl_class()) on handshake failure: an *external object
with NULL payload*. That object is an ordinary Lean value handed back
to the Lean layer (tlsServe / connectTlsPinned check sslIsNull, then
drop it). When it is collected, ssl_finalizer runs
SSL_shutdown((SSL*)NULL) before SSL_free - SSL_shutdown does not
accept NULL and dereferences it. Every rejected handshake in the
long-running accept loop therefore arms a segfault at an arbitrary
later GC point. Reproduce trivially: run the tls server, point an
openssl s_client without a client cert at it (the spec does exactly
this), force a GC, crash. Fix: first line of ssl_finalizer must be
`if (!s) return;`. (ctx_finalizer is safe: SSL_CTX_free(NULL) is a
documented no-op.)

### MAJOR

**M1. Server-side key-permission check is missing, and the existing
test for it is vacuous.** dsh_tls_client_ctx calls key_perms_ok
(rejects group/other-readable key files), but dsh_tls_server_ctx
never does - the server loads any key file regardless of mode,
diverging from the documented policy ("key files readable by
group/other are rejected") and from the Haskell side, which checks
both roles. Worse, tools/TransportSpec.lean case "server ctx
rejected: group-readable key" uses certFile := nosan.crt +
nosan.key (chmod 640): the nosan cert is rejected by the SAN rule
first, so the test passes for the wrong reason and would stay green
even with the check deleted. Fix: call key_perms_ok(keyf) in
dsh_tls_server_ctx before anything else, and rewrite the test to use
the good server cert with a chmod-640 copy of server.key.

**M2. Expired-certificate warnings can never fire (UInt64-to-Nat
wrap).** The C shim returns days as (uint64)(int64)days (negative
when expired); certDaysRemaining does `some d.toNat`, which turns a
negative days (e.g. -3 = 0xFFFF...FFFD) into a huge Nat. Then
warnIfNearExpiry compares `days < 7` (false for huge) and `days < 0`
- impossible for a Nat, so the "is expired" branch is dead code. Net
effect: an expired server/client certificate produces NO warning at
startup. Fix in the Lean wrapper: reinterpret the UInt64 as a signed
value (negative branch when the high bit is set) and keep Int.

**M3. Hostname pinning does not cover IP SANs, and OpenSSL falls
back to CN when no DNS SAN exists - both diverge from the Haskell
tls package.** dsh_tls_connect pins only via SSL_set1_host:
(a) X509_check_host never matches iPAddress SAN entries, so a
client connecting by IP literal (the transport passes `host`, not the
resolved 127.0.0.1) fails closed against a cert whose SAN is
IP:127.0.0.1 - the shim comment "covers SAN DNS/IP entries" is
wrong; (b) when a cert has no dNSName SAN at all, OpenSSL checks the
Subject CN unless X509_CHECK_FLAG_NEVER_CHECK_SUBJECT is set, while
x509-validation (tls package) requires SAN. Both are fail-closed or
CN-tolerant rather than exploitable, but they are parity and policy
divergences. Fix: use X509_VERIFY_PARAM_set1_ip_asc when host parses
as an IP, set NEVER_CHECK_SUBJECT, and document the wildcard-rule
differences (X509_check_host accepts leftmost-label wildcards,
x509-validation accepts wildcards anywhere in the label) as an
accepted divergence or align them.
### MINOR

**m1. load_chain leaks every X509 it reads.** sk_X509_free frees the
stack container only; the pushed X509 objects leak. Callers are
configuration-time only (server/client ctx creation, fingerprint,
days), so the leak is bounded, but dsh_tls_cert_fp_file /
dsh_tls_cert_days are exposed per-call - use sk_X509_pop_free.

**m2. leaf_has_san accepts any GeneralName.** It counts email/URI/other
SANs too, while the error message (and the Haskell policy) say DNS or
IP. A server cert with only an email SAN passes startup. Filter to
GenDNS/GenIPADD entries.

**m3. NULL-chain deref path in dsh_tls_server_ctx.** If load_chain
fails (missing/unreadable cert file), sk_X509_value(NULL, 0) happens
to return NULL and X509_get_ext_d2i(NULL, ...) happens to return
NULL, so the function rejects with the misleading "no SAN" message.
Safe by accident; guard explicitly for the right error.

**m4. Single-threaded assumptions are implicit.** g_err is a global
and the accept loop is sequential; fine today, but Phase 6
concurrency (or a concurrent client) would interleave errmsg.
Document or make errmsg thread-local when concurrency lands.

**m5. Nonblocking-fd hazards in read/write.** dsh_tls_read spins
forever on WANT_READ/WANT_WRITE (no backoff) and dsh_tls_write_all
treats WANT_* as fatal. Both are correct for the blocking sockets
used today; note it before anyone sets O_NONBLOCK.

**m6. Unbounded line buffer in tlsTransport.recv.** acc grows until
an LF arrives with no cap - a malicious peer can balloon server
memory. Check the Haskell recv-line cap for parity and add one
(e.g. reject > 1 MiB lines).

**m7. Inconsistent sentinel class.** The load_verify_locations error
path in dsh_tls_client_ctx returns mk_null_ext(ssl_class()) - a CTX
failure tagged with the SSL class. Works only because dsh_tls_is_null
accepts both classes; use ctx_class() there.

**m8. isNull assumes a real external object.** lean_get_external_class
on the TlsCtx/TlsSsl constructor inhabitant (.mk) would misbehave.
Currently only used for Nonempty; worth an assert or a comment.

## Verified sound (no action)

- **TLS 1.3-only:** min = max = TLS1_3_VERSION set on both ctx
  creation paths before anything else; no SECLEVEL or cipher-list
  overrides anywhere (no SSL_CTX_set_cipher_list / set_ciphersuites /
  security_level calls in the shim), so the OpenSSL defaults
  (all-TLS-1.3 AEAD suites) apply. A peer cannot negotiate down;
  the tls1_2-only negative probe confirms.
- **Client certs required on the server:** SSL_VERIFY_PEER |
  SSL_VERIFY_FAIL_IF_NO_PEER_CERT set on the server ctx (NULL verify
  callback = default X509_verify_cert path, no bypass), with the CA
  loaded via SSL_CTX_load_verify_locations before serving. The
  certificate-less client probe confirms rejection.
- **Fingerprint extraction:** SHA-256 over i2d_X509 DER of the peer
  leaf (SSL_get1_peer_certificate), DER freed with OPENSSL_free,
  hex buffer bounds respected (65 bytes, NUL-terminated), empty
  chain / absent peer returns the sentinel; parity with the openssl
  CLI is asserted in the spec.
- **Startup chain validation:** the server cert chain must validate
  against the CA store (leaf in slots, intermediates untrusted,
  X509_verify_cert, error surfaced) before the listener binds.
- **ABI gotchas (both resolved, no remaining instance):** every
  ByteArray out-param uses lean_sarray_cptr (errmsg, read, write,
  both fingerprint fns) with an explicit cap; no C code hand-builds
  Option ctors - failure is the NULL-payload external sentinel
  checked via dsh_tls_is_null (modulo B1).
- **Error propagation:** every failure path calls set_err, which
  peeks the last OpenSSL error, formats it, and ERR_clear_errors -
  no swallowed error queues; tlsRead maps ZERO_RETURN to clean EOF
  and write_all is a full-drain loop.
- **External-object ownership:** SSL_CTX/SSL freed exactly once by
  the registered finalizers (the only finalizer backstop, per 9.7);
  SSL_set_fd does not transfer fd ownership (BIO_NOCLOSE), so
  Lean-side closeFd plus finalizer SSL_free does not double-close.

## Negative-test coverage gaps (tools/TransportSpec.lean)

Present and good: no-SAN server cert, group-readable key (currently
vacuous, see M1), wrong fingerprint pin, untrusted (wrong-CA) client
cert including the TLS 1.3 post-handshake rejection subtlety,
TLS 1.2-only peer, certificate-less client, fingerprint/expiry
parity checks.

Suggested additions:

1. **Expired certificate**: sign a soon-expired/expired cert; assert
   (a) mkServerCtx still succeeds (startup does not hard-fail on
   expiry) and (b) after M2 is fixed the expiry warning fires /
   days < 0 is observable.
2. **SAN mismatch (client side)**: generate a second good server cert
   with SAN DNS:other.example; connectTlsPinned "localhost" against
   it must fail (currently untested - the only hostname-check test
   is the happy path).
3. **Client trusting the wrong CA**: clientFiles with caFile :=
   other.crt against the good server: handshake must fail
   (complement of the rogue-client test).
4. **Self-signed / unchainable server cert at startup**: server cert
   not signed by the CA file: mkServerCtx must error (covers the
   chain_validates path, currently only exercised positively).
5. **Cert/key mismatch**: good cert + wrong key: mkServerCtx must
   error (SSL_CTX_check_private_key path never negatively tested).
6. **Empty/garbage cert file**: zero-length and non-PEM cert files:
   mkServerCtx and certFingerprintSHA256 must fail cleanly (also
   exercises the m3 NULL-chain path once fixed).
7. **IP-literal connect**: connectTlsPinned "127.0.0.1" against a
   cert with SAN IP:127.0.0.1 - documents the M3 behavior; should
   become a positive test once IP pinning lands.
8. **Oversized line (after m6)**: peer sending > cap bytes with no LF
   must be rejected, not ballooned.

## Required follow-ups

- B1, M1, M2, M3 to shell-engineer (fixes in Ffi/tls_shim.c and
  Shell/Transport/Tls.lean); M1 test rewrite + coverage items 1-7
  in tools/TransportSpec.lean.
- This review did not modify any code (review-only task).
