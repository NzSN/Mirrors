import Std.Tactic

set_option warningAsError true


/-!
Executable resource accounting for asynchronous jobs. Resource acknowledgements
mean successful acquisition/release by the effectful caller. No OS behavior is
axiomatized here. Proofs cover arbitrary histories, not bounded enumeration.
-/
namespace Core.AsyncResources

inductive ResourceKind where
  | spec | directory | child
  deriving DecidableEq, BEq, Repr

inductive Lease where
  | fresh | held | released
  deriving DecidableEq, BEq, Repr

def Lease.acquisitions : Lease → Nat
  | .fresh => 0 | _ => 1

def Lease.releases : Lease → Nat
  | .released => 1 | _ => 0

def Lease.live : Lease → Nat
  | .held => 1 | _ => 0

theorem lease_accounting (l : Lease) : l.live + l.releases = l.acquisitions := by
  cases l <;> rfl

theorem lease_release_at_most_once (l : Lease) : l.releases ≤ 1 := by
  cases l <;> decide

inductive WorkerStage where
  | queued | active | settled
  deriving DecidableEq, BEq, Repr

inductive Outcome where
  | valid | invalid | traces | failed | cancelled
  deriving DecidableEq, BEq, Repr

def setAt {ι α : Type} [DecidableEq ι] (f : ι → α) (key : ι) (value : α) : ι → α :=
  fun i => if i = key then value else f i

@[simp] theorem setAt_same {ι α : Type} [DecidableEq ι] (f : ι → α) (key : ι) (value : α) :
    setAt f key value key = value := by simp [setAt]

@[simp] theorem setAt_other {ι α : Type} [DecidableEq ι] (f : ι → α) (key i : ι)
    (value : α) (h : i ≠ key) : setAt f key value i = f i := by simp [setAt, h]

/-- A fixed-size runtime record, not a chain of functional map updates. -/
structure ResourceMap where
  spec : Lease := .fresh
  directory : Lease := .fresh
  child : Lease := .fresh
  deriving DecidableEq, BEq, Repr

def ResourceMap.get (m : ResourceMap) : ResourceKind → Lease
  | .spec => m.spec | .directory => m.directory | .child => m.child

instance : CoeFun ResourceMap (fun _ => ResourceKind → Lease) := ⟨ResourceMap.get⟩

def ResourceMap.set (m : ResourceMap) (r : ResourceKind) (lease : Lease) : ResourceMap :=
  match r with
  | .spec => { m with spec := lease }
  | .directory => { m with directory := lease }
  | .child => { m with child := lease }

@[simp] theorem ResourceMap.empty_get (r : ResourceKind) : ({} : ResourceMap) r = .fresh := by
  cases r <;> rfl

@[simp] theorem ResourceMap.set_same (m : ResourceMap) (r : ResourceKind) (lease : Lease) :
    m.set r lease r = lease := by cases r <;> rfl

@[simp] theorem ResourceMap.set_other (m : ResourceMap) (r k : ResourceKind) (lease : Lease)
    (different : k ≠ r) : m.set r lease k = m k := by
  cases r <;> cases k <;> simp_all [ResourceMap.set, ResourceMap.get]

structure Job where
  stage : WorkerStage := .queued
  slot : Lease := .fresh
  ownedSpec : Bool
  resources : ResourceMap := {}
  cancelled : Bool := false
  hook : Bool := false
  stopRequested : Bool := false
  outcome : Option Outcome := none
  childGeneration : Nat := 0

structure Job.Valid (j : Job) : Prop where
  slotActive : j.slot = .held ↔ j.stage = .active
  resourcesOwned : ∀ r, j.resources r = .held → j.stage = .active
  borrowedSpec : j.ownedSpec = false → j.resources .spec = .fresh
  hookActive : j.hook = true → j.stage = .active
  lateCancellation : j.cancelled = true → j.hook = true →
    j.resources .child = .held → j.stopRequested = true

def Job.initial (ownedSpec : Bool) : Job := { ownedSpec }

theorem initial_valid (ownedSpec : Bool) : (Job.initial ownedSpec).Valid := by
  constructor <;> simp [Job.initial]

def Job.noResources (j : Job) : Prop :=
  j.resources .spec ≠ .held ∧ j.resources .directory ≠ .held ∧ j.resources .child ≠ .held

instance (j : Job) : Decidable j.noResources := inferInstanceAs (Decidable (_ ∧ _ ∧ _))

inductive Event where
  | start
  | acquire (resource : ResourceKind)
  | release (resource : ResourceKind)
  | installHook
  | retireHook
  | cancel
  | publish (outcome : Outcome)
  | settle
  deriving DecidableEq, Repr

/-- Business guards reject invalid order and repeated acquisition/release.
There is no post-state invariant test: preservation is proved below. -/
def Job.step (j : Job) : Event → Option Job
  | .start =>
    if j.stage = .queued ∧ j.slot = .fresh then
      some { j with stage := .active, slot := .held }
    else none
  | .acquire r =>
    if j.stage = .active ∧ (j.outcome.isNone = true ∨ j.outcome = some .cancelled) ∧
        (j.resources r = .fresh ∨ (r = .child ∧ j.resources r = .released)) ∧
        (r = .spec → j.ownedSpec = true) ∧ (r = .child → j.hook = false) then
      some { j with resources := j.resources.set r .held,
                    childGeneration := if r = .child ∧ j.resources r = .released then j.childGeneration + 1 else j.childGeneration }
    else none
  | .release r =>
    if j.resources r = .held then
      some { j with resources := j.resources.set r .released,
                    hook := if r = .child then false else j.hook }
    else none
  | .installHook =>
    if j.resources .child = .held ∧ j.hook = false then
      some { j with hook := true, stopRequested := j.cancelled || j.stopRequested }
    else none
  | .retireHook =>
    if j.resources .child ≠ .held then some { j with hook := false } else none
  | .cancel =>
    some { j with cancelled := true, stopRequested := j.hook || j.stopRequested }
  | .publish result =>
    if j.outcome.isSome = true ∨ result = .failed ∨ result = .cancelled ∨ (j.noResources ∧ j.hook = false) then
      some { j with outcome := j.outcome.orElse (fun _ => some result) }
    else none
  | .settle =>
    if j.stage = .active ∧ j.noResources ∧ j.hook = false then
      some { j with stage := .settled, slot := .released }
    else none

private theorem start_valid (j : Job) (h : j.Valid) :
    ({ j with stage := .active, slot := .held } : Job).Valid := by
  constructor
  · simp
  · intros; rfl
  · exact h.borrowedSpec
  · intros; rfl
  · exact h.lateCancellation

private theorem acquire_valid (j : Job) (h : j.Valid) (r : ResourceKind)
    (ha : j.stage = .active) (hb : r = .spec → j.ownedSpec = true)
    (hc : r = .child → j.hook = false) :
    ({ j with resources := j.resources.set r .held,
                    childGeneration := if r = .child ∧ j.resources r = .released then j.childGeneration + 1 else j.childGeneration } : Job).Valid := by
  constructor
  · exact h.slotActive
  · intros; exact ha
  · intro borrowed
    have ne : ResourceKind.spec ≠ r := by
      intro eq
      have := hb eq.symm
      simp_all
    simpa [ne] using h.borrowedSpec borrowed
  · exact h.hookActive
  · intro cancelled hook child
    have ne : ResourceKind.child ≠ r := by
      intro eq
      have := hc eq.symm
      simp_all
    exact h.lateCancellation cancelled hook (by simpa [ne] using child)

private theorem release_valid (j : Job) (h : j.Valid) (r : ResourceKind)
    (hr : j.resources r = .held) :
    ({ j with resources := j.resources.set r .released,
              hook := if r = .child then false else j.hook } : Job).Valid := by
  constructor
  · exact h.slotActive
  · intro k hk
    by_cases eq : k = r
    · simp [eq] at hk
    · exact h.resourcesOwned k (by simpa [eq] using hk)
  · intro borrowed
    have ne : ResourceKind.spec ≠ r := by
      intro eq
      have := h.borrowedSpec borrowed
      subst r
      simp_all
    simpa [ne] using h.borrowedSpec borrowed
  · intro hook
    by_cases eq : r = .child
    · simp [eq] at hook
    · exact h.hookActive (by simpa [eq] using hook)
  · intro cancelled hook child
    by_cases eq : r = .child
    · simp [eq] at hook
    · exact h.lateCancellation cancelled (by simpa [eq] using hook)
        (by simpa [Ne.symm eq] using child)

private theorem install_valid (j : Job) (h : j.Valid) (hc : j.resources .child = .held) :
    ({ j with hook := true, stopRequested := j.cancelled || j.stopRequested } : Job).Valid := by
  constructor
  · exact h.slotActive
  · exact h.resourcesOwned
  · exact h.borrowedSpec
  · intros; exact h.resourcesOwned .child hc
  · intro cancelled _ _; change j.cancelled = true at cancelled; simp [cancelled]

private theorem retire_valid (j : Job) (h : j.Valid) :
    ({ j with hook := false } : Job).Valid := by
  constructor
  · exact h.slotActive
  · exact h.resourcesOwned
  · exact h.borrowedSpec
  · simp
  · simp

private theorem cancel_valid (j : Job) (h : j.Valid) :
    ({ j with cancelled := true, stopRequested := j.hook || j.stopRequested } : Job).Valid := by
  constructor
  · exact h.slotActive
  · exact h.resourcesOwned
  · exact h.borrowedSpec
  · exact h.hookActive
  · intro _ hook _; change j.hook = true at hook; simp [hook]

private theorem settle_valid (j : Job) (h : j.Valid)
    (hr : j.noResources) (hh : j.hook = false) :
    ({ j with stage := .settled, slot := .released } : Job).Valid := by
  constructor
  · simp
  · intro r live
    cases r <;> simp_all [Job.noResources]
  · exact h.borrowedSpec
  · simp [hh]
  · exact h.lateCancellation

/-- Kernel-checked preservation for every event, resource and valid job state. -/
theorem step_preserves (j next : Job) (h : j.Valid) (event : Event)
    (hs : j.step event = some next) : next.Valid := by
  cases event with
  | start =>
    simp only [Job.step] at hs
    split at hs
    · cases hs; exact start_valid j h
    · contradiction
  | acquire r =>
    simp only [Job.step] at hs
    split at hs
    · rename_i guards
      cases hs
      exact acquire_valid j h r guards.1 guards.2.2.2.1 guards.2.2.2.2
    · contradiction
  | release r =>
    simp only [Job.step] at hs
    split at hs
    · rename_i guard
      cases hs; exact release_valid j h r guard
    · contradiction
  | installHook =>
    simp only [Job.step] at hs
    split at hs
    · rename_i guard
      cases hs; exact install_valid j h guard.1
    · contradiction
  | retireHook =>
    simp only [Job.step] at hs
    split at hs
    · cases hs; exact retire_valid j h
    · contradiction
  | cancel =>
    cases hs; exact cancel_valid j h
  | publish result =>
    simp only [Job.step] at hs
    split at hs
    · cases hs; exact { h with }
    · contradiction
  | settle =>
    simp only [Job.step] at hs
    split at hs
    · rename_i guards
      cases hs; exact settle_valid j h guards.2.1 guards.2.2
    · contradiction

/-- An arbitrary finite accepted history. Invalid commands fail rather than
silently changing the ownership state. -/
def Job.run (j : Job) : List Event → Option Job
  | [] => some j
  | event :: rest => (j.step event).bind (fun next => next.run rest)

theorem run_preserves (events : List Event) (j next : Job) (h : j.Valid)
    (hr : j.run events = some next) : next.Valid := by
  induction events generalizing j with
  | nil => simp [Job.run] at hr; subst next; exact h
  | cons event rest ih =>
    cases hs : j.step event with
    | none => simp [Job.run, hs] at hr
    | some intermediate =>
      simp only [Job.run, hs, Option.bind_some] at hr
      exact ih intermediate (step_preserves j intermediate h event hs) hr

inductive Reachable : Job → Prop where
  | initial (ownedSpec : Bool) : Reachable (Job.initial ownedSpec)
  | next {j next : Job} : Reachable j → j.step event = some next → Reachable next

theorem reachable_valid {j : Job} (h : Reachable j) : j.Valid := by
  induction h with
  | initial owned => exact initial_valid owned
  | next _ step ih => exact step_preserves _ _ ih _ step

theorem terminal_stable (j next : Job) (event : Event) (value : Outcome)
    (ho : j.outcome = some value) (hs : j.step event = some next) :
    next.outcome = some value := by
  cases event <;> simp only [Job.step] at hs
  all_goals first
    | (split at hs <;> simp_all <;> subst next <;> rfl)
    | (cases hs; simp [ho])

theorem settled_no_leaks (j : Job) (h : j.Valid) (settled : j.stage = .settled) :
    j.slot ≠ .held ∧ ∀ r, j.resources r ≠ .held := by
  constructor
  · intro held; have := h.slotActive.mp held; simp_all
  · intro r held; have := h.resourcesOwned r held; simp_all

theorem reachable_quiescence_leak_free (j : Job) (h : Reachable j)
    (settled : j.stage = .settled) :
    j.slot.live = 0 ∧ ∀ r, (j.resources r).live = 0 := by
  obtain ⟨slot, resources⟩ := settled_no_leaks j (reachable_valid h) settled
  constructor
  · cases hs : j.slot <;> simp_all [Lease.live]
  · intro r; have hr := resources r; cases hs : j.resources r <;> simp_all [Lease.live]

def Event.local : Event → Bool
  | .start | .settle => false
  | _ => true

theorem local_step_keeps_slot (j next : Job) (event : Event)
    (localEvent : event.local = true) (hs : j.step event = some next) : next.slot = j.slot := by
  cases event <;> simp only [Event.local] at localEvent
  all_goals first | contradiction | skip
  all_goals simp only [Job.step] at hs
  all_goals first
    | (split at hs <;> simp_all <;> subst next <;> rfl)
    | (cases hs; rfl)

theorem step_does_not_reopen (j next : Job) (event : Event)
    (hs : j.step event = some next) (live : next.outcome.isNone = true) :
    j.outcome.isNone = true := by
  cases ho : j.outcome with
  | none => rfl
  | some value =>
    have stable := terminal_stable j next event value ho hs
    simp [stable] at live

theorem start_slot (j next : Job) (hs : j.step .start = some next) :
    j.slot = .fresh ∧ next.slot = .held := by
  simp only [Job.step] at hs
  split at hs
  · rename_i guards
    cases hs; exact ⟨guards.2, rfl⟩
  · contradiction

theorem settle_slot (j next : Job) (hs : j.step .settle = some next) :
    next.slot = .released := by
  simp only [Job.step] at hs
  split at hs
  · cases hs; rfl
  · contradiction

/-- Cumulative accounting includes all sequential child-process incarnations. -/
def Job.acquisitions (j : Job) (r : ResourceKind) : Nat :=
  (if r = .child then j.childGeneration else 0) + (j.resources r).acquisitions

def Job.releases (j : Job) (r : ResourceKind) : Nat :=
  (if r = .child then j.childGeneration else 0) + (j.resources r).releases

theorem job_resource_accounting (j : Job) (r : ResourceKind) :
    (j.resources r).live + j.releases r = j.acquisitions r := by
  have := lease_accounting (j.resources r)
  simp only [Job.acquisitions, Job.releases]
  omega

theorem child_reacquire_advances_generation (j next : Job)
    (released : j.resources .child = .released) (hs : j.step (.acquire .child) = some next) :
    next.childGeneration = j.childGeneration + 1 := by
  simp only [Job.step] at hs
  split at hs
  · cases hs; simp [released]
  · contradiction

theorem generation_monotone_step (j next : Job) (event : Event)
    (hs : j.step event = some next) : j.childGeneration ≤ next.childGeneration := by
  cases event with
  | acquire r =>
    simp only [Job.step] at hs
    split at hs
    · cases hs; dsimp; split <;> omega
    · contradiction
  | start | release _ | installHook | retireHook | settle =>
    simp only [Job.step] at hs
    split at hs
    · cases hs; exact Nat.le_refl _
    · contradiction
  | cancel => cases hs; exact Nat.le_refl _
  | publish _ =>
    simp only [Job.step] at hs
    split at hs
    · cases hs; exact Nat.le_refl _
    · contradiction

theorem generation_monotone_run (events : List Event) (j next : Job)
    (accepted : j.run events = some next) : j.childGeneration ≤ next.childGeneration := by
  induction events generalizing j with
  | nil => simp [Job.run] at accepted; subst next; exact Nat.le_refl _
  | cons event rest ih =>
    cases hs : j.step event with
    | none => simp [Job.run, hs] at accepted
    | some intermediate =>
      simp only [Job.run, hs, Option.bind_some] at accepted
      exact Nat.le_trans (generation_monotone_step j intermediate event hs) (ih intermediate accepted)

theorem released_resource_stays_released (j next : Job) (event : Event) (r : ResourceKind)
    (released : j.resources r = .released) (hs : j.step event = some next)
    (same : r = .child → next.childGeneration = j.childGeneration) :
    next.resources r = .released := by
  cases event with
  | acquire k =>
    simp only [Job.step] at hs
    split at hs
    · rename_i guards
      cases hs
      by_cases eq : r = k
      · subst k
        have child : r = .child := by simpa [released] using guards.2.2.1
        have equalGen := same child
        have releasedChild : j.resources .child = .released := by simpa [child] using released
        simp [child, releasedChild] at equalGen
      · simp [eq, released]
    · contradiction
  | release k =>
    simp only [Job.step] at hs
    split at hs
    · cases hs
      by_cases eq : r = k <;> simp [eq, released]
    · contradiction
  | start | installHook | retireHook | settle =>
    simp only [Job.step] at hs
    split at hs
    · cases hs; exact released
    · contradiction
  | cancel => cases hs; exact released
  | publish value =>
    simp only [Job.step] at hs
    split at hs
    · cases hs; exact released
    · contradiction

theorem released_rejects_release (j : Job) (r : ResourceKind)
    (released : j.resources r = .released) : j.step (.release r) = none := by
  simp [Job.step, released]

/-- No accepted history releases the same incarnation twice. Child processes
may be sequentially reacquired only by advancing their generation. -/
theorem released_has_no_further_release (events : List Event) (j next : Job) (r : ResourceKind)
    (released : j.resources r = .released) (accepted : j.run events = some next)
    (same : r = .child → next.childGeneration = j.childGeneration) :
    Event.release r ∉ events := by
  induction events generalizing j with
  | nil => simp
  | cons event events ih =>
    cases hs : j.step event with
    | none => simp [Job.run, hs] at accepted
    | some intermediate =>
      have different : Event.release r ≠ event := by
        intro eq; subst event; rw [released_rejects_release j r released] at hs; contradiction
      simp only [Job.run, hs, Option.bind_some] at accepted
      have lo := generation_monotone_step j intermediate event hs
      have hi := generation_monotone_run events intermediate next accepted
      have mid : r = .child → intermediate.childGeneration = j.childGeneration := by
        intro child; have := same child; omega
      have tailSame : r = .child → next.childGeneration = intermediate.childGeneration := by
        intro child; have := same child; have := mid child; omega
      simp only [List.mem_cons, not_or]
      exact ⟨different, ih intermediate
        (released_resource_stays_released j intermediate event r released hs mid) accepted tailSame⟩

/-- Returned states carry erased kernel evidence; executable guards are only
those of Job.step. The runtime cannot replace the state with an unchecked row. -/
structure CheckedJob where
  value : Job
  reachable : Reachable value

theorem CheckedJob.valid (j : CheckedJob) : j.value.Valid := reachable_valid j.reachable

def CheckedJob.initial (ownedSpec : Bool) : CheckedJob :=
  ⟨Job.initial ownedSpec, .initial ownedSpec⟩

def CheckedJob.step (j : CheckedJob) (event : Event) : Option CheckedJob :=
  match hs : j.value.step event with
  | none => none
  | some next => some ⟨next, .next j.reachable hs⟩

def CheckedJob.cancel (j : CheckedJob) : CheckedJob :=
  ⟨{ j.value with cancelled := true, stopRequested := j.value.hook || j.value.stopRequested },
    .next (event := .cancel) j.reachable rfl⟩

/-- The exact admission predicate executed by the shared job store. -/
def admissionAllowed (live capacity : Nat) : Bool := decide (live < capacity)

theorem admission_bounded (live capacity : Nat) (accepted : admissionAllowed live capacity = true) :
    live + 1 ≤ capacity := by
  simp only [admissionAllowed, decide_eq_true_eq] at accepted
  omega

/-- Metadata operations shared with the effectful store. They compare only IDs,
so proofs do not require equality or inspection of effectful payloads. -/
def lookupEntry {κ α : Type} [DecidableEq κ] : List (κ × α) → κ → Option α
  | [], _ => none
  | (key, value) :: rest, wanted => if key = wanted then some value else lookupEntry rest wanted

def dropEntry {κ α : Type} [DecidableEq κ] (key : κ) (entries : List (κ × α)) : List (κ × α) :=
  entries.filter (fun entry => decide (entry.1 ≠ key))

theorem lookup_dropped_absent {κ α : Type} [DecidableEq κ] (entries : List (κ × α)) (key : κ) :
    lookupEntry (dropEntry key entries) key = none := by
  induction entries with
  | nil => rfl
  | cons entry rest ih =>
    simp [dropEntry] at ih
    obtain ⟨id, value⟩ := entry
    by_cases eq : id = key <;> simp [dropEntry, lookupEntry, eq, ih]

theorem eviction_preserves_other {κ α : Type} [DecidableEq κ] (entries : List (κ × α))
    (removed wanted : κ) (different : wanted ≠ removed) :
    lookupEntry (dropEntry removed entries) wanted = lookupEntry entries wanted := by
  induction entries with
  | nil => rfl
  | cons entry rest ih =>
    simp [dropEntry] at ih
    obtain ⟨id, value⟩ := entry
    by_cases eq : id = removed
    · subst id; simp [dropEntry, lookupEntry, Ne.symm different, ih]
    · simp [dropEntry, lookupEntry, eq, ih]

namespace Cancellation

/-- Pure hook registry; payloads may be IO actions, but these functions never
execute them. The shell executes only the returned claims, outside its lock. -/
structure Registry (α : Type) where
  cancelled : Bool := false
  nextId : Nat := 0
  hooks : List (Nat × α) := []

structure Registration (α : Type) where
  state : Registry α
  ticket : Option Nat
  immediate : Option α

def register (s : Registry α) (cleanup : α) : Registration α :=
  if s.cancelled then ⟨s, none, some cleanup⟩
  else ⟨{ s with nextId := s.nextId + 1, hooks := (s.nextId, cleanup) :: s.hooks },
        some s.nextId, none⟩

def retire (s : Registry α) (id : Nat) : Registry α :=
  { s with hooks := s.hooks.filter (fun entry => entry.1 != id) }

def cancel (s : Registry α) : Registry α × List (Nat × α) :=
  ({ s with cancelled := true, hooks := [] }, s.hooks)

def Valid (s : Registry α) : Prop :=
  (s.cancelled = true → s.hooks = []) ∧
  (∀ entry ∈ s.hooks, entry.1 < s.nextId)

theorem initial_valid : Valid ({} : Registry α) := by simp [Valid]

theorem register_preserves (s : Registry α) (h : Valid s) (f : α) :
    Valid (register s f).state := by
  unfold register
  split
  · exact h
  · rename_i notClosed
    constructor
    · simp_all
    · intro entry member
      simp only [List.mem_cons] at member
      rcases member with eq | old
      · subst entry; simp
      · have := h.2 entry old; dsimp; omega

theorem retire_preserves (s : Registry α) (h : Valid s) (id : Nat) :
    Valid (retire s id) := by
  constructor
  · intro closed; simp [retire, h.1 closed]
  · intro entry member
    exact h.2 entry (List.mem_filter.mp member).1

theorem cancel_preserves (s : Registry α) : Valid (cancel s).1 := by
  simp [Valid, cancel]

theorem late_registration_emits_cleanup (s : Registry α) (closed : s.cancelled = true)
    (f : α) : (register s f).immediate = some f ∧ (register s f).state = s := by
  simp [register, closed]

theorem registration_keeps_prior_hooks (s : Registry α) (notClosed : s.cancelled = false)
    (f : α) : (register s f).state.hooks = (s.nextId, f) :: s.hooks := by
  simp [register, notClosed]

theorem registration_ticket_fresh (s : Registry α) (h : Valid s) (entry : Nat × α)
    (member : entry ∈ s.hooks) : entry.1 ≠ s.nextId := by
  have := h.2 entry member; omega

theorem cancellation_claims_every_hook (s : Registry α) : (cancel s).2 = s.hooks := rfl

theorem repeated_cancellation_claims_nothing (s : Registry α) :
    (cancel (cancel s).1).2 = [] := rfl

theorem retired_hook_not_claimed (s : Registry α) (id : Nat) (entry : Nat × α)
    (member : entry ∈ (cancel (retire s id)).2) : entry.1 ≠ id := by
  have := (List.mem_filter.mp member).2
  simpa using this

inductive Reachable {α : Type} : Registry α → Prop where
  | initial : Reachable {}
  | register : Reachable s → Reachable (register s f).state
  | retire (ticket : Nat) : Reachable s → Reachable (Cancellation.retire s ticket)
  | cancel : Reachable s → Reachable (cancel s).1

theorem reachable_valid {s : Registry α} (h : Reachable s) : Valid s := by
  induction h with
  | initial => exact initial_valid
  | register _ ih => exact register_preserves _ ih _
  | retire ticket _ ih => exact retire_preserves _ ih _
  | cancel => exact cancel_preserves _

theorem reachable_ticket_unique {s : Registry α} (h : Reachable s) :
    s.hooks.Pairwise (fun a b => a.1 ≠ b.1) := by
  induction h with
  | initial => simp
  | @register s f prior ih =>
    unfold register
    split
    · exact ih
    · apply List.Pairwise.cons
      · intro entry member
        exact Ne.symm (registration_ticket_fresh s (reachable_valid prior) entry member)
      · exact ih
  | retire ticket _ ih => exact List.Pairwise.filter _ ih
  | cancel => simp [cancel]

structure Checked (α : Type) where
  value : Registry α
  reachable : Reachable value

theorem Checked.valid (s : Checked α) : Valid s.value := reachable_valid s.reachable

def Checked.initial : Checked α := ⟨{}, .initial⟩

def Checked.register (s : Checked α) (f : α) : Checked α × Option Nat × Option α :=
  (⟨(Cancellation.register s.value f).state, .register s.reachable⟩,
    (Cancellation.register s.value f).ticket, (Cancellation.register s.value f).immediate)

def Checked.retire (s : Checked α) (id : Nat) : Checked α :=
  ⟨Cancellation.retire s.value id, .retire id s.reachable⟩

def Checked.cancel (s : Checked α) : Checked α × List (Nat × α) :=
  (⟨(Cancellation.cancel s.value).1, .cancel s.reachable⟩, (Cancellation.cancel s.value).2)

end Cancellation

end Core.AsyncResources
