# H2: enforce the existing Haskell SAN-only client policy

Status: concrete design for parent review; **no H2 production/test edits made**.
This follows the approved plan's separate-review condition for a newly proven
TLS-policy defect. It preserves guide C25 rather than proposing a policy change.

## Proven mechanism and exact boundary

Remote WSL's actual `tls-2.4.3` / `crypton-x509-validation-1.9.1` handshake probe
accepted a CA-valid CN-only server certificate. The first 16 NonModel cases
passed with the CN-only case deliberately observational; that result cannot
qualify C25's SAN-only requirement.

The checked installed source is retained under:

`Plans/client-conformance-fix-evidence-20261015/remote/haskell-h2-design/dependency-source/`

- `tls-2.4.3/Network/TLS/Parameters.hs:576-581` defines
  `OnServerCertificate = CertificateStore -> ValidationCache -> ServiceID ->
  CertificateChain -> IO [FailedReason]`; its default hook is `validateDefault`
  at line 714.
- `crypton-x509-validation-1.9.1/Data/X509/Validation.hs:109-148` exposes no
  SAN-only check. `checkFQHN=False` would disable identity checks and is not
  the proposed intervention.
- Lines 153-166 expose `hookValidateName :: HostName -> Certificate ->
  [FailedReason]`. `defaultHooks` uses the dependency's hostname matcher.
- Lines 207-217 define `validateDefault = validate HashSHA256 defaultHooks
  defaultChecks`; therefore changing only the name hook preserves the default
  chain/time/CA/leaf checking settings and fingerprint algorithm.
- Lines 242-253 return success immediately on `ValidationCachePass`, before
  invoking hooks. A strict SAN check must run before this cache lookup too.
- Lines 465-473 gather DNS SANs only. Lines 520-534 enter the SAN branch only
  when that DNS list is nonempty, otherwise using the CN. Thus an IP-only SAN
  can be ignored in favor of CN. A mere nonempty-SAN or matching-type-presence
  guard is insufficient: wrong IP SAN plus matching IP CN can still pass, while
  correct IP SAN plus different CN can fail.
- Lines 506-509 classify IPs with `readMaybe :: Maybe IPv4`, then IPv6, from
  `Data.IP`. Those public dependency parsers can be reused without a new IP
  parser. The actual matcher and `parseIPAddress` are private exports.

The implementation seam is `mkClientParams`'s `onServerCertificate` hook in
`src-tls/Protocol/Transport/Tls.hs`. No server policy, wire message, certificate
object, signature verification, TLS version, wildcard policy or pin comparison
changes are proposed.

## Smallest coherent intervention

Add one internal pure `sanOnlyName` helper and a small certificate-validation
hook wrapper in the existing TLS module. Reuse the module's existing
`sanEntries`, which uses the same `extensionGet` API as the dependency.

For a DNS identity, require at least one `AltNameDNS`; then call the **existing
dependency** `hookValidateName defaultHooks host originalCertificate`.
With that DNS SAN present its verified source selects SAN matching, so the
dependency retains its case handling, wildcard rules, malformed-name handling
and DNS matching. No new DNS/wildcard matcher is introduced.

For an IP identity, use the **same** `Data.IP` IPv4/IPv6 `Read` instances as
the installed validator and compare its canonical address bytes against only
`AltNameIP` values. This fixes the dependency's DNS-presence gate for IP-only
SANs. The equality is 4 bytes for IPv4 or 16 for IPv6, so wrong types, wrong
addresses and malformed IP lengths cannot match. Numeric names in DNS SANs
are insufficient for an IP identity. No DNS lookup or custom IP text parser is
added.

Run this helper before any validation-cache lookup. On success call the
library's existing `validate` with SHA256, `defaultChecks`, the original trusted
store/cache/service ID and **original signed chain**, changing only
`hookValidateName` to this same helper. On an unknown cache entry, the normal
validator invokes that hook again along with its existing CA/time/chain checks.
On cache pass, the precheck still forbids cached CN-only/wrong-SAN identities.
Cache deny remains a failure. No `checkFQHN` check is disabled.

Pseudocode (public API names verified except final Data.IP export inspection,
which the remote helper is supplying before implementation):

```haskell
sanOnlyName :: HostName -> Certificate -> [FailedReason]
sanOnlyName host cert =
  case readMaybe host :: Maybe IPv4 of
    Just ip -> matchIP (BS.pack (map fromIntegral (fromIPv4 ip)))
    Nothing -> case readMaybe host :: Maybe IPv6 of
      Just ip -> matchIP (BS.pack (concatMap word16Bytes (fromIPv6 ip)))
      Nothing
        | any isDNS (sanEntries cert) -> hookValidateName defaultHooks host cert
        | otherwise -> mismatch
  where
    mismatch = [NameMismatch host]
    matchIP wanted = if wanted `elem` [raw | AltNameIP raw <- sanEntries cert]
                     then [] else mismatch
    word16Bytes word = [fromIntegral (word `div` 256), fromIntegral word]

sanOnlyServerCertificate store cache ident@(host, _) chain = case chain of
  CertificateChain [] -> pure [EmptyChain]
  CertificateChain (leaf : _) -> case sanOnlyName host (getCertificate leaf) of
    [] -> validate HashSHA256
            (defaultHooks { hookValidateName = sanOnlyName })
            defaultChecks store cache ident chain
    errors -> pure errors

-- mkClientParams retains all other default hooks:
clientHooks = defaultClientHooks
  { onCertificateRequest = existingClientCredentialCallback
  , onServerCertificate = sanOnlyServerCertificate
  }
```

Add `iproute` as a direct library dependency because its public `Data.IP` API
is now imported; it is already a compiled transitive dependency of the installed
validator. Reuse its observed installed version in evidence; do not migrate
versions or copy its parser implementation. If `fromIPv6` differs from the
expected public eight-segment API, adjust only the canonical-byte conversion
using its verified public exports before coding. Test-side cache probes may
need direct Cabal test dependencies on the existing crypton x509/store/validation
packages; these are already library dependencies.

## Test conversion and required controls

Convert CN-only from observation to **mandatory rejection**. Preserve typed
`PeerTimeout` handling: timeouts are inconclusive infrastructure failures and
must never count as TLS-policy rejection. Keep actual TLS peers, fresh CA-valid
fixtures and existing owned-process/socket cleanup.

| Identity and CA-valid leaf | Required result |
| --- | --- |
| DNS SAN matches, CN differs | Accept; normal protocol round trip succeeds. |
| DNS SAN differs, CN matches | Reject. |
| CN-only DNS identity | Reject; no client protocol send is reached. |
| DNS identity with only IP SAN or email SAN, matching CN | Reject. |
| IPv4 SAN matches, CN differs | Accept; proves IP SAN, rather than CN, is used. |
| IPv4 SAN differs, CN matches | Reject. |
| IP identity with only DNS SAN (including numeric DNS spelling) or email SAN, matching CN | Reject. |
| Correct IPv6 SAN `::1`, different CN | Accept via same actual loopback TLS transport; equivalent IPv6 spellings match. |
| Wrong IPv6 SAN or CN-only IPv6 identity | Reject. |
| Mixed DNS/IP SAN with a matching requested type | Accept; wrong-type entries cannot supply identity. |
| Existing valid one-label DNS wildcard / nested or root mismatch | Preserve current pass/fail behavior. |
| Correct SAN but untrusted CA | Reject; default CA validation remains active. |
| CN-only with an exactly matching lowercase fingerprint pin | Reject before pinning can authorize it. |
| Correct SAN + lowercase pin / uppercase or wrong pin | Preserve existing pass/reject and documented case-sensitive-pin exception. |
| Direct hook with `ValidationCachePass`, CN-only or wrong IP SAN | Reject before cache can bypass name policy. |
| Direct hook with unknown cache and correct SAN but wrong CA | Reject; cache wrapper has not bypassed normal validation. |

The actual-peer negative helper should record a client protocol-send counter
and the raw TLS peer's observed application payload bytes. On denied identity
the connection never returns a transport to the client runner, the send counter
stays zero and no protocol payload reaches the peer. Handshake TLS bytes are
expected and do not count as JSONL application payload. A baseline run of these
same negative cases must expose the old CN-only acceptance, and the IP-positive
case with wrong CN must distinguish genuine SAN validation from fallback.

## Files, ownership and validation

Expected edits: `src-tls/Protocol/Transport/Tls.hs`, `ModelMirrors.cabal`,
`test/TlsPolicySpec.hs`, and, only as needed for raw-peer byte receipts,
`test/TransportTestSupport.hs`; update `docs/transport-framing.md` to replace
observation-only CN wording with the now-enforced SAN policy. Retain the separate
case-sensitive pin exception. No corpus, generated binding or original checkout
edits by this owner.

After parent design acceptance, implement staged files only, request targeted
independent review, then let the remote helper build/run the exact NonModel
list and TLS tests with retained package/command/source hashes. Repeat the
incremental build and fixed policy gate. No local compilation/probes and no
model checker are needed. Hosted CI and native Windows/macOS remain separate.

Rollback is the small TLS-hook/Cabal/test/doc unit. This repair may reject
previously accepted CN-only certificates under C25, with the normal TLS identity
failure diagnostic; certificate/key files and modes are never mutated.

## Coordinator design review

Approved 2026-10-15 as the separate follow-up required by the approved plan.
The runtime CN-only acceptance and installed validator source establish the
defect. The design keeps the original signed chain, store, service identity,
cache and default checks, adds a SAN-only precheck before the cache, reuses the
existing DNS matcher, and uses the same public Data.IP parsers for exact IP SAN
bytes. Verify its public byte-conversion exports before coding. The direct
iproute dependency is already in the resolved dependency graph.

Required additions include correct IP SAN with different CN, wrong IP SAN with
matching CN, wrong SAN types/email, IPv6, matching-pin CN-only refusal, cache
pass/deny controls, normal CA validation and zero protocol payload on refusal.
The historical case-sensitive pin exception remains separate. Implementation
and a new runtime identity require review and validation before acceptance.
