# Historical rc.9 iteration — superseded by rc.10

**Continuation:** [rc.10 completion record](../completion-rc10-20261106/README.md).
The rc.9 implementation/native/package results remain bound to their original
bytes. Its installed audit attempt is not credited: the stale registered prefix
and receipt/manifest mismatch are documented by
`rc9-installed-audits-not-credited.json`. The corrected collector and independent
scope verifier reject both actual sealed mixed-candidate bundles. No rc.9 tag
was published or moved.

# Completion iteration — 2026-11-06

The user requested iterating through all remaining release-roadmap work.
Codex retains direct execution ownership. Starting state is recorded by the
November 6 Windows DPM follow-up; preserve every old source/evidence identity.

1. Implement and validate native Windows distribution/evidence prerequisites
   without removing required gates or weakening private-storage boundaries.
2. Freeze exact final source and companion/runtime inputs; construct new packages.
3. Renew affected installed, native, client/model and independent evidence gates.
4. Assemble release admission, immutable publication inputs and rollback handoff.
5. Complete authorized publication/deployment operations at their concrete gates.
6. Retain compatibility and actual workload results; two shipped-cycle acceptance
   cannot be fabricated from source changes or elapsed time.

Broader M4/native-host and speculative scheduling research remain separate from
this selected release campaign. This ledger records intent, not acceptance.

## Progress during the iteration

- Added native NTFS owner ACL, directory-relative no-reparse file access, real
  file-ID checks, durable exclusive publication, and transaction directory guards.
  All five new native filesystem controls and all 19 existing store tests pass.
- Native transaction activation, rollback and all interruption controls pass.
  All 73 distribution tests pass under Windows Python 3.10 and Python 3.12.
- Native evidence collection, real console-break cancellation, attachments,
  finalization, graph controls and privacy tests pass: 151 tests under the
  prepared Python 3.12 runtime. Linux 73 distribution and 151 evidence tests pass
  with the ext4 temporary-directory prerequisite; five Windows-only tests skip
  on Linux.
- Prepared task-local Python 3.12.10 from the retained official carrier and exact
  retained pure Python attrs/jsonschema/pyrsistent wheels; no global install.
- Full native driver candidate 20 is running. Failed earlier attempts remain
  in the original owned stage's logs with dated exclusive names.
- A review follow-up is moving the already-tested DPM creation-time Job Object
  primitive into a hash-pinned shared helper, so the evidence collector no longer
  has a suspended-child-before-assignment acquisition gap. This follow-up still
  requires focused Linux/native validation and a subsequent full-driver run.

Raw iteration artifacts are under `.golden-build/completion-iteration-20261106/`.
Each `overlay-N.json` binds the corresponding tar candidate. Native commands run
in `D:\ModelMirrors\staging\windows-fixes-20261106\Mirrors`; original frozen
rc.8 source and previous acceptance records remain preserved. No final source
freeze, new candidate qualification, release or production operation has yet
been accepted by this iteration.
