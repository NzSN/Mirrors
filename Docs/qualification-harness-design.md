# Qualification harness design

Date: 2026-09-22

Status: source commands and linked evidence verification implemented; installed
command adapters await the final I4 runtime paths and producer wrappers named
below. This document does not claim a qualified candidate.

## Evidence order

Qualification preserves this acyclic order:

```text
catalog C0 -> distribution-binding D -> origin R0 -> bundle/replay R1
           -> linked offline verification Q -> later catalog approval C1
```

Every command runs under E2 and finalizes independently. Q consumes a private
`mirrors.qualification-scope/v1` DAG of already-finalized run references. It
does not copy those commands into its own envelope. E4 credits only selected
successful attempts, while failed retries and supporting diagnostics remain
retained without satisfying a requirement.

## Registered command map

The local candidate and release candidate profiles require these commands.
Paths below are exact for source commands. `ACTIVE_RUNTIME` means the runtime
directory selected by the final I4 installation manifest, never a source
checkout or `PATH` fallback. `PRIVATE_OUTPUT` is a fresh owner-only directory
whose declared files are captured by E2.

| Command ID | Phase and exact invocation | Required retained result | State |
| --- | --- | --- | --- |
| `mirrors.local-no-model` | cwd bound to the declared `mirrors` component root: `bash tools/run-local-no-model-check.sh` | local build, proof, codec, fixture and unit-gate logs; the script explicitly omits TLC and every live Apalache/model-check tier | Registered; deliberately non-model-checking |
| `mirrors.remote-model-check` | Mirrors cwd: `python3 tools/evidence/run_remote_model_check.py`; fixed TLS 1.3 mTLS endpoint `192.168.150.219:8999`, pinned server leaf, fixed `HourClock.tla` `Init`/`Next`/`Inv`, bound 3 | private command context and log containing the declared service/source/binary identities, client and HourClock byte hashes, and terminal `VALID` | Registered; credentials remain operator-supplied private file paths |
| `mirrors.interop` | cwd bound to the declared `mirrors` component root: `bash tools/interop/run.sh`; explicit companion roots/SHAs, `HS_BIN`, and Apalache 0.61.0 are required environment | command logs | Registered; final environment freezes with C0 |
| `mirrorecma.project-check` | cwd bound to the declared `mirrorecma` component root: `pnpm run check` | command logs | Registered |
| `mirrorecma.test` | cwd bound to the declared `mirrorecma` component root: `pnpm run test` | command logs | Registered |
| `mirrorgate.required` | cwd bound to the declared `mirrorgate` component root: `bash scripts/test.sh` | command logs | Registered; unavailable required backend remains incomplete |
| `framework.install-diagnostics` | Mirrors cwd: `python3 tools/distribution/qualification.py --prefix INSTALL_PREFIX --framework-catalog-bin TRUSTED_C3 --framework-catalog-sha256 C3_SHA --bwrap BWRAP --strace STRACE --strace-sha256 STRACE_SHA --audit-out PRIVATE_OUTPUT/install-diagnostics.json --hide-root MIRRORS --hide-root MIRRORECMA --hide-root MIRRORGATE` | installed audit, D manifest and cache index | Producer exists; E2 copy/attachment wrapper still required |
| `framework.replay-correct` | source-hidden installed consumer, `ACTIVE_RUNTIME/runtimes/node/bin/node` plus the installed project replay wrapper in correct mode | typed producer result and local cleanup receipt | Awaiting installed project fixture path |
| `framework.replay-faulty` | same installed wrapper in the deliberate-fault mode | exact normalized mismatch and local cleanup receipt | Awaiting installed project fixture path |
| `framework.reproduction` | installed `mirrorecma reproduce` with explicit project, R0-derived bundle, framework input, C0 combination, finalized R0 envelope/artifact store, server, and installed tool registry | R1 reproduction input and typed replay result | CLI exists; source-hidden fixture/output wrapper pending |
| `framework.reduction` | installed LeaseService reduction materializer with explicit candidate, R0-derived bundle, model, lock, original trace, tool manifest, output and receipt paths | bounded reduction result, oracle receipt, original reproduction input | Producer exists; final installed paths pending |
| `framework.mutation-local` | installed Node runs `run.mjs all --prevalidated-registry INSTALLED_REGISTRY --receipt PRIVATE_OUTPUT/local-application-campaigns.json` using the installed applications, Mirror and package tree | one `mirrorecma.application-campaign-aggregate/v1` result containing all three closed campaigns and confirmed local cleanup | Final installed paths pending |
| `framework.mutation-gate` | installed aggregate wrapper directly runs `application-program-gate.mjs APPLICATION --receipt PRIVATE_OUTPUT/APPLICATION-gate-receipt.json` for all three applications through the installed Gate profile | three `mirrorgate.application-validation/v2` receipts and confirmed physical cleanup | Aggregate wrapper and final installed paths pending; source R0 commands cannot substitute |
| `mirrorgate.recovery` | installed Gate administrative CLI `recovery reclaim` with explicit state root, optional delegated cgroup parent, complete original private run linkage, and `--receipt PRIVATE_OUTPUT/recovery-receipt.json` | private native recovery receipt with `gate-recovery` cleanup | E1 adapter implemented; CLI file output pending |
| `evidence.offline-verify` | installed verifier: `python3 qualification_scope.py --scope PRIVATE_OUTPUT/qualification-scope.json --store EVIDENCE_STORE` with pinned wheels | required private qualification-scope producer result | Implemented |

The three source campaign IDs
`mirrorgate.application-campaign.{work-queue,persistent-transfer,lease-service}`
are R0 origin runs. Each uses pinned Node and
`application-program-gate.mjs APPLICATION --receipt NEW_FILE`. Their receipts
can seed reproduction bundles only after R0 finalization. They do not satisfy
`framework.mutation-gate`, because final qualification must execute the exact
installed D artifacts.

## Remote-only model-check boundary

Qualification on the current coordinator must not start Apalache, TLC, or any
other model checker. `lake test` is unsafe for this host even with
`APALACHE_MC` absent: it runs `tools/check-async-protocol.py --quick` through TLC
and probes a developer-local Apalache fallback. The registered local aggregate
is therefore `tools/run-local-no-model-check.sh`, which runs the build, pure
proof/unit/codec/fixture/evidence gates while explicitly omitting the TLC async
protocol check and all live Apalache tiers. Its local result establishes those
local behaviors only and cannot receive model-check credit.

The required model-check observation is the separate private command
`mirrors.remote-model-check`. Its wrapper fixes the deployed endpoint to
`192.168.150.219:8999`, the Windows service name to `ModelMirrors`, and the
HourClock predicates and bound. It accepts only these private environment
inputs:

- `MIRRORS_REMOTE_CLIENT_CERT`, `MIRRORS_REMOTE_CLIENT_KEY`, and
  `MIRRORS_REMOTE_CA`: paths to operator-controlled files. The wrapper checks
  file type but never reads or prints their bytes.
- `MIRRORS_REMOTE_SERVER_PIN`: the expected SHA-256 fingerprint of the server
  leaf certificate, enforced by the client.
- `MIRRORS_REMOTE_SERVICE_BINARY_SHA256` and
  `MIRRORS_REMOTE_SERVICE_SOURCE_REF`: values copied from the same-time remote
  administrative observation described below.
- The registry fixes Apalache to 0.61.0 plus its selected archive and staged jar
  SHA-256 values, and Java to selected 25.0.4+7 / observed 25.0.4+7-LTS plus
  the staged Windows archive and `java.exe` SHA-256 values. The activated remote
  deployment observation must report those same complete identities.

E2 retains those values only in the private command context. Public projection
contains neither credential paths nor private context. The wrapper also removes
`APALACHE_MC` from the client environment, prints the local client executable
hash and non-secret endpoint identities, then replaces itself with the fixed
client invocation. The prelude hashes the exact local `HourClock.tla` bytes sent
by that invocation. Exit zero plus `VALID` proves that the pinned mTLS endpoint
performed this bounded validation; service-manager status by itself does not.

Q1 must pair that run with a retained, same-time private remote administrative
observation. That observation records UTC capture time, host/IP, service name,
service state and start mode, listener port and owning PID, configured executable
path and SHA-256, deployed source/full revision, service-account Apalache path and
version, Java version, and hashes of the server certificate and non-secret
deployment manifest. It omits environment secrets and all certificate/key bytes.
The model-check command's endpoint, server-leaf pin, service binary hash and
source revision must equal the administrative observation. A `VALID` result with
missing or mismatched service identity remains retained diagnostic evidence but
does not receive Q1 credit.

The 2026-09-22 boot check is supporting smoke evidence only. It observed the
Windows `ModelMirrors` service as `RUNNING` and `AUTO_START`, listener
`0.0.0.0:8999` owned by PID 33532, TLS 1.3 mTLS verification, installed binary
SHA-256 `194fc1ca8b66f8ab559644eff832e722839d6aaabb2d76d1e20d20b7f25a74ed`
reporting Mirrors 0.0.2, server leaf pin
`b2fc7265145cf2b89a1a248b0932885df8d300121b47f7854317ece4bac9ce67`,
server certificate file SHA-256
`03f98bb439fb7f9100cbbaf5fc8562e3629f17e85bc7e807ce26bd239e82c854`
(valid 2026-08-15 through 2026-11-13), and a bound-3 HourClock result of
`VALID`. The pin remains operator-supplied to the private wrapper. That running
service used Apalache 0.58.2 and Java 21.0.11, so it does not satisfy the selected
qualification tool identity. Apalache 0.61.0 (selected archive SHA-256
`68fb56dd9d053cf21d692fd7ec3fbaaeba1395661ec7434fa2b4c47e6fc432b8`,
staged jar SHA-256
`33611081942d392646af60993c599907f1f41752fce4a62304dbf9e2cdad4346`)
and Microsoft OpenJDK 25.0.4+7-LTS (Windows archive SHA-256
`54ba13f3ef80887fa74708b2a32daaae6262517ba68433d850bb4b426343172b`,
`java.exe` SHA-256
`58df5c13e5d6e68f242ad9b724479122828523008ef0907d3f2a02f54afaff23`)
were staged and verified but had not been activated. Q1 requires a new retained
service observation and remote validation after activation.

The existing `mirrors.interop` registry entry still describes a source matrix
that starts local model-check-backed servers. It must not be executed on this
coordinator under the remote-only constraint. Until that matrix has a reviewed
remote-service mode or is run on an authorized sufficiently provisioned host,
its required Q tier is unavailable and Q3 remains incomplete; the standalone
remote validation cannot substitute for transport/client matrix coverage.

## Installed command handoff contract

The final command registry adds the following eight entries only after each
producer supplies the exact installed path and complete output contract.
Symbolic names in this table describe roles; they are not values permitted in
`commands.json`. Every output directory is an owner-only mode-`0700` directory,
and every captured file is a predeclared mode-`0600` attachment. New outputs use
exclusive creation. Existing inputs are captured with a pre-run SHA-256.

| Command ID | Exact argv shape to freeze | Fixed captured files and schemas | Handoff still required |
| --- | --- | --- | --- |
| `framework.install-diagnostics` | Installed Python plus installed `qualification.py --prefix INSTALL_PREFIX --framework-catalog-bin C3_BIN --framework-catalog-sha256 C3_SHA256 --bwrap BWRAP --strace STRACE --strace-sha256 STRACE_SHA256 --audit-out PRIVATE_OUTPUT/install-diagnostics.json`, followed by the three exact `--hide-root` pairs | New `install-diagnostics.json`, producer result `mirrors.installed-consumer-audit/v1`; existing `distribution-manifest.json`, role `distribution-manifest`, schema `mirrors.reference-distribution-manifest/v1`; existing `cache-index.json`, role `cache-index`, schema `mirrors.reference-cache-index/v1` | Distribution owner: installed Python/script paths, install prefix, C3/Bubblewrap/strace paths and hashes, exact hide roots, and the D manifest/cache bytes copied into the attachment root before collection |
| `framework.replay-correct` | Installed replay wrapper with one fixed `correct` mode and one output-root argument | New `replay-correct.json`, producer result `mirrorecma.suite-result/v1`; it must retain passed behavior plus confirmed local cleanup rather than relying on exit zero | Reproduction owner: wrapper path, complete argv, output flag/index, project/registry inputs, and the closed result-file contract |
| `framework.replay-faulty` | The same installed replay wrapper with one fixed deliberate-fault mode and one output-root argument | New `replay-faulty.json`, producer result `mirrorecma.suite-result/v1`; it must retain the exact normalized mismatch coordinate plus confirmed local cleanup | Reproduction owner: wrapper path, complete argv, output flag/index, deliberate-fault identity, and the closed result-file contract |
| `framework.reproduction` | Installed Node and installed MirrorECMA CLI/wrapper, with explicit project, bundle, framework input, combination, finalized R0 envelope, artifact store, server and tool registry, plus one output-root argument | Existing R0-derived bundle, role `reproduction-input`, schema `mirrorecma.reproduction-bundle/v1`; new `reproduction-result.json`, producer result `mirrorecma.reproduction-replay/v1`; any separate cleanup result must also have a fixed filename and schema | Reproduction owner: wrapper path and exact argv order, fixed result writer, optional-versus-required artifact-store decision, and cleanup representation. Current CLI stdout alone is not an attachment contract |
| `framework.reduction` | Installed Node plus installed `materialize-lease-reduction.mjs --candidate CANDIDATE --bundle BUNDLE --model MODEL --lock LOCK --original-trace TRACE --tool-manifest TOOLS --out PRIVATE_OUTPUT/lease-reduction-candidate-trace.json --receipt PRIVATE_OUTPUT/lease-reduction-receipt.json` | Existing `lease-reduction-candidate.json`, `lease-reduction-original-bundle.json` (also role `reproduction-input`), `lease-reduction-model.tla`, `lease-reduction-lock.json`, `lease-reduction-original-trace.json`, and `lease-reduction-tool-manifest.json` (`mirrorecma.lease-reduction-tools/v1`); new candidate trace and producer result `lease-reduction-receipt.json`, schema `mirrorecma.lease-reduction-oracle/v1` | Distribution/reproduction owners: installed Node/script paths and exact installed filenames and hashes for all six inputs |
| `framework.mutation-local` | Installed Node plus installed `run.mjs all --prevalidated-registry INSTALLED_REGISTRY --receipt PRIVATE_OUTPUT/local-application-campaigns.json` | New `local-application-campaigns.json`, producer result `mirrorecma.application-campaign-aggregate/v1`; the evidence adapter fixes applications to WorkQueue, PersistentTransfer and LeaseService, denominator 17, 29 detailed executions, accepted campaigns and confirmed local cleanup | Distribution/reproduction owners: installed Node, runner and registry paths, plus confirmation that no extra argv/environment is needed |
| `framework.mutation-gate` | One installed aggregate wrapper with one output-root argument. It invokes installed `application-program-gate.mjs` exactly once for each of `work-queue`, `persistent-transfer`, and `lease-service` | New `work-queue-gate-receipt.json`, `persistent-transfer-gate-receipt.json`, and `lease-service-gate-receipt.json`, each producer result `mirrorgate.application-validation/v2`; the aggregate evidence adapter requires all three fixed names and validates the frozen 9/4/4 case denominators, campaign acceptance, fidelity controls and physical cleanup | Recovery/reproduction owners: aggregate wrapper path, exact argv/environment, installed Gate profile inputs, and confirmation that the three v2 files are the complete output set |
| `mirrorgate.recovery` | Installed Gate administrative CLI/wrapper `recovery reclaim --state-root STATE_ROOT`, plus the exact cgroup/original-run arguments and one receipt-output argument | New `recovery-receipt.json`, producer result `mirrorgate.recovery-receipt/v1`, bound to the original private R0 run; the evidence adapter validates the native digest, complete resource results, remaining resources and derived `gate-recovery` cleanup | Recovery owner: final CLI executable and argv order, receipt flag/index, exact original-run arguments, and policy for an unavailable delegated cgroup parent. The currently inspected CLI has no receipt-output flag, so it cannot yet be registered |

The installed offline verifier is a ninth, Q-owned command rather than one of the
eight producer wrappers. Its registration freezes the installed Python,
`qualification_scope.py`, scope path and evidence-store arguments after the
distribution manifest names those installed bytes. It captures the required
`mirrors.qualification-scope/v1` producer result and receives no producer credit
for any command in the linked graph.

## Seven demonstrations

1. Installation uses the final I3 cache and transaction installer; D retains the
   typed manifest/cache pair and the install audit.
2. Read-only diagnostics consume D and C0 before any application factory or Gate
   acquisition. Diagnostic-only runs receive no qualification command credit.
3. Separate installed correct and faulty commands retain a pass and the intended
   application mismatch with local cleanup.
4. R0 finalizes first. The bundle builder embeds R0's private run reference;
   installed R1 reproduction and supported LeaseService reduction retain their
   own results.
5. Local and Gate aggregate wrappers each execute the fixed three-application
   denominator and retain every native receipt. A single LeaseService run cannot
   satisfy the command.
6. Recovery links the interrupted original run, reclaims only owned resources,
   and derives cleanup from the native receipt. Missing delegated cgroup support
   remains an unavailable required tier when aggregate enforcement is required.
7. Q verifies every finalized bundle from the installed verifier after producer
   scratch removal. E4 then binds C1 to Q's public run reference and D's canonical
   manifest/raw cache identities.

## Remaining adapter scope

The final snapshot must freeze these seams before command registration:

- the installed correct/faulty project and tool-registry paths;
- the installed local and Gate aggregate wrappers and their fixed output names;
- the R0-to-bundle materializer and installed reproduction result writer;
- installed LeaseService reduction inputs/tool manifest;
- Gate recovery `--receipt` output; and
- final active runtime, trusted C3 executable/hash, Bubblewrap, companion SHA,
  Haskell binary, and Apalache paths.

No final run may use a placeholder path or reinterpret an earlier `/tmp` result.
