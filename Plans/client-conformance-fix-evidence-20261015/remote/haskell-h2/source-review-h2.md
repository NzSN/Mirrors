# Independent H2 source review — 2026-10-15

Status: **no remaining confirmed findings in the reviewed H2 scope**. The reviewer implemented none of the five production/test/document changes and performed no source edits.

## Frozen scope

| File | SHA256 |
| --- | --- |
| `src-tls/Protocol/Transport/Tls.hs` | `afc5618b129a0cebc6ee4d5237f40f6fb55e6b79e8832d788fdeeb3ff3ecaba0` |
| `ModelMirrors.cabal` | `e142d77c74aef4aa82298f1320c4d6b6768765d78fd79a83b22c20f250500b49` |
| `test/TlsPolicySpec.hs` | `311c6d171ca50eee9aee8fe0192a91432427c2883fe6ec5c90403cc69e96f85a` |
| `test/TransportTestSupport.hs` | `52acf084ba033f25bf6476e7dc2b748f19c8a5ddb0c0be2b4af83b0a25b85dd8` |
| `docs/transport-framing.md` | `4a86e4da9f7a31d4f003fcca81896ae073225bcbd50fca0203a16a3f2ae0e318` |

## Review evidence

The review read all five files and checked the exact installed TLS 2.4.3, crypton-x509-validation 1.9.1 and iproute 1.7.15 public APIs retained in the sibling `haskell-h2-design` directory.

- DNS requires an actual DNS SAN before calling the unchanged dependency name matcher on the original certificate; an absent, email-only or IP-only SAN cannot trigger CN fallback.
- Numeric identities use the same dependency IPv4/IPv6 Read instances. Raw SAN lengths are checked before conversion: exactly four bytes or sixteen bytes. IPv6 pairs produce exactly eight 16-bit words. Wrong-type SANs and malformed IP lengths cannot match.
- The SAN check runs before cache lookup. The unknown-cache path calls `validate HashSHA256` with unchanged `defaultChecks`, original trust store/cache/service ID and original signed chain, overriding only the name hook. Empty chains remain failures. No certificate view or signed object is mutated.
- Normal TLS parameters, TLS 1.3 selection, client credential callback and case-sensitive fingerprint comparison remain intact. Pins run after TLS identity validation and cannot authorize a CN-only certificate.
- The negative fixture catches outside System.Timeout. A returned timeout, PeerTimeout or missing worker completion fails the test. The send counter increments only after a usable transport returns; the peer counts decrypted application bytes. A returned transport or subsequent send error cannot be credited as identity refusal because the counter would be nonzero.
- Listener/socket/context ownership is bracketed; worker termination is followed by a bounded join via readMVar. Peer receive runs concurrently with client sends, so the baseline application write is drained rather than blocked by an idle fixture. Key modes and bytes are not changed by production constructors.

## Executed controls

The actual pre-H2 TLS implementation with only new test/Cabal overlays accepted CN-only identity and produced **one protocol write / 35 decrypted bytes**; its negative test failed explicitly rather than timing out. The same baseline rejected a correct IP-only SAN with a different CN via a real TLS NameMismatch. Both controls isolate the original dependency fallback.

The corrected candidate compiled and passed all **18 NonModel tests twice**. Each run retained **17 rejection receipts**, all zero client protocol writes and zero decrypted application bytes. The correct IP-only SAN/different-CN protocol round trip passed, as did typed DNS/IP SANs, wildcard depth, equivalent IPv6 spellings, mismatched types, cache pass/deny/unknown controls, wrong CA and pin additivity. The no-change build retained the same test-binary hash.

The remote manifest binds the source snapshot, commands, exits and raw logs. No owned Haskell compiler/test process or session temporary directory remained, and H1 source/binaries/evidence identities were reverified unchanged.

This is a scoped source and executed WSL review; it does not qualify native Windows/macOS ACL/TLS behavior, hosted CI or unselected model-backed suites.
