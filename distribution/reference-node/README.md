# Reference Node distribution

Status: I2 locked-input contract. I3 build/install implementation is pending
review of these manifests. Nothing here publishes a package or installs into a
real user prefix.

The distribution targets Ubuntu 24.04 x86_64 and has three deliberately
separate profiles:

| Profile | Purpose | State |
| --- | --- | --- |
| `checked-replay-local` | Offline local replay of a prepared checked corpus | Build required |
| `checked-replay-gate` | The same replay through the optional Gate provider | Build required; extends the entire local artifact closure |
| `fresh-trace` | Explicit trace generation with Java and Apalache | Build required; exact Java 25.0.4+7 and Apalache 0.61.0 archives are prepared and locked |

`profiles.json` is the selection and inheritance contract. `component-lock.json`
binds build recipes to full C4 component identities. `dependency-lock.json`
records only external artifacts whose bytes are known, plus explicit missing
dependencies. The two schemas define I3's finalized distribution manifest and
cache index. All JSON identity uses `mirrors-framework-canonical-json/v1` and a
terminal newline is excluded from its semantic digest.

The checked profiles do not contain Java or Apalache. Ordinary replay never
executes `model_interface_gen`; the compiler is included for separately invoked
preparation and freshness checks. No command resolves a sibling checkout or an
implicit executable from `PATH` after the cache is built.

## Prepared cache and layout

A finalized cache has this relocatable layout:

```text
cache/
  cache-index.json
  distribution-manifest.json
  artifacts/
    bin/
    examples/
    gate/
    packages/
    runtimes/
```

Every manifest path is normalized, relative to the cache root, unique and
case-sensitive. Files have mode `0644` or `0755`. Runtime trees use
`mirrors-runtime-tree-v1`, hashing each sorted UTF-8 relative path, entry type,
normalized executable bit, byte length and content digest. Symlinks, hardlink
aliases, special files, traversal, mutation during hashing, more than 100,000
entries or more than 2 GiB per tree are rejected.

The cache may contain public application examples and checked corpora selected
by the manifest. It must not contain credentials, private keys, private models,
private traces, operator policy, trust stores or host-specific secret paths.
Operator policy and credentials are resolved separately after installation.

The pinned Batteries Git bundle is an exact prepared, content-addressed input.
Its recipe records the source revision, Git identity, `pack.threads=1`, and
compression level 9, and a clean clone must resolve the locked revision. Repeated
bundle creation has not produced byte-identical archives, so the build makes no
reproducibility claim for regenerating that carrier. It verifies and consumes the
one locked bundle byte sequence; changing those bytes requires a new dependency
lock even when the contained revision is unchanged.

Distribution artifacts use the distribution's own bounded cache contract: up to
512 MiB per file and 2 GiB per admitted runtime tree. Current native executables
are larger than E1's 64 MiB retained-evidence artifact limit. E1 therefore
retains the small finalized distribution manifest/cache index (or an immutable
external reference to them) and their hashes; it does not copy, truncate or
reclassify the executable bytes as evidence artifacts. The distribution cache
retains each raw executable and its uncompressed SHA-256 plus dynamic-library
audit. Verification checks those bytes directly before activation.

## Offline resolution

`tools/distribution/manifest-check` validates the three lock files and a selected
profile without network access. Profile closure is explicit through `extends`:
Gate inherits every local artifact and adds Gate artifacts; fresh trace inherits
local and adds only Java/Apalache. Missing required dependencies make a profile
unresolvable rather than selecting a host tool. Compatible overrides require a
new locked artifact identity and catalog/profile validation; product-version
equality alone is insufficient.

`extends` inherits the parent's complete required-artifact closure and all
operator prerequisites. Conflicting prerequisite records are rejected. The
selected profile's `forbiddenArtifacts` is its final exclusion policy; parent
forbidden lists are not unioned into the child. This permits `fresh-trace` to add
Java/Apalache while both checked profiles continue to forbid them.

Installed verification invokes `manifest-check` with the distributed
`framework_catalog` payload only after activation for independent Q2 use.
Pre-activation `manifest-check` instead requires an operator-supplied trusted C3
verifier through `--framework-catalog-bin` and its independently obtained digest
through `--framework-catalog-sha256`. The verifier is copied to an owner-only
snapshot before bounded execution. It is never selected from the cache under
review and never falls back to a source-tree `.lake` path in an installed flow.
Repository validation may use the explicit local build only for development.

I3 will build only into disposable output roots, produce the final manifest and
cache index, then exercise verification and activation under temporary prefixes.
The [transaction contract](activation-transaction.md) governs that work.
The builder takes the dynamic-linker inspector as an explicit `--ldd-bin`
input. Its manifest records exact Python, Git, `ldd`, Lake and bootstrap catalog
verifier bytes and version output; Node and TypeScript remain separately bound
by the locked Node artifact and the complete TypeScript dependency-tree digest.

Installation pins the untrusted cache root, copies it with descriptor-relative
no-follow operations and enforces the cache count/size/case-collision bounds
during that copy. The staged copy is then independently verified and required
to have the admitted manifest identity before any archive is materialized.

Installation materializes each verified cache exactly once beneath
`versions/MANIFEST_DIGEST/`: `cache/` retains immutable archives and manifests,
while `runtime/` contains runnable `bin/`, selected regular-file Node runtime,
compiled MirrorECMA package, generated Counter suite, verifier files, and optional
Gate operator root. The Gate root preserves a `mirrorgate-runtime/` package root
with `runtimes/node/` and `sdk/node/`, a `mirrorgate-supervisor/` Python package
root, and `protocol/` as one admitted tree. The public Node package is copied
from that admitted root into `node_modules/mirrorgate`, so package exports and
source-relative worker imports remain valid after relocation.
`materialization.json` binds the complete runtime-tree digest. Replay
uses only this relocated runtime and performs no per-run extraction, package
installation, source lookup, compiler invocation, or global Node/npm discovery.

## Acyclic identity graph

Dirty component identity excludes the derived central/component catalogs,
generated framework-map bytes, and the three distribution lock files with E1
reason `evidence-output`. Those bytes are not discarded: the finalized
distribution manifest carries required `buildInputs` entries for the complete raw
`profiles.json`, `component-lock.json`, and `dependency-lock.json` bytes, including
all structured recipes. The identity order is therefore:

The two valid manifest/cache fixtures are also derived identity carriers and are
excluded for the same reason; their bytes are test vectors rather than build
source. Production final-manifest/cache bytes are outputs downstream of locks.

```text
component source -> private catalog -> distribution locks
                 -> built artifacts/runtime trees -> final manifest/cache index
```

`tools/distribution/refresh_identity.py` refreshes this graph in that order. A
second run with unchanged component sources is byte-stable. Concurrent companion
edits legitimately change their dirty-content digest and therefore the downstream
catalog selection; this is recorded as a new provisional snapshot, not mistaken
for a self-hash cycle.
