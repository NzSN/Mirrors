# Runtime Model-Interface Distribution — Design

> Status: **Mirrors compiler/distribution and MirrorECMA compiled verification
> implemented; dynamic descriptor mode and static-client registries planned**
> Compiler contract:
> [`model-interface-compiler-design.md`](model-interface-compiler-design.md)
> Cross-language generated interface:
> [`generated-model-interface-spec.md`](generated-model-interface-spec.md)
> Parent architecture:
> [`model-interface-generation-design.md`](model-interface-generation-design.md)
> Current protocol reference: [`interface-reference.md`](interface-reference.md)

## 0. Implementation status

The Mirrors-side version-1 path is implemented:

- strict duplicate-aware request/reply/failure codecs and a uniform 65,535-byte
  UTF-8 JSONL bound;
- canonical descriptor resolution from the replay trace bundle, exact digest
  verification, descriptor delivery, `ifNoneMatch`, and final-envelope checks;
- fail-closed protocol admission through `Core.step`, including the
  `register_traces -> register_error` refinement branch;
- negotiated-only trace preflight before replay;
- a bounded, content-verified, realm/principal/tenant-scoped process cache with
  key-level single-flight, bounded negative results, per-scope queue admission,
  and a separate resolution semaphore;
- explicit local/TCP/mTLS authorization contexts, with verified TLS peer
  fingerprints retained for principal and cache scoping;
- always-on pure and mock-session gates in `model_interface_spec` and
  `model_interface_distribution_spec`.

MirrorECMA's D3 compiled-verification path is implemented in its sibling repo:

- strict verification request/reply codecs leave the frozen legacy protocol
  module unchanged;
- `runClientNegotiated` and `runClientWithTracesNegotiated` select an exact
  immutable local adapter registration only after a validated `matched` reply;
- legacy and negotiated entry points share one replay implementation, while
  fresh bindings and explicit legacy fallbacks are disposed exactly once;
- inbound stdio/TCP/TLS framing is raw-byte bounded with fatal UTF-8 decoding;
- the generated Counter binding completes real replay over stdio and
  allowlisted mTLS, with wrong-digest and unauthorized paths making zero SUT
  calls and an incorrect observer reaching ordinary `step_mismatch`.

The remaining external-client work is D4's optional MirrorECMA dynamic handler
registry plus D5's exact-digest registries for MirrorCPP, MirrorRust, and
MirrorLean. Existing handwritten `StateComputer` entry points remain unchanged.

The development-time TypeScript emitter now exports
`<Model>ModelInterface = { semanticDigest, contract } as const`. The contract
comes from the authenticated local compiler lock: lock verification recomputes
`provenance.contractSha256` before emission. This closes the metadata handoff
needed by a client runner without placing the contract in the runtime semantic
descriptor or changing its digest.

## 1. Purpose

The Model Interface Compiler lives in Mirrors and resolves a model, companion
contract, run profile, and structural evidence into a canonical
language-neutral descriptor. Clients need a safe way to receive or verify that
descriptor before replaying a trace against a real implementation.

This design adds that distribution layer without sending executable code,
changing `StateComputer`, or inserting an unsolicited message into the frozen
JSONL replay sequence.

The central distinction is:

```text
ModelInterfaceDescriptor
  language-neutral actions, inputs, observations, types, and digest
  produced and transmitted by Mirrors

GeneratedBinding
  target-language code that interprets the descriptor through StateComputer
  generated at development time and compiled into the client

ImplementationAdapter
  concrete mapping from the generated port to the client-local SUT
  written by a human or LLM and never transmitted by Mirrors
```

The client retrieves a descriptor or verifies its digest. It does not retrieve
the implementation adapter.

## 2. Why the adapter remains client-local

An implementation adapter contains facts Mirrors cannot own:

- target-language symbols and types;
- constructors, methods, callbacks, and state accessors of the real SUT;
- local process, device, database, or network dependencies;
- credentials and deployment configuration;
- application-specific error handling and lifecycle behavior.

Transmitting executable adapter source or bytecode would also:

- create a remote-code-execution and software-supply-chain surface;
- be unusable for already-compiled C++, Rust, and Lean clients;
- couple the server to exact compiler, runtime, and library versions;
- bypass ordinary code review and package provenance;
- exceed the role of the JSONL conformance protocol.

Mirrors therefore transmits data only. Descriptors contain no executable
expressions, target templates, URLs, includes, plugins, or SUT symbols.

## 3. Goals

1. Keep the compiler and canonical descriptor semantics in Mirrors.
2. Let clients retrieve a descriptor when explicitly requested.
3. Let compiled clients fail closed unless the server descriptor digest equals
   the digest embedded in their generated binding.
4. Preserve the existing `register -> spec_validated -> initial_state` message
   sequence.
5. Preserve byte-identical legacy messages when negotiation is absent.
6. Preserve the existing `StateComputer` seam and all handwritten callers.
7. Support build-time generation and runtime verification as separate flows.
8. Cache immutable descriptors by content and resolution inputs.
9. Bound all remote compiler work and descriptor sizes.
10. Prevent any SUT action before required negotiation succeeds.

## 4. Non-goals

- Sending or evaluating implementation adapter code.
- Compiling TypeScript, C++, Rust, or Lean during a replay connection.
- Making a digest an authorization credential.
- Replacing mTLS identity verification or certificate pinning.
- Inferring a client-local implementation mapping on the server.
- Supporting arbitrary remote includes, package downloads, or URLs in a
  contract.
- Adding descriptor chunks to a replay session.
- Treating runtime descriptor retrieval as a substitute for compiling static
  clients.
- Extending validate-only, trace-generation-only, async-job, or explorer flows
  in version 1.
- Changing the conformance relation used by `Core.Diff`.

## 5. Ownership

| Owner | Responsibility |
| --- | --- |
| Model repository | TLA+ sources and companion model-interface contract |
| Mirrors compiler | Resolution, normalized types/paths, comparison completeness, canonical descriptor, semantic digest |
| Mirrors session shell | Negotiation, descriptor cache, policy enforcement, bounded response delivery |
| Client library | Negotiation codec, digest verification, generated binding runtime, adapter selection |
| Application repository | LLM/human-written implementation adapter and real SUT integration |
| Authenticated transport | Server identity and confidentiality; the descriptor digest alone does not authenticate a server |

The server may also ship development-time target emitters in the Mirrors
repository. It does not run those emitters inside a remote replay request.

## 6. Two distinct flows

### 6.1 Development-time generation

Static clients need the descriptor before compilation:

```text
resolve or retrieve descriptor
        -> generate target port and StateComputer binding
        -> LLM/human writes implementation adapter
        -> compile and review client
        -> embed semantic digest
```

The primary development flow remains the local compiler executable:

```text
model_interface_gen resolve ...
model_interface_gen generate ...
```

Static TypeScript, C++, Rust, and Lean clients use this build-time path
exclusively. Version 1 does not define a standalone remote artifact-retrieval
command. Runtime descriptor delivery is reserved for MirrorECMA's local-handler
interpreter and continues directly into the same replay session.

### 6.2 Runtime verification

A compiled version-1 binding exports both its semantic digest and the canonical
companion contract used to generate it as inert data. Registration sends both
because the server needs the contract to resolve the interface. Among local adapter
selection fields, only the semantic digest crosses the wire: `adapterId`,
target profile, and binding-contract version remain client-local.

```text
compiled client digest
        -> register request
        -> Mirrors resolves or loads descriptor
        -> exact digest match
        -> spec_validated
        -> client selects local adapter
        -> initial_state / next_step replay
```

On a required mismatch, no replay begins. On an old server that does not return
negotiation data, a required client closes the connection before invoking the
SUT.

## 7. Protocol placement

Version 1 extends only the stepping registrations:

- `register`;
- `register_traces`.

It adds:

1. an optional `modelInterface` request field to the registration object;
2. an optional `modelInterface` reply field to the existing
   `spec_validated` object;
3. an optional structured `modelInterface` failure field on
   `register_error`.

It does not add a new `proto_step`, phase, or round trip.

This placement is intentional:

- current server decoders read known registration fields and ignore unrelated
  object fields;
- clients already must tolerate unknown mirror-message fields;
- `spec_validated` is already received before `initial_state`;
- existing abstract protocol tags remain unchanged and the successful ordering
  remains `register -> spec_validated -> initial_state`;
- legacy encoders remain byte-identical when no request is present.

Current clients that want negotiation must update their `spec_validated`
decoder, because some implementations currently discard unknown fields while
constructing the typed message.

## 8. Request schema

Example runtime verification request:

Digest strings in examples are abbreviated for readability; encoded messages
always contain the full canonical 64-hex payload.

```json
{
  "proto_step": "register",
  "apalacheConfig": {
    "specPath": "Counter.tla",
    "invariant": "TraceComplete",
    "lengthBound": 6,
    "paramVars": "parameters"
  },
  "traceConfig": { "numTraces": 10 },
  "spec": { "sources": ["---- MODULE Counter ----\n..."] },
  "modelInterface": {
    "schema": "mirrors.model-interface-negotiation/v1",
    "request": "verify",
    "policy": "require",
    "acceptDescriptorSchemas": [
      "mirrors.model-interface-descriptor/v1"
    ],
    "expectedSemanticDigest": "sha256:0123456789abcdef...",
    "contract": {
      "inline": {
        "schema": "mirrors.model-interface/v1",
        "interfaceVersion": "1.0.0",
        "model": { "module": "Counter", "source": "Counter.tla" },
        "wire": {
          "actionVariable": "action_taken",
          "parameterVariable": "parameters"
        },
        "initializers": [
          {
            "id": "Initialize",
            "wireAction": "init",
            "wireAliases": [],
            "inputs": []
          }
        ],
        "actions": [
          {
            "id": "Tick",
            "wireAction": "tick",
            "wireAliases": [],
            "inputs": [
              {
                "id": "Stride",
                "from": {
                  "root": "stepParameters",
                  "path": [
                    { "field": "parameters" },
                    { "field": "stride" }
                  ]
                }
              }
            ]
          }
        ],
        "observations": [
          {
            "id": "Count",
            "wireName": "count",
            "provenance": "implementation"
          }
        ]
      }
    }
  }
}
```

### 8.1 `ModelInterfaceRequestV1`

| Field | Type | Rule |
| --- | --- | --- |
| `schema` | string | Exactly `mirrors.model-interface-negotiation/v1` |
| `request` | `verify` or `descriptor` | Required |
| `policy` | `require` or `prefer` | Required; negotiated runners default to `require` |
| `acceptDescriptorSchemas` | nonempty string array | Ordered strongest/preferred first; maximum 8 |
| `expectedSemanticDigest` | digest or null | Required for `verify`; optional for `descriptor` |
| `ifNoneMatch` | digest or null | Allowed only for `descriptor` |
| `contract` | contract reference | Exactly one supported reference form |

Version 1 accepts only an inline companion contract:

```json
{ "inline": { "...": "strict ContractV1" } }
```

The envelope reserves a future digest reference:

```json
{ "digest": "sha256:..." }
```

but the server must reject it until an authenticated, authorization-aware
contract registry exists. Mirrors never guesses an adjacent companion file
from `specPath`.

### 8.2 Strictness

The negotiation and companion-contract schemas reject:

- duplicate JSON keys;
- unknown fields for their declared version;
- invalid field combinations;
- malformed or noncanonical digests;
- empty schema lists;
- oversized strings, arrays, paths, or type graphs.

The outer JSONL protocol remains field-additive. Schema-versioned negotiation
objects are strict so a misspelled security policy cannot silently become a
legacy fallback.

### 8.3 Request modes

`verify`:

- requires `expectedSemanticDigest`;
- asks the server to resolve the interface and compare exactly;
- does not return the full descriptor on success;
- is the default runtime mode for compiled clients.

`descriptor`:

- asks for the complete canonical descriptor when it fits the inline bound;
- may include `expectedSemanticDigest` for comparison;
- may include `ifNoneMatch` for content-addressed cache reuse;
- is reserved in version 1 for MirrorECMA's local-handler interpreter during
  the replay registration.

### 8.4 Policies

`require`:

- any missing capability, unsupported schema, invalid contract, resolution
  failure, digest mismatch, or unavailable required descriptor produces
  `register_error` before stepping;
- the client also fails closed if an old server omits the reply field.

`prefer`:

- the server reports the negotiation status and may continue the legacy replay
  flow;
- the client may continue only if the caller supplied an explicit legacy
  `StateComputer` fallback;
- an explicit `expectedSemanticDigest` mismatch is always fatal, regardless of
  policy; `prefer` applies only to missing capability or descriptor delivery;
- no library silently changes `require` to `prefer`.

## 9. Reply schema

Successful verification:

```json
{
  "proto_step": "spec_validated",
  "result": "valid",
  "modelInterface": {
    "schema": "mirrors.model-interface-negotiation/v1",
    "status": "matched",
    "descriptorSchema": "mirrors.model-interface-descriptor/v1",
    "semanticDigest": "sha256:0123456789abcdef..."
  }
}
```

Descriptor delivery:

```json
{
  "proto_step": "spec_validated",
  "result": "valid",
  "modelInterface": {
    "schema": "mirrors.model-interface-negotiation/v1",
    "status": "resolved",
    "descriptorSchema": "mirrors.model-interface-descriptor/v1",
    "semanticDigest": "sha256:0123456789abcdef...",
    "provenanceDigest": "sha256:fedcba9876543210...",
    "descriptorBytes": 12345,
    "descriptor": {
      "schema": "mirrors.model-interface-descriptor/v1",
      "interfaceVersion": "1.0.0",
      "semanticDigest": "...",
      "...": "..."
    }
  }
}
```

### 9.1 Statuses

| Status | Meaning | Descriptor present? |
| --- | --- | --- |
| `matched` | Resolved digest equals `expectedSemanticDigest` | No |
| `resolved` | Descriptor requested and returned | Yes |
| `not_modified` | `ifNoneMatch` equals resolved digest | No |
| `mismatch` | Resolved digest differs from expected | No |
| `unsupported` | No accepted descriptor schema is supported | No |
| `unavailable` | Descriptor cannot be resolved under `prefer` | No |
| `too_large` | Descriptor exceeds the inline response bound | No |

Under `require`, only `matched`, `resolved`, and `not_modified` may accompany
`spec_validated`. Every other outcome becomes `register_error`.

When `expectedSemanticDigest` is present, `mismatch` becomes `register_error`
under both policies. Status selection otherwise uses this precedence:

```text
if no accepted schema:
  unsupported
else if resolution fails:
  unavailable
else if expectedSemanticDigest exists and differs:
  mismatch
else if request = verify:
  matched
else if ifNoneMatch equals the resolved digest:
  not_modified
else if descriptor bytes or the final envelope exceed their limit:
  too_large
else:
  resolved with descriptor
```

Policy conversion to `register_error` happens after status selection. A
version-1 mismatch never carries descriptor bytes.

Encoders omit absent `expectedSemanticDigest`, `ifNoneMatch`, `descriptor`, and
`provenanceDigest`. Decoders accept absent or explicit `null` for these optional
fields. The server never emits `descriptor: null`.

`descriptorBytes` is the exact canonical UTF-8 byte count. It is required for
`resolved` and `too_large`. A descriptor that fits its own bound but causes the
final response envelope to exceed the JSONL limit is still `too_large`. The
server never truncates, compresses, base64-encodes, or partially emits it.

### 9.2 Structured registration failure

```json
{
  "proto_step": "register_error",
  "error": "model interface digest mismatch",
  "modelInterface": {
    "schema": "mirrors.model-interface-negotiation/v1",
    "status": "mismatch",
    "code": "interface_digest_mismatch",
    "expectedSemanticDigest": "sha256:..."
  }
}
```

The existing human-readable `error` field remains. The optional structured
field gives new clients a stable classification without changing the
`register_error` protocol tag.

The actual digest and provenance digest are returned on failure only when the
authenticated caller has descriptor-read scope. Unauthorized and nonexistent
descriptor references produce externally indistinguishable failures.

Remote failures never include absolute paths, source excerpts, command lines,
environment values, or raw internal diagnostics.

## 10. Negotiation state machine

The pure negotiation model is:

```text
request absent
  -> legacy

request present
  -> parse request
  -> select mutually accepted descriptor schema
  -> authorize contract/model access
  -> resolve or load descriptor
  -> verify canonical descriptor digest
  -> apply request mode and policy

legacy
  -> original spec_validated bytes

matched/resolved/not_modified
  -> extended spec_validated
  -> normal replay

required failure
  -> extended register_error
  -> terminal; no initial_state

preferred non-pin failure
  -> extended spec_validated with failure status
  -> legacy replay only if client explicitly permits fallback
```

Server invariants:

1. The server emits negotiation fields only after a request was present.
2. A required failure emits no `initial_state` or `next_step`.
3. The descriptor is resolved against the same spec, trace evidence, and
   `paramVars` used by the replay.
4. The advertised digest is recomputed from canonical descriptor semantics.
5. A `matched` reply never contains descriptor bytes.
6. A `not_modified` reply is valid only when `request = descriptor` and
   `ifNoneMatch` matched.
7. A preferred failure never changes model or trace behavior; it only reports
   negotiation status.
8. Legacy requests do not perform compiler work solely for distribution.

Client invariants:

1. `require` plus a missing reply field is failure, including against an old
   server.
2. In `verify` mode the client parses the returned branded digest and compares
   it exactly with the embedded digest. In `descriptor` mode it validates the
   schema and recomputes the descriptor digest before caching or use, under the
   same byte/depth/node limits used for uncached input.
3. The client invokes no SUT action before required negotiation succeeds.
4. A digest mismatch never selects a “closest” adapter.
5. `prefer` continues only through an explicit caller-provided fallback.
6. The descriptor never enters `eval`, dynamic module loading, a compiler, or
   a shell during the replay session.
7. A `not_modified` reply succeeds only when the local cache entry exists and
   its bytes recompute to the advertised digest. A missing or corrupt entry
   aborts the session; the caller may retry on a new connection without
   `ifNoneMatch`.

## 11. Compatibility matrix

| Client | Server | Request | Result |
| --- | --- | --- | --- |
| Old | New | none | Exact legacy behavior and bytes |
| New | New | `verify/require`, match | Extended `spec_validated`; replay |
| New | New | `verify/require`, mismatch | `register_error`; no replay |
| New | New | `descriptor/require`, fits | Descriptor returned; replay may continue |
| New | New | `descriptor/require`, too large | `register_error`; use build-time CLI |
| New | New | `*/prefer`, unavailable | Status returned; explicit fallback decides |
| New | Old | `*/require` | Old server ignores request; missing reply causes client abort before SUT |
| New | Old | `*/prefer` | Explicit legacy fallback may continue |

Old clients are not sent an unsolicited field because the new server adds it
only when the request field is present.

## 12. Descriptor identity

The compiler's canonical semantic descriptor is content-addressed with domain
separation:

```text
semanticDigest = SHA-256(
  UTF8("mirrors-model-interface-descriptor/v1")
  || 0x00
  || canonicalSemanticDescriptorBytes
)
```

The wire form is:

```text
sha256:<64 lowercase hexadecimal characters>
```

All implementations use one branded internal value:

```text
SemanticDigest = exactly 32 bytes

parseWire("sha256:<64 lowercase hex>") -> SemanticDigest
renderWire(SemanticDigest)              -> canonical string
```

Clients do not compare arbitrary digest strings.

`provenanceDigest` remains separate. It covers source closure, companion
contract, evidence, and compiler provenance, but it does not select an
implementation adapter. A comment-only source change may update provenance
without changing the semantic digest.

The transmitted descriptor is the lock's canonical semantic projection. It
does not contain the lock's source manifest, logical source paths, evidence
locations, compiler diagnostics, or other provenance records. The complete
compiler lock remains a local/build artifact. `provenanceDigest` may be carried
in the envelope as an opaque freshness/audit hint, but clients neither select
adapters nor authorize access with it.

The descriptor includes or commits to:

- lock schema and resolver-semantics version;
- interface version;
- exact run profile, including effective parameter variables;
- action phases, stable IDs, labels, aliases, input paths, and types;
- complete observation names and types;
- comparison-policy version tied to `applyParamVars` and `filterMeta` semantics.

`canonicalSemanticDescriptorBytes` is compact canonical JSON of exactly:

```text
schema
interfaceVersion
model identity
run profile and comparison-policy version
initializers
transition actions
input projections and structural types
observations and structural types
```

The `semanticDigest` field itself, provenance fields, and any final file newline
are excluded from the digest input. Canonicalization version is fixed by the
descriptor schema. Lean and every client repository share fixed descriptor and
digest test vectors.

Target-generated source has its own build/profile provenance. Mirrors verifies
semantic identity, not TypeScript or C++ formatting.

## 13. Server resolution and cache

### 13.1 Resolution key

```text
ResolutionFingerprint = SHA-256(
  UTF8("mirrors-model-interface-resolution/v1")
  || 0x00
  || canonicalJson({
       sourceClosureDigest,
       contractDigest,
       runProfileDigest,
       normalizedEvidenceDigest,
       resolverSemanticsVersion
     })
)

ScopedResolutionKey =
  (securityRealmId, principalId, tenantId, ResolutionFingerprint)
```

The key locates a resolution result. The semantic digest addresses the
immutable descriptor itself. Two resolution keys may legitimately point to
the same semantic descriptor. Realm, principal, and optional tenant scope
lookup and quota accounting; none is part of the descriptor's semantic digest.

### 13.2 Cache shape

```text
resolution index:
  ScopedResolutionKey -> semanticDigest | stable failure summary

descriptor store:
  semanticDigest -> canonical immutable descriptor bytes
```

Cache invariants:

- one semantic digest always maps to identical canonical bytes;
- writes are atomic;
- cache hits revalidate stored length and digest;
- in-flight identical resolutions are deduplicated;
- failures have short bounded lifetimes and never cache sensitive raw
  diagnostics;
- eviction removes index/store reachability but never mutates an entry;
- cache lookup never replaces authorization.

Each cache entry has one lifecycle:

```text
building -> ready | failed | quarantined
```

Only fully verified `ready` entries are visible. Identical in-flight builds are
single-flight. Ready entries are pinned while a reply uses them; eviction never
removes a pinned entry. Failed results have a short bounded negative-cache TTL,
and a digest/bytes inconsistency quarantines the entry.

Version 1 uses a bounded process-local cache. Suggested defaults:

- maximum 128 descriptors;
- maximum 16 MiB of descriptor bytes;
- maximum 4 active resolutions per realm and 16 process-wide;
- maximum 16 queued resolutions per realm and 64 process-wide;
- maximum 64 negative entries per realm with a 30-second TTL;
- bounded resolution-index entries and logical bytes per realm in addition to
  global physical-byte limits;
- LRU eviction among completed entries;
- no persistent disk cache until recovery, permissions, and tenant scoping are
  designed separately.

### 13.3 Authorization scope

Knowing a semantic or contract digest does not authorize descriptor retrieval.
The caller must already be authorized for the model/spec registration. When
the deployment distinguishes tenants, both the resolution index and descriptor
lookup are scoped by the authenticated principal or tenant.

Current deployments without tenant identity keep the cache process-local and
return a descriptor only on the same authorized registration flow. Version 1
does not expose a global “fetch by digest” endpoint.

The logical resolution index is scoped by the security realm, authenticated
principal, and optional tenant derived from the authorized session context.
Physical immutable bytes may be deduplicated, but authorization decisions and
logical quota charging remain scope-specific.

Runtime orchestration receives an explicit context:

```lean
inductive TransportTrust where
  | localStdio
  | authenticatedTls
  | unauthenticatedTcp

structure SessionAuthContext where
  trust          : TransportTrust
  principalId    : Option String
  tenantId       : Option String
  securityRealm  : String
  scopes         : List String
```

The accept/session seam constructs this context; the compiler never derives
authorization from descriptor contents. An mTLS deployment that wants
principal-scoped delivery must expose a stable allowlisted identity from the
verified peer certificate (for example a deployment-selected SAN URI or a
rotation-aware certificate identity). If the current TLS transport cannot
surface such identity, full remote descriptor delivery remains disabled rather
than treating “certificate accepted” as application authorization.

Version-1 scopes are `model-interface.verify` and
`model-interface.read-descriptor`; descriptor read implies verify. Local stdio
uses an explicit local principal/realm. Plain TCP has neither scope unless the
operator enables a named trusted-deployment policy.

The version-1 mTLS CLI application policy is explicit and fail-closed:

- `--model-interface-allow-client FP[,FP...]` accepts exact client certificate
  SHA-256 fingerprints and grants only `model-interface.verify`;
- `--model-interface-descriptor-read` additionally grants
  `model-interface.read-descriptor` to that allowlist and is invalid without it;
- absent the allowlist, a CA-valid client retains legacy registration access but
  receives no model-interface scope;
- the normalized peer fingerprint remains part of cache and quota scope, so
  principals under one CA do not share logical entries or accounting identity.

The distribution layer does not reuse the async job store's cross-connection
job visibility as an authorization mechanism and exposes no guessable artifact
handle.

## 14. Resource and wire limits

All negotiation input is untrusted. Version-1 hard limits are:

| Resource | Limit |
| --- | ---: |
| Negotiation-enabled raw JSONL line | New uniformly enforced 65,535-byte limit |
| On-disk ITF trace artifact | 16 MiB, read with a one-byte overflow probe |
| Canonical descriptor eligible for inline response | 32,768 bytes |
| Accepted descriptor schemas | 8 |
| Initializers | 32 |
| Transition actions | 256 |
| Aliases per action | 16 |
| Inputs per action | 128 |
| Observations | 1,024 |
| Path segments | 32 |
| Structural type depth | 32 |
| Total normalized type nodes | 8,192 |
| Stable ID or wire label | 256 UTF-8 bytes |
| Remote diagnostic arguments | 4,096 UTF-8 bytes total |
| Diagnostics returned per request | 64 |

The final encoded response line is checked independently against the JSONL
limit after envelope overhead. `too_large` never triggers chunking inside a
replay session.

Before enabling negotiation, all participating server and client transports
must enforce the line bound on raw UTF-8 bytes before JSON parsing and after
final response encoding. Invalid UTF-8 is rejected. The implementation must not
rely only on client-side conformance guidance or an unbounded TCP accumulator.
Strict duplicate-key validation also occurs on raw JSON before ordinary
`Lean.Json` object construction.

Resolver CPU, memory, external process, and concurrency work use a separate
negotiation semaphore plus CPU and wall-clock budgets. Existing connection/job
limits are not sufficient by themselves. The integration must not spawn an
unbounded task per negotiation or permit a cache-miss stampede.

Model-interface negotiation is enabled by default only for local stdio and
authenticated mTLS sessions with application authorization. Unauthenticated
plain TCP rejects both `verify` and `descriptor` requests unless an explicit
trusted-deployment opt-in is configured. Full descriptor delivery additionally
requires descriptor-read scope.

## 15. Compiler integration in Mirrors

The session shell compiles against the same trace bundle used for replay:

```text
register
  -> acquire/materialize exact spec
  -> generate raw typed traces
  -> preserve normalized type evidence
  -> apply configured paramVars for replay
  -> resolve descriptor from source + contract + evidence + run profile
  -> negotiate digest/descriptor
  -> spec_validated
  -> replay the same processed traces

register_traces
  -> load raw trace files with strict evidence parser
  -> resolve descriptor
  -> apply configured paramVars
  -> negotiate
  -> spec_validated
  -> replay those traces
```

The current `ItfTrace` parser discards `#meta.varTypes`. Compiler integration
therefore needs a richer trace bundle rather than attempting to recover type
evidence after parsing:

```lean
structure TraceBundle where
  rawEvidence : ModelEvidence
  traces      : List ItfTrace
```

The ordinary replay core continues to consume `List ItfTrace`. Distribution
uses only the additional normalized evidence.

## 16. Client architecture

### 16.1 Existing runner

Existing interfaces remain unchanged:

```text
runClient(..., StateComputer)
```

They send no negotiation request and retain legacy behavior.

### 16.2 Negotiated runner

Clients add two source-compatible stepping interfaces:

```text
runClientNegotiated(
  target,
  config,
  traceConfig,
  verifyOptions,
  adapterSource
)

runClientWithTracesNegotiated(
  target,
  config,
  tracePaths,
  verifyOptions,
  adapterSource
)
```

The adapter source is explicit:

```text
NegotiatedAdapterSource =
  | Compiled {
      adapterId,
      targetProfile,
      bindingContractVersion,
      registry,
      fallbackFactory?
    }
  | DynamicHandlers {
      handlers,
      observations,
      descriptorCache
    }
```

`Compiled` requires `request = verify`. `DynamicHandlers` requires
`request = descriptor`. Invalid combinations fail before registration.

The negotiated runner:

1. sends the registration request;
2. receives and decodes `spec_validated`;
3. validates the negotiation reply and descriptor digest;
4. resolves the exact local adapter factory or validates the dynamic handler
   registry;
5. creates a fresh local binding and obtains its ordinary `StateComputer`;
6. only then receives/processes `initial_state` and `next_step`.

The physical server may already have queued `initial_state` after
`spec_validated`; that does not authorize a client SUT action. A failed client
closes without reporting state.

Legacy and negotiated runners converge on one internal replay loop after the
registration result:

```text
receiveRegistrationResult
  -> negotiate and create local binding when requested
  -> shared replayLoop(StateComputer)
```

Clients must not duplicate the `initial_state`, `next_step`, mismatch,
transport-close, and terminal-message logic for negotiated mode.

### 16.3 Static adapter registry

C++, Rust, Lean, and normal production TypeScript clients use precompiled
bindings:

The semantic digest identifies an interface, not one unique SUT adapter.
Applications therefore use a local key:

```text
CompiledAdapterKey = {
  semanticDigest,
  adapterId,
  targetProfile,
  stateComputerContractVersion
}

CompiledAdapterRegistry
  CompiledAdapterKey -> AdapterFactory
```

Among adapter-selection fields, the wire carries only `semanticDigest`; the
inline companion contract is separate resolver input. `adapterId` is explicit
local configuration, and the client never guesses “latest” or tries multiple
adapters.
Factories create fresh per-session handles rather than returning a mutable
singleton:

```text
LocalBinding = {
  semanticDigest : SemanticDigest,
  computer : StateComputer,
  assertCompatibleConfig(config),
  coverage(),
  dispose  : effectful cleanup
}
```

Registry lookup before connection is pure and invokes no SUT. Factory creation
occurs only after successful required negotiation, performs no remote retrieval,
and produces one fresh binding per session. The runner rechecks binding digest
and effective `paramVars`, then disposes the binding exactly once on success,
`step_mismatch`, decode failure, provider failure, or thrown `StateComputer`.

Generated Counter code embeds:

```text
CounterBinding.semanticDigest
```

The application registers its local implementation adapter under that exact
key. Lookup is exact; there is no version range or structural “best match”.

Failures:

- `negotiation_missing`;
- `descriptor_schema_unsupported`;
- `descriptor_digest_invalid`;
- `negotiation_status_unexpected`;
- `descriptor_missing`;
- `not_modified_without_cache`;
- `adapter_not_registered`;
- `adapter_ambiguous`;
- `target_profile_mismatch`;
- `state_computer_contract_mismatch`;
- `interface_digest_mismatch`;
- `binding_digest_mismatch`;
- `binding_config_mismatch`;
- `adapter_factory_failed`;
- `adapter_dispose_failed`;
- `legacy_fallback_unavailable`;
- `handler_missing` / `handler_extra`;
- `observer_missing` / `observer_extra`;
- `descriptor_type_unsupported`.

All selection/factory/config errors occur before a SUT action. Dispose failure
is reported after cleanup was attempted and never replaces an earlier primary
conformance or transport failure. These client-local errors remain distinct
from server `register_error`, generated binding errors, and Mirrors
`step_mismatch`.

### 16.4 Dynamic MirrorECMA option

MirrorECMA may additionally interpret a descriptor at runtime through a local
handler registry keyed by stable descriptor IDs:

```ts
interface DynamicHandlerRegistry {
  readonly semanticDigest: SemanticDigest;
  readonly actions: Readonly<Record<
    StableActionId,
    (inputs: Readonly<Record<StableInputId, NativeModelValue>>) => void
  >>;
  readonly observations: Readonly<Record<
    StableObservationId,
    () => NativeModelValue
  >>;
}
```

The descriptor interpreter owns raw action dispatch, ITF decoding, lifecycle,
observation assembly, and `StateComputer`. Handler functions remain local.

This dynamic mode provides less compile-time exhaustiveness than generated
TypeScript and is not the default production path. It never evaluates source
or constructs handler bodies from the descriptor.

Before constructing `StateComputer`, the interpreter requires:

- the registry's expected semantic digest equals the verified descriptor;
- every declared initializer/action has exactly one local handler;
- every declared observation has exactly one local observer;
- no extra local IDs are present;
- every descriptor type is supported by the interpreter;
- aliases map only to their primary stable action ID.

There is no process-global lookup by action ID. Descriptor retrieval alone does
not authorize binding creation. During replay, all inputs decode before
mutation, expected state and `prevState` remain hidden, exactly one action is
followed by one observation pass, and an invalid observer value poisons the
binding.

## 17. Security model

### 17.1 Trust

- Model sources, contracts, traces, requests, and descriptors are untrusted
  parser inputs.
- The descriptor digest detects accidental or malicious byte substitution but
  does not authenticate the server.
- mTLS server identity, CA validation, SAN verification, and optional
  fingerprint pinning remain the authentication mechanism.
- Full descriptor delivery is disabled by default on unauthenticated plain
  TCP; a digest-only pin does not make the transport confidential.
- An unpinned descriptor retrieved during development is scaffolding evidence
  that requires review before its digest is committed.

### 17.2 Prohibited descriptor content

Descriptor schemas cannot contain:

- executable expressions or scripts;
- generated target source;
- shell commands;
- file or module includes;
- network URLs;
- plugin/package identifiers to load dynamically;
- credentials, secrets, or implementation endpoints;
- server absolute paths or source excerpts.

### 17.3 Fail-closed execution

When policy is `require`:

- no adapter is selected before exact digest verification;
- no handler, initializer, observer, or other SUT callback runs on failure;
- no received source is compiled or dynamically loaded;
- the connection is closed after the structured failure.

### 17.4 Diagnostics privacy

Remote diagnostics expose stable codes, a bounded safe pointer/segment, and a
correlation ID only. Default server logs record the safe code, digest, and a
pseudonymous principal ID. Verbose compiler diagnostics are opt-in, bounded,
control-character escaped, and redacted. Remote messages and default logs must
not expose:

- server filesystem layout;
- inline model source;
- command lines or environment variables;
- cache paths or cross-tenant cache state;
- whether an unauthorized digest exists.

## 18. Protocol and proof impact

### 18.1 Wire types

`Codec.Json` gains optional payload types:

```text
ModelInterfaceRequestV1
ModelInterfaceReplyV1
ModelInterfaceFailureV1
```

The stepping registration constructors carry an optional request. The
`specValidated` and `registerError` constructors carry an optional reply or
failure.

When those options are absent, encoder output must remain byte-identical to
the current golden corpus.

### 18.2 Abstract protocol

The abstract tag inventory does not change:

```text
register -> specValidated -> initialState -> ...
register -> registerError
```

No new phase is required, and Bridge tag-fidelity remains about the same
constructors. Server-enforced `policy = require` does, however, add a new
registration outcome—especially for `register_traces`, which currently goes
directly to `specValidated`/`initialState`. The implementation must explicitly
extend:

- the registration oracle/input with negotiation success;
- the `registerTraces` transition to permit terminal `registerError`;
- allowed-output and attainability statements;
- the TLA-step extension/refinement witness for the new failure branch.

The abstract input becomes, conceptually:

```lean
structure Oracles where
  validationOk : Bool
  interfaceOk  : Bool
```

No request and every accepted/preferred outcome set `interfaceOk = true`.
Required negotiation failure sets it to `false`:

```text
register succeeds iff validationOk && interfaceOk
register_traces succeeds iff interfaceOk

failure -> phase done + exactly [registerError]
success -> existing stepping outputs
```

The shell must not bypass `Core.step` by sending `register_error` directly:

```text
resolve negotiation
-> derive interfaceOk
-> call Core.step
-> accepted: set stepping, send extended spec_validated, run replay
-> rejected: set done, send extended register_error, never run replay
```

An async server connection must terminate this rejected synchronous flow rather
than return to the session loop.

The TLA relation has an explicit alternative
`MirrorRecvRegisterTracesError` action: it consumes the same registration,
queues `REGISTER_ERROR`, and terminates without adding a wire round trip. The
Lean `extRecvRegisterTracesError` constructor witnesses that checked-in action.
Required proof updates include `step_refines_tla`, `no_unsolicited_output`,
phase/target theorems, the `register_traces` witnesses, and Bridge
constructor-pattern proofs after concrete payload arities change.

Payload and control theorems/tests establish:

- no descriptor reply without a request;
- required negotiation failure cannot reach `initialState`;
- successful reply digest equals the resolved descriptor digest;
- legacy optional fields encode identically when absent.

Request/reply correlation and digest selection belong to
`Core.ModelInterface.Distribution`. Required-failure gating composes that result
with `Core.Protocol.interfaceOk`. Byte identity belongs to codec theorems and
golden fixtures; tag erasure alone cannot prove payload correlation.

The successful TLA+ sequence remains unchanged. The required-failure path is an
explicit protocol extension, not something hidden behind codec payloads. It
adds no send/receive phase, but its alternative terminal output must be covered
by the existing refinement discipline.

### 18.3 Proof claim limit

Lean may prove pure negotiation selection, digest correspondence over supplied
canonical bytes, and required-failure gating. It does not prove:

- server authentication;
- correctness of Apalache evidence;
- correctness of generated foreign code;
- that the local adapter calls the intended SUT;
- behavioral completeness of finite traces.

## 19. Repository implementation map

```text
Core/ModelInterface/Distribution.lean
    Pure request policy/status model and required-failure gating

Codec/ModelInterfaceDistributionJson.lean
    Request/reply/failure codecs and canonical descriptor envelope

Shell/ModelInterface/Cache.lean
    Bounded process-local resolution index and descriptor store

Shell/ModelInterface/Runtime.lean
    Resolve/cache orchestration, authorization context, safe remote diagnostics

Shell/ModelInterface/Auth.lean
    Transport trust, principal/realm mapping, and negotiation scopes

Shell/Mirror/Session.lean
    Optional request dispatch and extended spec_validated/register_error send

Shell/Transport/Tls.lean and TLS shim integration
    Preserve verified peer identity long enough to construct SessionAuthContext

Codec/Json.lean
    Optional fields on stepping registrations and mirror replies

tools/ModelInterfaceDistributionSpec.lean
    Codec, policy, cache, compatibility, limit, and session tests

test/fixtures/model-interface/distribution/
    Legacy and negotiated JSONL transcripts, descriptors, failures, limits
```

External clients add their negotiation types, descriptor validation, and
adapter-provider interfaces in their native repositories.

## 20. Test matrix

### 20.1 Wire compatibility

1. Every legacy registration and reply remains byte-identical without the
   optional field.
2. Old client decoders ignore extended mirror fields.
3. New server decoders accept the new optional request and still ignore other
   additive outer fields.
4. Malformed strict negotiation objects are decode failures and return
   `protocol_error`; semantic resolution/policy failures use `register_error`.
5. Encode/decode round-trips cover every request mode, policy, status, and
   optional descriptor shape.
6. Duplicate `policy`, `contract`, and nested contract keys are rejected before
   conversion to `Lean.Json`.
7. Absent optional fields and explicit `null` decode equivalently; encoders omit
   absent optionals.

### 20.2 Negotiation behavior

| Case | Expected result |
| --- | --- |
| Required digest match | `matched`, then normal replay |
| Required mismatch | `register_error`; no `initial_state` |
| Preferred digest mismatch | `register_error`; a pin never falls back |
| Descriptor fits | `resolved` with verified descriptor |
| `ifNoneMatch` hit | `not_modified` without descriptor |
| Descriptor too large | Required error or preferred `too_large` |
| Unsupported schema | Required error or preferred `unsupported` |
| Old server omits reply | Required new client aborts before adapter |
| Unknown action after match | Existing generated binding failure |

The fixture corpus covers the cross-product of request mode, expected digest,
cache validator, descriptor size, and policy. It includes a descriptor below
the descriptor-byte limit whose final envelope exceeds the line limit.

### 20.3 Client safety

1. A recording SUT adapter observes zero calls before a required match.
2. Mismatch, malformed descriptor, unsupported schema, missing reply, and
   missing local adapter each produce zero calls.
3. A matching digest selects exactly one local adapter.
4. A cached descriptor with modified bytes fails digest verification.
5. `prefer` without an explicit fallback does not run a SUT.
6. Dynamic MirrorECMA mode never evaluates descriptor-provided source.
7. Registry lookup does not instantiate a SUT; exactly one factory runs after
   `matched` and returns a fresh binding.
8. Binding-digest/config/factory failures close without `report_state`.
9. Every terminal path disposes a created binding exactly once.
10. Dynamic missing/extra handlers or observers fail before any SUT callback.
11. `not_modified` without a present digest-valid cache entry fails closed.
12. Negotiated and legacy runners use the same replay-loop fixture corpus.

### 20.4 Cache and limits

1. Identical resolution keys deduplicate concurrent work.
2. Cache hits return identical descriptor bytes and digest.
3. Digest-to-bytes inconsistency is a hard internal failure.
4. LRU and byte quotas evict only completed entries.
5. Oversized action/type/path/descriptor inputs fail deterministically.
6. Remote errors contain no absolute path or source excerpt.
7. Unauthorized callers cannot use digest lookup to learn cache contents.
8. Unique-key miss floods respect active/queued/negative-entry quotas.
9. Pinned entries survive eviction while a response is in flight.
10. Failed builders wake every waiter with one bounded result.
11. Realm/tenant indexes and logical byte charging remain isolated even when
    physical descriptor bytes are deduplicated.
12. Raw request and final response byte limits are enforced uniformly before
    parsing/after encoding.

### 20.5 End-to-end Counter

1. Resolve the Counter descriptor from the same traces used for replay.
2. Generate and compile a local Counter binding/adapter.
3. Embed its semantic digest.
4. Verify over stdio and authorized mTLS; assert negotiation rejection on plain
   TCP by default.
5. Replay the real trace only after `matched`.
6. Change the contract or `paramVars`; required verification fails.
7. A deliberately incorrect Counter observer still reaches ordinary
   `step_mismatch` after successful interface negotiation.
8. `register_traces` with `interfaceOk = false` reaches `done`, emits exactly
   one `register_error`, and has a TLA refinement witness.
9. Legacy `interfaceOk = true` retains the exact previous output.
10. Required failure over stdio and mTLS sends zero `initial_state` bytes and
    closes the flow.

## 21. Implementation sequence

### D0: stabilize compiler descriptor

- Complete the Counter compiler vertical slice.
- Freeze canonical descriptor bytes, semantic digest, and resolver-semantics
  version.
- Preserve raw typed evidence alongside replay traces.

Exit: the same inputs always produce the same Counter descriptor.

### D1: pure negotiation and codecs

- Implement request/reply/failure types.
- Implement strict nested decoding and optional outer fields.
- Prove/test policy selection and absent-field byte compatibility.
- Add the legacy/new compatibility fixtures.

Exit: codec and pure policy tests pass without session integration.

### D2: server runtime and cache

- Resolve against the exact replay trace bundle.
- Implement process-local bounded cache and in-flight deduplication.
- Enforce descriptor/resource limits and safe remote diagnostics.
- Integrate required failure before `runReplayFlow`.

Exit: required mismatch emits no `initial_state`; legacy behavior is unchanged.

### D3: MirrorECMA verification — implemented

- Add negotiation request/reply codecs.
- Add `runClientNegotiated` and exact adapter-provider lookup.
- Embed the generated Counter digest.
- Test old/new server combinations and zero-SUT-call failures.

Exit: Counter verifies and replays over stdio and mTLS; plain TCP fails closed
unless the trusted-deployment opt-in is explicitly exercised.

### D4: descriptor retrieval and dynamic development mode

- Add descriptor caching and `ifNoneMatch` in MirrorECMA.
- Add optional local handler registry interpreter.
- Keep dynamic execution source-free and development-oriented.

Exit: a dynamic client can retrieve a descriptor and bind local handlers
without evaluating remote code.

### D5: static clients

- Add exact digest verification and adapter registries to MirrorCPP,
  MirrorRust, and MirrorLean.
- Reuse the same descriptor fixture and semantic digest.
- Keep runtime descriptor interpretation/retrieval out of these static clients;
  they verify and select only precompiled bindings.
- Add the top-level interop matrix legs.

Exit: all clients select precompiled adapters by one language-neutral digest.

## 22. Rejected alternatives

- **Send generated adapter source:** unsafe, unreviewed, and unusable for static
  clients.
- **Send a new unsolicited `model_interface` message:** old clients treat an
  unexpected protocol tag as failure and the sequence would change.
- **Insert an acknowledgement before `initial_state`:** adds a new phase and
  round trip; required gating can happen before `spec_validated` instead.
- **Always attach descriptors:** breaks byte compatibility and wastes bandwidth
  for clients that do not negotiate.
- **Select adapters by model name/version range:** names do not prove structural
  identity; selection is by exact semantic digest.
- **Treat digest as authorization:** content identity is not access control.
- **Infer a server companion path from `specPath`:** filesystem layout is not a
  protocol contract.
- **Chunk descriptor messages during replay:** complicates framing and phase
  semantics; oversized descriptors use build-time retrieval.
- **A separate streaming artifact endpoint in version 1:** bounded semantic
  descriptors fit the negotiated envelope, and static clients use the local
  compiler. Reconsider this only if authorized remote retrieval of larger
  descriptors becomes a demonstrated requirement.
- **Compile received code in MirrorECMA:** dynamic language capability is not
  permission for remote code execution.
- **Regenerate C++/Rust/Lean in a live process:** static target generation is a
  build-time operation.
- **Store coverage in the descriptor:** sampled traces must not change
  interface identity.
- **Continue required negotiation on old-server silence:** absence is failure
  when the caller requested fail-closed verification.

## 23. Acceptance criteria

The runtime distribution design is implemented when:

1. The artifact transmitted by Mirrors is named and treated as a descriptor,
   never an implementation adapter.
2. Legacy registrations and replies remain byte-identical when negotiation is
   absent.
3. Negotiated replay uses the existing `spec_validated` tag and adds no new
   message phase.
4. Required mismatch, missing capability, invalid contract, unsupported
   schema, or oversized required descriptor emits no `initial_state`.
5. New clients against old servers fail before any SUT action under `require`.
6. `verify` clients parse and compare the returned digest exactly;
   `descriptor` clients canonicalize and recompute descriptor identity before
   cache/use. Both select adapters by exact semantic digest.
7. Static clients use precompiled local adapters; no runtime code generation is
   required.
8. Dynamic MirrorECMA mode accepts local handlers only and evaluates no remote
   code.
9. Server cache entries are immutable, bounded, authorization-scoped, and
   content-verified.
10. Remote diagnostics and descriptors expose no server path, source excerpt,
    credential, command, or implementation symbol.
11. Descriptor and compiler resource limits are enforced before unbounded
    allocation or work.
12. The descriptor is resolved from the exact spec, evidence, traces, and run
    profile used by replay.
13. Required successful negotiation precedes adapter selection and every SUT
    callback.
14. A valid but behaviorally wrong SUT still reaches the normal
    `step_mismatch` conformance result.
15. Existing handwritten `StateComputer` entry points remain source-compatible.
16. C++, Rust, and Lean perform no runtime descriptor interpretation,
    compilation, dynamic loading, or network artifact retrieval.

## 24. Result

The resulting seams are explicit:

```text
Mirrors compiler
  -> canonical ModelInterfaceDescriptor

JSONL negotiation
  -> descriptor delivery or exact digest verification

client adapter provider
  -> local precompiled GeneratedBinding

LLM-written ImplementationAdapter
  -> real SUT

GeneratedBinding
  -> unchanged StateComputer
```

Mirrors owns interface truth and runtime identity. Clients own executable
behavior. The negotiated path checks exact semantic-digest agreement before
replay. Lean proves the pure selection and gating rules; authentication,
evidence correctness, generated foreign code, and the implementation adapter
remain outside that claim.
