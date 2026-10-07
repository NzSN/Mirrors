# Qualification harness design

Date: 2026-09-22

Status: source commands, installed adapters, linked Q1 and independent offline
Q2 are implemented. The current named profile `m5-wsl-windows-remote/v1`
qualifies at the exact published revisions in
[October 7 readiness](../Plans/q3-published-roadmap-2026-10-07.md): 18 commands/16
tiers, two D bindings, 19 nodes, 20 bundles and six rejected controls. This design
describes mechanisms; source or documentation changes do not renew that evidence.

## Installed LeaseService qualification branch

The selected Windows profile adds `framework.lease-origin-installed` and
`framework.reproduction-lease`. The distribution materializes a separate
`applications/lease-project` with correct and expired-token adapters, the
compiler-owned LeaseService handle, two protected witness occurrences and exact
server/package/tool locks. WorkQueue's reference project remains the prefix
reduction branch.

The installed origin wrapper runs the correct project before the fault and
retains `lease-baseline.json` and `lease-origin.json`, both
`mirrorecma.suite-result/v1`. Its evidence mode `lease-faulty` requires the passed
baseline and exact trace-0/state-5 `write` mismatch with confirmed cleanup.
The separate R1 command uses the normal public project authority and capture/
reproduction path. Scope v2 declares its origin/reproduction phases and R5
consumes that R1's exact required bundle bytes.

`framework.reduction` invokes an installed wrapper around the remote materializer.
After model validity and oracle cleanup, the wrapper rechecks actual LeaseService
project authority, model/lock/original-corpus bytes and the finalized original
reference, reproduces the original, then runs a correct baseline and the fault
against the reduced two-occurrence corpus. It retains
`lease-reduction-acceptance.json` (`mirrors.lease-reduction-acceptance/v1`),
binding the original bundle, candidate trace and oracle receipt hashes to the
same original/candidate signature and both cleanup results. The selected adapter
requires that acceptance artifact; an oracle-only receipt cannot qualify R5.
This changes qualification orchestration, not the wire or generated interface.

The installed recovery origin `framework.recovery-origin-installed` abruptly
exits a real owned Gate controller after protected snapshot preparation and
before worker launch. It retains the public manifest and a typed
`mirrors.recovery-origin/v1` result with failed behavior/unconfirmed physical
cleanup. Q keeps this origin as a retained attempt, then credits only the native
recovery receipt linked to its finalized private reference. This exercises
filesystem snapshot reclamation. Post-restart process recovery without a
non-PID/delegated-cgroup ownership proof remains ambiguous and unqualified;
its refusal diagnostics are retained and no ownership check is relaxed.

Catalog-link approval retains every verified distribution binding when scope v2
uses separate local and Gate D runs. Singular manifest/cache fields remain only
for one binding; multiple bindings are not flattened into one installation.

## Evidence order

Qualification preserves this acyclic order:

```text
catalog C0 -> distribution-binding D -> origin R0 -> bundle/replay R1
           -> linked offline verification Q -> later catalog approval C1
```

Every command runs under E2 and finalizes independently. Q consumes a private
`mirrors.qualification-scope/v2` DAG of already-finalized run references. It
does not copy those commands into its own envelope. E4 credits only selected
successful attempts, while failed retries and supporting diagnostics remain
retained without satisfying a requirement.

## Registered command map

The local candidate and release candidate profiles require these commands.
Paths below are exact for source commands. `ACTIVE_RUNTIME` means the runtime
directory selected by the final I4 installation manifest, never a source
checkout or `PATH` fallback. `PRIVATE_OUTPUT` is a fresh owner-only directory
whose declared files are captured by E2.

| Command ID | Phase and exact invocation | Required retained result | Current implemented/scoped state |
| --- | --- | --- | --- |
| `mirrors.local-no-model` | cwd bound to the declared `mirrors` component root: `bash tools/run-local-no-model-check.sh` | local build, proof, codec, fixture and unit-gate logs; the script explicitly omits TLC and every live Apalache/model-check tier | Registered; deliberately non-model-checking |
| `mirrors.remote-model-check` | Mirrors cwd: `python3 tools/evidence/run_remote_model_check.py`; fixed TLS 1.3 mTLS endpoint `172.20.208.1:8999`, pinned server leaf, fixed `HourClock.tla` `Init`/`Next`/`Inv`, bound 3 | private command context and log containing the declared service/source/binary identities, client and HourClock byte hashes, and terminal `VALID` | Registered; credentials remain operator-supplied private file paths |
| `mirrors.interop` | cwd bound to the declared `mirrors` component root: `python3 tools/interop/run-remote.py OUTPUT_ROOT`; explicit five-client roots/SHAs, binary hashes, prepared ECMA runtime and Node, and private mTLS paths | required retained runtime pin and v2 receipt with 22 pinned-mTLS rows | Registered Windows profile; legacy all-transport matrix remains separate |
| `mirrorecma.project-check` | cwd bound to the declared `mirrorecma` component root: `pnpm run check` | command logs | Registered |
| `mirrorecma.test` | cwd bound to the declared `mirrorecma` component root: `pnpm run test` | command logs | Registered |
| `mirrorgate.required` | cwd bound to the declared `mirrorgate` component root: `bash scripts/test.sh` | command logs | Registered; unavailable required backend remains incomplete |
| `framework.install-diagnostics` | Mirrors cwd: `python3 tools/distribution/qualification.py --prefix INSTALL_PREFIX --framework-catalog-bin TRUSTED_C3 --framework-catalog-sha256 C3_SHA --bwrap BWRAP --strace STRACE --strace-sha256 STRACE_SHA --audit-out PRIVATE_OUTPUT/install-diagnostics.json --hide-root MIRRORS --hide-root MIRRORECMA --hide-root MIRRORGATE` | installed audit, D manifest and cache index | Implemented E2 wrapper; exact installed local D qualified |
| `framework.replay-correct` | source-hidden installed consumer, `ACTIVE_RUNTIME/runtimes/node/bin/node` plus the installed project replay wrapper in correct mode | typed producer result and local cleanup receipt | Implemented installed wrapper; scoped replay qualified |
| `framework.replay-faulty` | same installed wrapper in the deliberate-fault mode | exact normalized mismatch and local cleanup receipt | Awaiting installed project fixture path |
| `framework.reproduction` | installed `mirrorecma reproduce` with explicit project, R0-derived bundle, framework input, C0 combination, finalized R0 envelope/artifact store, server, and installed tool registry | R1 reproduction input and typed replay result | Implemented source-hidden installed R1 wrapper; qualified |
| `framework.reduction` | installed LeaseService reduction materializer in remote oracle mode with explicit candidate, R0-derived bundle, model, lock, original trace, tools/v2 manifest, service identity record, three TLS PEM files, output and receipt paths | bounded reduction result, `mirrorecma.lease-reduction-oracle/v2` receipt, original reproduction input | Registered and installed (driver ships in the `mirrorecma` package); current Windows console ownership/identity observation required |
| `framework.reduction-prefix` | installed prefix-reduction driver with explicit project, R0-derived bundle, stability record, original trace, framework input, combination, finalized R0 envelope, output root and policy bounds | `mirrorecma.reproduction-prefix-reduction/v1` bounded result plus the original reproduction bundle as `reproduction-input` | Registered and installed; qualified 2026-09-30 (`run-dcc51362…`, `shortest_reproducing_prefix`) |
| `framework.mutation-local` | installed Node runs `run.mjs all --prevalidated-registry INSTALLED_REGISTRY --receipt PRIVATE_OUTPUT/local-application-campaigns.json` using the installed applications, Mirror and package tree | one `mirrorecma.application-campaign-aggregate/v1` result containing all three closed campaigns and confirmed local cleanup | Implemented installed aggregate; qualified for the declared campaigns |
| `framework.mutation-gate` | installed aggregate wrapper directly runs `application-program-gate.mjs APPLICATION --receipt PRIVATE_OUTPUT/APPLICATION-gate-receipt.json` for all three applications through the installed Gate profile | three `mirrorgate.application-validation/v2` receipts and confirmed physical cleanup | Implemented installed aggregate; qualified; source R0 cannot substitute |
| `mirrorgate.recovery` | installed Gate administrative CLI `recovery reclaim` with explicit state root, optional delegated cgroup parent, complete original private run linkage, and `--receipt PRIVATE_OUTPUT/recovery-receipt.json` | private native recovery receipt with `gate-recovery` cleanup | Native receipt-output CLI implemented; prepared-filesystem recovery qualified |
| `evidence.offline-verify` | installed verifier: `python3 qualification_scope.py --scope PRIVATE_OUTPUT/qualification-scope.json --store EVIDENCE_STORE` with pinned wheels | required private qualification-scope producer result | Implemented |

The selected full profile also registers these installed/supporting branches:

| Command ID | Invocation/role | State |
| --- | --- | --- |
| `framework.install-diagnostics-gate` | Same D tool against exact registered Gate prefix; separate component-set binding | Implemented and qualified; runs before dependent installed producers |
| `framework.lease-origin-installed` | Installed Node plus `verification/bundle/tools/evidence/installed-lease-origin.mjs PRIVATE_OUTPUT` | Fresh correct/fault LeaseService origin qualified |
| `framework.reproduction-lease` | Installed public project reproduction path for the LeaseService origin | Fresh R0→R1 linkage qualified |
| `framework.recovery-origin-installed` | Installed Python plus `verification/bundle/tools/evidence/installed-recovery-origin.py PRIVATE_OUTPUT` | Supporting abrupt-interruption origin retained without qualification credit |

Exact argv, runtime paths and artifact attachments are owned by
`tools/evidence/commands.json` and each admitted installed manifest. The summary
rows do not authorize substitution of source checkouts or historical run refs.
Broader M4 process recovery/aggregate enforcement stays on its separate track.

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
`172.20.208.1:8999`, the deployment to `workspace-native-console`, and the
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
- `MIRRORS_REMOTE_ADMIN_OBSERVATION`: the bounded native Windows console
  observation JSON, captured within one hour and matched to the selected
  process lifetime, binary/source, certificate and complete runtime hashes.
- The registry fixes Apalache to 0.62.2 plus its selected archive and staged jar
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

Q1 pairs the run with a same-time `mirrors.windows-deployment-observation/v1`
record from the owned native console deployment under Windows Workspace. The
record binds UTC observation/process-creation time, host/IP, owning process and
listener, executable/source/manifest hashes, mTLS leaf and complete Apalache/Java
archive and executable hashes. It contains no credential bytes. A missing,
stale or mismatched observation fails admission before remote contact. Console
ownership establishes this profile only; it does not establish AUTO_START or
service-manager acceptance. The current M5 scope excludes separate native
Ubuntu and aggregate-cgroup requirements while retaining WSL-supported installed,
isolation/recovery and evidence checks.

Historical service-manager profile (2026-09-22; superseded for current execution):

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

Pin reconciliation: the Windows `54ba13f3…`/`58df5c13…` pins name that staged
host toolchain and remain **pending-operator-observation** (verified by the
same-time identity observation at activation, which is out of scope here).
Local tiers pin the locally verified Linux carrier instead — archive
`75894d107e474ffb6c947ab050e3893e0a1d3d40d36f107d42936ac6088769c1`, `bin/java`
`e7bc0bc01b516a2ade3d9fceabc12d16c3a3b737adbf186a353602872ba31aad`. The two
pin sets name different carriers and are not interchangeable.

The selected remote interop command exercises five real clients' valid/invalid
bounded verdicts and wrong-pin rejection, plus ECMA register/replay, deliberate
mismatch, supplied Windows trace, inline trace generation, exploration/session
cleanup and inline multi-module sources. Its receipt declares exactly 22 mTLS
rows. The legacy `tools/interop/run.sh` all-transport/local-backend matrix remains
a separate profile and must not be started on this WSL coordinator. The bounded
Windows result is not an assertion that every legacy transport/client row ran.

The interop runner matches each client's declared terminal verdict and exit code.
Argument errors, conflicting verdicts, transport errors, and timeouts do not
count as counterexamples. Its ECMA adapters load only `ECMA_RUNTIME_ROOT` and
execute the absolute `ECMA_NODE_BIN`; ambient `NODE_OPTIONS` and `NODE_PATH` are
removed. The reviewed `tools/interop/ecma-runtime-pin.json` binds a clean build
of the registered ECMA revision, the complete SDK runtime tree, and Node bytes.
Admission precedes client execution; SDK, Node, and both adapter identities are
checked again before writing the v2 receipt. E2 retains the receipt and pin as
required artifacts; Q2 verifies those retained bytes with the rest of the bundle.

The remote `mirrorecma.lease-reduction-tools/v2` contract has exactly schema,
mode, totalBudgetMs, cleanupBudgetMs and validator. Only the separately supplied,
hash-pinned candidate validator runs locally; the remote SDK transport requires
no local mirror, Apalache or Java entry. The installed materializer and evidence
adapter validate the same closed contract. Model validity, candidate replay with
the original mismatch signature, cleanup and linked-scope credit are distinct
observations.

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
| `framework.reduction` | Installed Node plus installed `materialize-lease-reduction.mjs --candidate CANDIDATE --bundle BUNDLE --model MODEL --lock LOCK --original-trace TRACE --tool-manifest TOOLS --out PRIVATE_OUTPUT/lease-reduction-candidate-trace.json --receipt PRIVATE_OUTPUT/lease-reduction-receipt.json --oracle-mode remote --service-identity PRIVATE_INPUT/lease-reduction-service-identity.json --tls-ca CA --tls-cert CERT --tls-key KEY` | Existing `lease-reduction-candidate.json`, `lease-reduction-original-bundle.json` (also role `reproduction-input`), `lease-reduction-model.tla`, `lease-reduction-lock.json`, `lease-reduction-original-trace.json`, `lease-reduction-tool-manifest.json` (`mirrorecma.lease-reduction-tools/v2`, mode `remote`), and `lease-reduction-service-identity.json`; new candidate trace and producer result `lease-reduction-receipt.json`, schema `mirrorecma.lease-reduction-oracle/v2` carrying `oracleMode: remote` and the observed service identity record | Operator: owned native Windows console at 172.20.208.1:8999, Apalache 0.62.2, same-time identity observation and client TLS material; distribution/reproduction owners: installed Node/script paths and exact installed filenames and hashes for all seven inputs (satisfied, confirmed in `commands.json`) |
| `framework.reduction-prefix` | Installed Node plus installed `reduce-reproduction-prefix.mjs --project PROJECT --bundle BUNDLE --stability STABILITY --original-trace TRACE --framework-input FRAMEWORK_INPUT --combination ID --evidence-envelope R0_ENVELOPE --output-root PRIVATE_OUTPUT --candidate-limit N --total-budget-ms N --per-candidate-budget-ms N --cleanup-budget-ms N` | Existing `prefix-reduction-original-bundle.json` (role `reproduction-input`), `prefix-reduction-stability.json`, `prefix-reduction-original-trace.json`, `prefix-reduction-framework-input.json`, and `prefix-reduction-r0-envelope.json`; new `prefix-reduction-result.json`, producer result `mirrorecma.reproduction-prefix-reduction/v1` | Satisfied 2026-09-30: installed driver ships in the `mirrorecma` package; paths, filenames, and policy-bound argv values confirmed against `commands.json` |
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
