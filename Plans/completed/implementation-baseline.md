# Mirror framework implementation baseline

Date: 2026-09-22

This is the B1 implementation baseline for the framework-improvement roadmap. It
records source identities and existing entry points. It does not transfer old
test results to these revisions, accept a release candidate, install anything,
or establish publication. Subsequent evidence must name the exact source and
artifact identities it exercised.

## Repository snapshot

The first read-only capture was taken before this implementation wave started
writing coordination documents.

| Repository | Branch and full HEAD | Porcelain state at capture | Treatment |
| --- | --- | --- | --- |
| Mirrors | `main`, `e7c8681d7db62000555675188d0125931136e002` | Clean | This task adds only its assigned documentation and catalog fixtures. Concurrent coordination edits under `Plans/` are preserved. |
| MirrorECMA | `main`, `87ff8ca1555e2e35dd9a4664fc94aaa46d8f3dc2` | Untracked `.work/` | `.work/` contains pre-existing Rust-evaluator/package-consumer material. It is neither an input to this baseline nor safe to delete or reinterpret as fresh evidence. |
| MirrorGate | `main`, `173075d318e4be926570a1378fc0aa36a1294f89` | Clean | An ignored `.work/` exists with earlier evaluator/toolchain material. Git cleanliness does not make ignored artifacts retained or current evidence. |

The planning snapshot used older Mirrors and MirrorECMA revisions. All consumers
must use the revisions above or take a newer explicit snapshot. A commit identity
alone does not identify dirty or ignored content, built executables, runtime
trees, or installed packages.

## Existing identity and evidence assets

| Asset | Current owner and source | What exists | Boundary for this roadmap |
| --- | --- | --- | --- |
| Product identities | Each component: Mirrors `Shell/Version.lean`; MirrorECMA `package.json`; Gate package manifests and `sdk/compatibility.json` | Mirrors reports `0.0.2`; MirrorECMA declares `2.0.0`; Gate development packages declare `0.1.0` | Product versions do not identify protocols, commits, artifacts, or publication. |
| Compiler target profiles | Mirrors `Shell/ModelInterface/Compiler.lean`, emitters under `Shell/ModelInterface/Emit/`, and `tools/ModelInterfaceGen.lean` | Dispatch and golden gates exist for `mirrorecma-v1`, `mirrorecma-async-v1`, `mirrorcpp-v1`, and `mirrorrust-v1` | Emitter source and source tests do not establish an installed client or Gate path. |
| Model/interface identities | Mirrors compiler and generated `*.mirror-interface.lock.json` files | Versioned schema/profile fields, semantic and provenance digests, source hashes, and interface version are emitted | Digests identify their defined canonical inputs only; they are not package or runtime identities. |
| Tool/client pins | Mirrors `tools/ci/versions.env`; MirrorECMA `scripts/ci/versions.env` | Workflow-specific Node, pnpm, Java, Apalache, Rust and client revision pins | Each pin file owns its workflow selection. Neither silently governs another repository. |
| Gate compatibility record | MirrorGate `sdk/compatibility.json` and `docs/compatibility.md` | Experimental backend, protocols, runtimes, client versions, prerequisites, ledger links, and `productionPublication: false` | It remains a Gate-owned input adapted into the future framework catalog. |
| Package identities | MirrorECMA `package.json` and lockfiles; Gate root/integration package manifests and Rust Cargo manifests/locks | Names, versions, package-manager/compiler requirements and dependency closures | A manifest is a declaration. A packed archive or admitted runtime tree needs its own hash and provenance. |
| Project diagnostics | MirrorECMA `src/project-config.ts`, `src/project.ts`, `src/cli.ts`, `test/project.test.ts`, and `docs/project-tools.md` | Read-only `doctor` checks configured paths, hashes, versions, capabilities, packages and corpus preflight | It intentionally does not import adapters, execute tools, install packages, or claim backend admission. |
| Installed-consumer fixtures | MirrorECMA `scripts/check-installed-suite.mjs`; Gate `integrations/mirrorecma/scripts/installed-suite.mjs` | Pack-once, relocate, offline replay with source checkouts hidden, deliberate faults, and cleanup cases | Preparation still starts from sibling source trees. Temporary consumers are deleted by default and are not a distributable installation. |
| Receipts and acceptance records | MirrorECMA suite result/report modules and dated results; Gate integration receipt modules/schemas; Mirrors `Docs/*evidence.json` | Behavioral, cleanup and selected artifact/source observations exist in several component-specific shapes | E1 owns the common envelope. Old hashes cannot replace absent logs or be rebound to current HEAD. |
| Mutation fixtures | MirrorECMA WorkQueue `acceptance.ts`, persistent-transfer and lease application-validation fixtures/results; Gate installed-suite variants | Known faults, expected first mismatches, correct controls, crashes, hangs and disposal failures | F1 fixes model, corpus, observer and implementation identities before a campaign. |
| Gate lifecycle | MirrorGate `supervisor/mirrorgate/orchestration.py`, `preparation.py`, `artifacts.py`, worker broker and control server | In-memory owner-bound sessions, snapshots, cancellation, ordinary cleanup and receipts | There is no durable crash-recovery journal or ownership-safe restart reclamation yet. |
| Platform/backend record | Gate `docs/sandbox/linux-bubblewrap.md`, compatibility record and required isolation tests | Linux/Bubblewrap is the only current backend; per-process limits and descendant cleanup are documented | Aggregate cgroup quotas, native-host qualification and non-Linux backends remain separate work. |

## Workstream entry points

| Workstream | Concrete source entry points | Implemented starting point | First handoff |
| --- | --- | --- | --- |
| C: compatibility | `Shell/ModelInterface/Compiler.lean`, `tools/ci/versions.env`, MirrorECMA project configuration, Gate `sdk/compatibility.json` | Multiple owner-specific records and handwritten support prose; no central strict catalog | C1 owner map and discrepancies feed C2. |
| I: installation | `Docs/versioning.md`, MirrorECMA installed-suite script, Gate installed-suite script | Component staging and source-prepared consumer tests exist; no locked framework distribution or transactional multi-component activation | I1 profile and dependency boundary feed I2. |
| R: reproduction | MirrorECMA `src/suite-runner.ts`, `src/suite-result.ts`, replay reports and project CLI | Structured failures and exact checked-corpus replay exist; no inert bounded reproduction bundle or reducer | R1 consumes C2/E1 identities. |
| F: fidelity | MirrorECMA application-validation and WorkQueue mutation fixtures; Gate installed-suite driver | Known mutants and correct controls exist in application-specific runners | F1 freezes protected input identities and taxonomy. |
| E: evidence | Mirrors dated evidence JSON; MirrorECMA result ledgers; Gate receipts and receipt writer | Useful records exist, but schemas and persistence are component-specific and some aggregate logs were temporary | E1 owns run/artifact/outcome/completeness semantics. |
| G: recovery | Gate orchestration/backend/artifact cleanup and isolation tests | Normal cancellation and close are implemented; abrupt death can leave snapshots and no aggregate cgroup accounting is promised | G1 supplies the lifecycle design and TLA+ model before runtime changes. |

## Source-versus-documentation discrepancies

1. Mirrors dispatches and source-tests `mirrorrust-v1`, while
   `Docs/framework-map.md` and `Docs/application-integration-guide.md` say there
   is no generated Rust target. Gate accurately describes only its handwritten
   Rust Counter fixture and sets `rustGeneratedApplicationTarget` to false.
   These are different capability scopes; the prose about Mirrors is stale.
2. Existing installed-suite gates demonstrate strong component-local behavior,
   but both assemble their consumers from source checkouts and delete scratch
   consumers by default. They are not a reference distribution, durable release
   evidence, or proof of package publication.
3. `Docs/application-integration-progress.md` records hashes for six aggregate
   logs that were absent during its 2026-09-17 audit. Their historical results
   remain historical; hashes alone do not restore inspectable artifacts.
4. Gate documents Bubblewrap 0.9 or newer, while the executable visible on this
   host prints `bubblewrap built for Codex` rather than a comparable version.
   The full namespace probe failed inside the command sandbox with a denied
   network-namespace socket and succeeded when rerun outside that sandbox. This
   identifies a tool-sandbox restriction, but it is not the full Gate test suite
   or fresh cleanup acceptance for this source combination.
5. The selected host is Ubuntu 24.04.4 x86_64 on a WSL2 6.6.87.2 kernel. Hosted
   workflows name `ubuntu-24.04`, but no native Ubuntu installed-consumer result
   was produced in this baseline pass.
6. Gate explicitly excludes crash-recovery garbage collection and aggregate
   cgroup guarantees. This host mounts cgroup v2 read-only, so it cannot supply
   the delegated parent required for G4.
7. Gate explicitly records publication as false. Mirrors and MirrorECMA source
   versions/tags and local package tests do not by themselves prove current
   registry publication; that state is unknown until publication-specific
   evidence is linked.

## State vocabulary used by downstream work

Every capability is evaluated independently as `sourceImplemented`,
`sourceTested`, `locallyAccepted`, `installedConsumerAccepted`,
`hostedCiAccepted`, and `published`. `sourceImplemented` cites a location at an
exact component revision; the other dimensions are observed states with their
own immutable evidence references or are explicitly unknown. Installed artifacts,
accepted source revisions, published packages and deployed services remain
different objects.

C2 owns capability declarations, component revisions and selected combinations.
E1 owns runs, artifacts, outcomes, completeness and retention. R1/F1 consume
those identities without copying them. G1 owns recovery resource identity and
lifecycle; its later capability export goes through C2 and its observations go
through E1.
