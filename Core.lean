import Core.Trace
import Core.Diff
import Core.Resource
import Core.Protocol
import Core.Jobs
import Core.Value

/-!
# The verified pure core (Layer 0, design §5.1)

Modules (per Docs/lean4-refactor-design.md):
- `Core.Value`    : ITF Value + decidable, proven set equality (done)
- `Core.Trace`    : ItfTrace, TraceState, applyParamVars, traceSteps
- `Core.Diff`     : diffState, DiffHint, caps + §6.1 theorems
- `Core.Protocol` : ClientMessage, MirrorMessage, session machine
- `Core.Jobs`     : async job state machine + §6.4 theorems
- `Core.Resource` : abstract lifecycle model + §6.5 theorems
-/