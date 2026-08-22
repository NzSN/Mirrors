# Ffi/ — C shims (TCB)

C shims for capabilities with no Lean ecosystem package (design §5.4):

- TLS 1.3 mutual auth via OpenSSL (or s2n-tls): `serveTlsOn` /
  `connectTlsPinned`-shaped entry points.
- Sockets: `socket`/`bind`/`accept` for the TCP transport.
- POSIX signal handling (SIGINT/SIGTERM deregistration).

Everything under `Ffi/` is trusted, not proved; keep it small, boring,
and line-auditable (§5.4, §9.1).
