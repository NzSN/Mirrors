# Reproduction handling governance (proposed)

Date: 2026-09-30. Status: **proposed, pending user ratification; preflight
does not consult them today.** No producer or checker change accompanies this
document.

## Scope

`handling` is the closed five-field record carried by
`mirrorecma.reproduction-bundle/v1` (MirrorECMA `src/reproduction-bundle.ts`,
`validateHandling`). It states the governance identifiers under which a
captured reproduction was obtained and may be retained. Reduction receipts
reference the bundle's handling record but do not define or re-derive it
(M3 design §9.4). Validation today is shape/format only; the current producer
(`tools/evidence/reproduction-capture.mjs`) writes documented MirrorECMA
fixture placeholder identifiers under an explicit "governance decision
pending" comment.

## Vocabulary

| Field | Names | Format enforced today |
| --- | --- | --- |
| `consentPolicyId` | The consent basis under which the failure evidence was collected and may be replayed. | Stable id `[A-Za-z0-9][A-Za-z0-9._/-]*` |
| `redactionProfileId` | The redaction profile applied to captured evidence (what must not be retained verbatim). | Stable id |
| `accessPolicyId` | Who may read the retained bundle and its derived artifacts. | Stable id |
| `retentionUntil` | ISO-8601 instant after which the bundle must no longer be retained. | `Date.parse`-able string |
| `deletionPolicyId` | The deletion procedure that satisfies retention and consent withdrawal. | Stable id |

## Owners

| Concern | Owner |
| --- | --- |
| Policy values for real captures (ratification) | user (operator of record) |
| Bundle schema and validation | MirrorECMA (reproduction owner) |
| Local capture defaults and fixture placeholders | Mirrors (evidence owner, `tools/evidence/reproduction-capture.mjs`) |
| Qualification scope requirements (only after ratification) | Mirrors (Q2 scope verifier) |

## Proposed local-qualification values (pending ratification)

Proposed for local qualification profiles only. They are self-describing
placeholders, not policy commitments; producers must not switch to them before
the user ratifies this document, and no checker consumes them today.

| Field | Proposed value |
| --- | --- |
| `consentPolicyId` | `local-qualification-consent/v1` |
| `redactionProfileId` | `local-qualification-redaction/v1` |
| `accessPolicyId` | `local-qualification-access/v1` |
| `retentionUntil` | `2026-12-31T00:00:00Z` (provisional local window; revisit at ratification) |
| `deletionPolicyId` | `local-qualification-deletion/v1` |

Until ratification, bundle producers keep the fixture placeholders
(`fixture-consent/v1`, `fixture-redaction/v1`, `fixture-access/v1`,
`fixture-delete/v1`, `retentionUntil 2026-12-31T00:00:00Z`), and the standing
comment in the capture script continues to mark the decision as pending.

## Rules if ratified

1. Ratified values replace the capture-script placeholders in one coordinated
   change (producer plus any scope/fixture expectations that name them).
2. Changing any of the five values is an evidence-affecting producer change:
   it requires the rule-0.1 chain (identity refresh, snapshot, caches,
   installs, affected-tier reruns) before new evidence is credited.
3. Receipts never restate handling values; they bind bundles by hash, and
   bundle identity already covers the record.
4. Enforcement (preflight consulting consent/access/retention) is a separate
   future decision; nothing here authorizes a runtime policy engine.

## Non-goals

- No schema change, no validator change, and no capture-default change now.
- No claim about the server-side or operator policy registries that will
  eventually own the real values.
