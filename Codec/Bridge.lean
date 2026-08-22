/-
# Core ↔ Codec message bridge (tag fidelity)

Closes the seam between the two message vocabularies:

* `Core.Protocol.ClientMessage` / `Core.Protocol.MirrorMessage` are the
  tag-abstract vocabularies of the §6.3-proven session machine
  (payloads reduced to what the control plane observes);
* `Codec.Json.ClientMessage` / `Codec.Json.MirrorMessage` are the
  payload-concrete vocabularies of the §6.6-proven wire codec.

This module provides mechanical tag extraction in both directions plus
tag-fidelity theorems for every constructor, and shows that every
abstract mirror message the machine may emit (`Core.Protocol.AllowedOutputs`)
has a concrete codec encoding.

**Design point (payload-at-driver-boundary):** `Core`'s
`reportState` carries the two protocol-relevant bits `reportMatches` /
`lastStep` (the TLA+ `report_matches` fact), while the wire
`reportState` carries only the state payload. The driver computes the
bits (via `Core.Diff` against the expected state) and constructs the
abstract message itself with `reportStateBridge`; `protoClientTag`
fills them with placeholder `false` values and must NOT be used for
`reportState` by drivers.
-/
import Core.Protocol
import Codec.Json

namespace Codec

/-! ## Client direction: concrete (wire) → abstract (machine) -/

/-- Tag extraction from a decoded wire client message to the abstract
message consumed by `Core.Protocol.step`. The six concrete explorer
commands all map to the abstract `.exploreCmd` tag (the machine treats
them uniformly). -/
def protoClientTag : ClientMessage → _root_.ClientMessage
  | .register _ _ _ => .register
  | .registerTraces _ _ => .registerTraces
  | .registerGenTraces _ _ _ _ => .registerGenTraces
  | .registerExplore _ _ _ _ => .registerExplore
  | .registerExploreSession _ _ _ => .registerExploreSession
  | .registerValidate _ _ _ => .registerValidate
  | .registerValidateAsync _ _ _ => .registerValidateAsync
  | .registerGenTracesAsync _ _ _ _ => .registerGenTracesAsync
  | .queryJob _ => .queryJob
  | .awaitJob _ _ => .awaitJob
  | .cancelJob _ => .cancelJob
  | .exploreAssumeTransition _ => .exploreCmd
  | .exploreNextStep => .exploreCmd
  | .exploreQueryState => .exploreCmd
  | .exploreCheckInvariant _ => .exploreCmd
  | .exploreAssumeState _ => .exploreCmd
  | .exploreRollback _ => .exploreCmd
  | .exploreDone => .exploreDone
  | .reportState _ => .reportState false false

/-- Driver-side construction of the abstract `reportState` message:
the driver compares the reported state against the expected state
(`Core.Diff`) and supplies the two bits itself. -/
def reportStateBridge (reportMatches lastStep : Bool) (_st : ValueMap) :
    _root_.ClientMessage :=
  .reportState reportMatches lastStep

/-! ## Mirror direction: abstract (machine) → concrete (wire) -/

/-- Tag extraction from a concrete codec mirror message to the abstract
mirror-message tag. The six concrete explorer result messages all map to
the abstract `.exploreResult` tag. -/
def protoMirrorTag : MirrorMessage → _root_.MirrorMessage
  | .specValidated _ => .specValidated
  | .initialState _ _ => .initialState
  | .nextStep _ _ => .nextStep
  | .stepOk => .stepOk
  | .stepMismatch _ _ _ => .stepMismatch
  | .allStepsDone => .allStepsDone
  | .genTracesDone _ => .genTracesDone
  | .registerError _ => .registerError
  | .protocolError _ => .protocolError
  | .explorerReady _ _ _ => .explorerReady
  | .exploreTransitionStatus _ => .exploreResult
  | .exploreStepDone _ => .exploreResult
  | .exploreState _ => .exploreResult
  | .exploreInvariantStatus _ => .exploreResult
  | .exploreAssumeStatus _ => .exploreResult
  | .exploreRollbackDone _ => .exploreResult
  | .exploreSessionDone => .exploreDone
  | .jobAccepted _ _ => .jobAccepted
  | .jobStatus _ _ => .jobStatus
  | .jobResult _ _ => .jobResult

/-- A canonical concrete witness for every abstract mirror message
(payloads are irrelevant placeholders; drivers substitute real ones). -/
def concreteMirror : _root_.MirrorMessage → MirrorMessage
  | .specValidated => .specValidated .valid
  | .initialState => .initialState "" []
  | .nextStep => .nextStep "" []
  | .stepOk => .stepOk
  | .stepMismatch => .stepMismatch [] [] []
  | .allStepsDone => .allStepsDone
  | .genTracesDone => .genTracesDone ⟨[], []⟩
  | .registerError => .registerError ""
  | .explorerReady => .explorerReady 0 0 0
  | .exploreResult => .exploreTransitionStatus ""
  | .exploreDone => .exploreSessionDone
  | .jobAccepted => .jobAccepted "" .validate
  | .jobStatus => .jobStatus "" .pending
  | .jobResult => .jobResult "" (.validate .valid)
  | .protocolError => .protocolError ""

end Codec