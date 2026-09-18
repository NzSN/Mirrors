import Core.AsyncOwnership
import Lean

set_option warningAsError true

/-! Kernel-checked non-vacuity examples and an axiom audit for the async resource
proofs. Normal runtime guard/OS regressions remain in JobStoreSpec/ApalacheCliSpec. -/
open Core.AsyncResources

private def sequentialChildren : List Event :=
  [.start, .acquire .spec, .acquire .directory,
   .acquire .child, .installHook, .release .child,
   .acquire .child, .installHook, .release .child,
   .release .directory, .release .spec, .publish .valid, .settle]

example : ((Job.initial true).run sequentialChildren).map (·.childGeneration) = some 1 := by decide
example : ((Job.initial true).run sequentialChildren).map (·.stage) = some .settled := by decide
example : ((Job.initial true).run sequentialChildren).map (·.outcome) = some (some .valid) := by decide
example : ((Job.initial true).run [.start, .acquire .spec, .settle]).isNone = true := by decide
example : ((Job.initial true).run [.start, .acquire .child, .publish .valid]).isNone = true := by decide
example : ((Job.initial false).run [.start, .acquire .spec]).isNone = true := by decide
example : ((Job.initial true).run [.start, .acquire .directory, .release .directory,
    .release .directory]).isNone = true := by decide
example : ((Job.initial true).run [.start, .acquire .spec, .release .spec,
    .acquire .spec]).isNone = true := by decide
example : ((Job.initial true).run [.start, .acquire .child, .cancel,
    .installHook]).map (·.stopRequested) = some true := by decide

#print axioms admission_bounded
#print axioms eviction_preserves_other
#print axioms lookup_dropped_absent
#print axioms step_preserves
#print axioms reachable_valid
#print axioms released_has_no_further_release
#print axioms Cancellation.reachable_ticket_unique
#print axioms world_step_preserves
#print axioms world_reachable_invariant
#print axioms active_jobs_bounded
#print axioms world_terminal_stable
#print axioms reachable_world_quiescence_leak_free
#print axioms quiescent_accounting_balanced

run_cmd do
  let permitted := #[``propext, ``Classical.choice, ``Quot.sound]
  for declaration in #[``Core.AsyncResources.admission_bounded,
      ``Core.AsyncResources.eviction_preserves_other,
      ``Core.AsyncResources.lookup_dropped_absent,
      ``Core.AsyncResources.step_preserves,
      ``Core.AsyncResources.reachable_valid,
      ``Core.AsyncResources.released_has_no_further_release,
      ``Core.AsyncResources.Cancellation.reachable_ticket_unique,
      ``Core.AsyncResources.world_step_preserves,
      ``Core.AsyncResources.world_reachable_invariant,
      ``Core.AsyncResources.active_jobs_bounded,
      ``Core.AsyncResources.world_terminal_stable,
      ``Core.AsyncResources.reachable_world_quiescence_leak_free,
      ``Core.AsyncResources.quiescent_accounting_balanced] do
    for dependency in (← Lean.collectAxioms declaration) do
      unless permitted.contains dependency do
        throwError "{declaration} depends on unapproved axiom {dependency}"

def main : IO UInt32 := do
  IO.println "ASYNC RESOURCE PROOFS GREEN"
  return 0
