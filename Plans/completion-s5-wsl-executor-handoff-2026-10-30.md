# Generic-executor WSL S3.6/S5 handoff

Date: 2026-10-30

## Authority and scope

The user removed native-runner execution planning and explicitly approved
running S3.6/S5 in the current Ubuntu 26.04.1 WSL2 environment.

Execute S3.6 and then S5.1-S5.20 in
[the revised completion plan](completion-qualification-release-plan-2026-10-30.md)
under [the revised design](../Docs/completion-qualification-release-design.md)
and [the environment decision](execution-decisions.md).
There are no native-runner/M4 tasks in this handoff.

No commit, push, tag move/create, release publication, production service
replacement, production configuration change, or reboot is authorized.
Isolated build/test fixtures on the current WSL2 host and `win10` are allowed;
production must remain unchanged.

## S3.6 current-WSL package acceptance

1. Reobserve actual OS, kernel, filesystem, libc, runtime libraries and tool
   paths. Name the scope `ubuntu-26.04-wsl2-x86_64` and never relabel it as
   Ubuntu 24.04 or native Linux.
2. Verify the retained Linux archive SHA-256
   `39623040464f71bcaff5f1b1002f93b1eec6d19e0bbecabc9a141b523d90b60a`
   and its source/tag binding to `d737aa0`.
3. Run `release.py check-archive` in the current WSL2 environment with no Lean
   or source lookup in the packaged runtime path. Keep the artifact read-only,
   use an owner-only temporary root, and record actual environment/exit and
   packaged CLI results.
4. Create a new S3.6 acceptance record and a new reconciled package-set record.
   Preserve the earlier awaiting-Ubuntu-24.04 records as historical planning,
   not as a failed product gate. Under the revised user-selected scope, S3.6
   and S3.9 may pass only with explicit WSL2 limits.

## S5 current-WSL qualification

1. S5.1-S5.5: freeze the exact source/artifact/companion/toolchain identities,
   C0 catalog selection, distribution locks and actual host observations.
   Materialize owner-only installations, hide source and disable ambient
   PATH/network fallbacks. Complete both required D audits before dependent
   producers.
2. Use existing contracts where they can honestly admit the current WSL host.
   Do not weaken a platform, catalog, installer or evidence check. If an exact
   Ubuntu 26.04 WSL2 distribution/catalog profile is required, implement it
   additively with focused regression tests while preserving the existing
   Ubuntu 24.04 profiles. Record any such source change as a new candidate
   input and stop before exact-candidate S5 continuation until a new S1/S2
   delivery is approved. Do not move the existing local tag.
3. S5.6-S5.14: execute the complete selected 18-command/16-tier M5 inventory,
   including installed replay/reproduction/reduction/mutation/recovery,
   remote model validation, the 22-row client matrix, and installed DPM with
   `freshModelCheck:false`. No required row may become an optional skip.
4. Use the Mirrors CLI against a freshly observed owned remote service. Do not
   start Apalache or TLC on the WSL2 coordinator. On `win10`, use only a new
   isolated task-owned oracle and fixtures; reobserve endpoint, server binary,
   Java/JAR, certificate and source identities, exchange no existing private
   key, and confirm owned cleanup and production stability.
5. S5.12: on an admitted Windows live-check host, run full native `lake test`
   and the required native integer-map/compiler/runtime/TLS tiers at the exact
   candidate. If a required live backend cannot be admitted, retain the skip
   and report S5 partial rather than converting the earlier eight-suite pass.
6. S5.15-S5.20: finalize the C0 -> D -> R0 -> R1 -> Q DAG, run linked Q1 and
   independent installed Q2 with source/producer scratch hidden, network
   unshared and inputs read-only. Execute all six actual negative controls and
   repeat offline verification after stopping the owned oracle.
7. Retain results in a new `Plans/completion-s5-wsl-evidence-20261030/`
   directory and an owner-only durable evidence store. Include an inventory,
   independent verifier, exact claim scope, failed attempts, cleanup and all
   remaining blockers. Do not rewrite earlier evidence.

Work in stage order and preserve the shared checkout. If a concrete source
defect or profile gap requires edits, make only focused additive changes with
regressions, rerun affected local gates, and report the required new identity
freeze. Do not claim Ubuntu 24.04, native M4, release admission, publication,
deployment, or reboot acceptance from this handoff.

