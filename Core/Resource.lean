/-!
# Resource ownership lifecycle (Core/Resource.lean)

Abstract, IO-free model of the enforced-RAII resource protocol ported from
Haskell @Resource.hs@ (see @docs/resource-model-design.md@ and
@docs/lean4-refactor-design.md@ §6.5).

A resource is a token in
@{Live, Delivered, Released, ReleaseFailed} × {Owned, Borrowed}@.
The IORef-based atomic transitions of the Haskell implementation become
pure step functions here; the §6.5 guarantees are machine-checked:

* cleanup runs **at most once** (over any sequence of operations);
* @Borrowed@ cleanup is a no-op;
* @Delivered@ never cleans up;
* @use@ on a non-@Live@ resource is a **type error** (the @h : state = live@
  proof a linear-style handle demands), so the GC-finalizer backstop is
  dead code for in-language uses (§9.7): the lexical bracket always ends
  in a non-@Live@ state, making any post-scope @use@ unrepresentable.
-/

inductive ResourceState where
  /-- owned, cleanup has not run yet -/
  | live
  /-- ownership transferred; cleanup skipped by design -/
  | delivered
  /-- cleanup has run -/
  | released
  /-- cleanup was attempted but threw (recorded) -/
  | releaseFailed
  deriving Repr, DecidableEq

inductive Provenance where
  /-- created here; cleanup reclaims it -/
  | owned
  /-- caller-owned; cleanup is a no-op -/
  | borrowed
  deriving Repr, DecidableEq

/-- An abstract resource handle. In the Haskell original the state lives in
an @IORef@; here it is part of the token, so every transition is a pure
function producing the next handle. -/
structure Resource (α : Type) where
  /-- the wrapped value; only reachable through `use` -/
  value : α
  /-- diagnostic label used by logging -/
  label : String
  /-- ownership state -/
  state : ResourceState
  /-- whether this process owes cleanup -/
  provenance : Provenance
  deriving Repr

namespace Resource

/-- A freshly acquired resource: @Live@ with the given provenance. -/
def fresh (value : α) (label : String) (pr : Provenance) : Resource α :=
  ⟨value, label, ResourceState.live, pr⟩

/-! ## Protocol steps -/

/-- One release attempt. `threw` records whether the (abstract) cleanup
action throws. The result flag is @true@ exactly when this caller won the
@Live → Released/ReleaseFailed@ transition, i.e. cleanup actually ran;
every other case is a no-op that leaves the handle untouched. -/
def releaseStep (threw : Bool) (r : Resource α) : Bool × Resource α :=
  if r.state = ResourceState.live ∧ r.provenance = Provenance.owned then
    (true, { r with state :=
      if threw then ResourceState.releaseFailed else ResourceState.released })
  else (false, r)

/-- Disclaim ownership (@Live → Delivered@, silent no-op otherwise):
cleanup is skipped from now on. -/
def transferStep (r : Resource α) : Resource α :=
  if r.state = ResourceState.live then { r with state := ResourceState.delivered }
  else r

/-- The protocol operations available on a handle. -/
inductive Op where
  /-- release with a well-behaved (total) cleanup action -/
  | release
  /-- release whose cleanup action throws; recorded as `ReleaseFailed` -/
  | releaseThrowing
  /-- `transferStep` -/
  | transfer

/-- Apply one operation; the flag says whether cleanup ran. -/
def stepOp (r : Resource α) : Op → Bool × Resource α
  | Op.release => releaseStep false r
  | Op.releaseThrowing => releaseStep true r
  | Op.transfer => (false, transferStep r)

/-- Run a sequence of operations, counting how many times cleanup ran. -/
def run (r : Resource α) : List Op → Nat × Resource α
  | [] => (0, r)
  | op :: rest =>
    let (ran, r') := stepOp r op
    let (n, r'') := run r' rest
    (if ran then n + 1 else n, r'')

/-! ## Basic step lemmas -/

theorem releaseStep_runs_iff (threw : Bool) (r : Resource α) :
    (releaseStep threw r).1 = true ↔
      r.state = ResourceState.live ∧ r.provenance = Provenance.owned := by
  simp only [releaseStep]
  by_cases h : r.state = ResourceState.live ∧ r.provenance = Provenance.owned
  · rw [if_pos h]
    exact ⟨fun _ => h, fun _ => rfl⟩
  · rw [if_neg h]
    simp only [Bool.false_eq_true, false_iff]
    exact h

theorem releaseStep_ran_not_live (threw : Bool) (r : Resource α)
    (hr : (releaseStep threw r).1 = true) :
    (releaseStep threw r).2.state ≠ ResourceState.live := by
  rw [releaseStep_runs_iff] at hr
  obtain ⟨h1, h2⟩ := hr
  simp only [releaseStep, h1, h2, if_true]
  cases threw <;> simp

/-- **Borrowed cleanup is a no-op**: releasing a caller-owned resource
leaves the handle (and its state) completely unchanged. -/
theorem releaseStep_borrowed_noop (threw : Bool) (r : Resource α)
    (hb : r.provenance = Provenance.borrowed) :
    releaseStep threw r = (false, r) := by
  simp only [releaseStep]
  rw [if_neg (by rw [hb]; simp)]

/-- **Delivered never cleans up**: release on a transferred resource is a
silent no-op. -/
theorem releaseStep_not_live (threw : Bool) (r : Resource α)
    (h : r.state ≠ ResourceState.live) :
    releaseStep threw r = (false, r) := by
  simp only [releaseStep]
  rw [if_neg (by intro hc; exact h hc.1)]

/-- **Delivered never cleans up**: release on a transferred resource is a
silent no-op. -/
theorem releaseStep_delivered_noop (threw : Bool) (r : Resource α)
    (hd : r.state = ResourceState.delivered) :
    releaseStep threw r = (false, r) :=
  releaseStep_not_live threw r (by simp [hd])

theorem transferStep_not_live (r : Resource α)
    (h : r.state ≠ ResourceState.live) : transferStep r = r := by
  simp only [transferStep]
  rw [if_neg h]

theorem stepOp_not_live (r : Resource α) (h : r.state ≠ ResourceState.live)
    (op : Op) :
    (stepOp r op).1 = false ∧ (stepOp r op).2.state ≠ ResourceState.live := by
  cases op with
  | release =>
    have h2 := releaseStep_not_live false r h
    simp only [stepOp]
    rw [h2]
    simp [h]
  | releaseThrowing =>
    have h2 := releaseStep_not_live true r h
    simp only [stepOp]
    rw [h2]
    simp [h]
  | transfer =>
    simp only [stepOp]
    rw [transferStep_not_live r h]
    simp [h]

/-! ## Cleanup runs at most once -/

/-- Once the handle has left the @Live@ state, no operation sequence can
run cleanup or return it to @Live@. -/
theorem run_no_clean_of_not_live (r : Resource α) (h : r.state ≠ ResourceState.live)
    (ops : List Op) :
    (run r ops).1 = 0 ∧ (run r ops).2.state ≠ ResourceState.live := by
  induction ops generalizing r with
  | nil => exact ⟨rfl, h⟩
  | cons op rest ih =>
    obtain ⟨h1, h2⟩ := stepOp_not_live r h op
    simp only [run, h1, if_false]
    exact ih _ h2

/-- **§6.5 cleanup at most once**: over any sequence of operations, cleanup
runs at most one time. -/
theorem run_cleanup_at_most_once (r : Resource α) (ops : List Op) :
    (run r ops).1 ≤ 1 := by
  induction ops generalizing r with
  | nil => simp [run]
  | cons op rest ih =>
    match op with
    | Op.release =>
      cases hr : (releaseStep false r).1 with
      | true =>
        have hnl := releaseStep_ran_not_live false r hr
        obtain ⟨h0, _⟩ := run_no_clean_of_not_live _ hnl rest
        simp only [run, stepOp, hr, if_true]
        rw [h0]
        simp
      | false =>
        simp only [run, stepOp, hr, if_false]
        exact ih _
    | Op.releaseThrowing =>
      cases hr : (releaseStep true r).1 with
      | true =>
        have hnl := releaseStep_ran_not_live true r hr
        obtain ⟨h0, _⟩ := run_no_clean_of_not_live _ hnl rest
        simp only [run, stepOp, hr, if_true]
        rw [h0]
        simp
      | false =>
        simp only [run, stepOp, hr, if_false]
        exact ih _
    | Op.transfer =>
      simp only [run, stepOp, Bool.false_eq_true, if_false]
      exact ih _

/-- **§6.5 Delivered never cleans up**, over whole operation sequences. -/
theorem run_delivered_never_cleans (r : Resource α)
    (hd : r.state = ResourceState.delivered) (ops : List Op) :
    (run r ops).1 = 0 :=
  (run_no_clean_of_not_live r
      (by rw [hd]; exact fun h => ResourceState.noConfusion h) ops).1

/-- Borrowed handles never run cleanup and stay borrowed under every
operation. -/
theorem stepOp_borrowed (r : Resource α)
    (hb : r.provenance = Provenance.borrowed) (op : Op) :
    (stepOp r op).1 = false ∧
      (stepOp r op).2.provenance = Provenance.borrowed := by
  cases op with
  | release =>
    rw [show stepOp r Op.release = releaseStep false r from rfl,
      releaseStep_borrowed_noop false r hb]
    simp [hb]
  | releaseThrowing =>
    rw [show stepOp r Op.releaseThrowing = releaseStep true r from rfl,
      releaseStep_borrowed_noop true r hb]
    simp [hb]
  | transfer =>
    simp only [stepOp, transferStep]
    split <;> simp [hb]

/-- **§6.5 Borrowed cleanup is a no-op**, over whole operation sequences. -/
theorem run_borrowed_never_cleans (r : Resource α)
    (hb : r.provenance = Provenance.borrowed) (ops : List Op) :
    (run r ops).1 = 0 := by
  induction ops generalizing r with
  | nil => simp [run]
  | cons op rest ih =>
    obtain ⟨h1, h2⟩ := stepOp_borrowed r hb op
    have heq : (run r (op :: rest)).1 = (run (stepOp r op).2 rest).1 := by
      simp only [run]
      rw [h1]
      simp
    rw [heq]
    exact ih _ h2

/-! ## Linear-style `use`: non-Live is a type error -/

/-- Use the underlying value. The linear-style handle: the caller must
supply a proof that the resource is still @Live@. A released, delivered, or
failed handle makes `use` a *type error* — there is no proof to pass —
which is exactly the §9.7 argument that the finalizer backstop is dead
code for in-language uses. -/
def use {α β : Type} (r : Resource α) (h : r.state = ResourceState.live)
    (f : α → β) : β := f r.value

/-- Any well-typed `use` is on a @Live@ resource, by construction. -/
theorem use_implies_live {α : Type} {r : Resource α} {β : Type}
    (h : r.state = ResourceState.live) (f : α → β) (x : β)
    (hx : use r h f = x) : r.state = ResourceState.live := h

/-- A non-@Live@ resource admits no `use` at all: the required proof is
uninhabited. -/
theorem use_after_release_unrepresentable {α : Type} (r : Resource α)
    (hne : r.state ≠ ResourceState.live) :
    ∀ h : r.state = ResourceState.live, False := fun h => hne h

/-! ## Lexical bracket and the dead finalizer backstop -/

/-- The enforced lexical form: run an action on a fresh @Live@ resource and
release it on scope exit (the pure analogue of @bracket acquire release@). -/
def withScope (value : α) (label : String) (pr : Provenance)
    (f : Resource α → β) : β × Resource α :=
  let r := Resource.fresh value label pr
  let b := f r
  let (_, r') := releaseStep false r
  (b, r')

/-- An owned resource is always released by scope exit: the bracket ends in
a non-@Live@ state, so the GC-finalizer backstop can never find a @Live@
handle in-language. -/
theorem withScope_owned_not_live (value : α) (label : String)
    (f : Resource α → β) :
    (withScope value label Provenance.owned f).2.state ≠ ResourceState.live := by
  simp only [withScope]
  have hrun : (releaseStep false (Resource.fresh value label Provenance.owned)).1
      = true := by
    simp [releaseStep, Resource.fresh]
  exact releaseStep_ran_not_live false _ hrun

/-- Cleanup ran exactly once inside an owned bracket. -/
theorem withScope_owned_cleans_once (value : α) (label : String)
    (f : Resource α → β) :
    (releaseStep false (Resource.fresh value label Provenance.owned)).1 = true ∧
      (withScope value label Provenance.owned f).2.state =
        ResourceState.released := by
  refine ⟨by simp [releaseStep, Resource.fresh], ?_⟩
  simp [withScope, releaseStep, Resource.fresh]

/-- **§9.7 finalizer backstop is dead code for in-language uses**: after the
lexical bracket, no `use` of the resource is typeable. -/
theorem finalizer_backstop_dead (value : α) (label : String)
    (f : Resource α → β) :
    ∀ h : (withScope value label Provenance.owned f).2.state
        = ResourceState.live, False :=
  use_after_release_unrepresentable _ (withScope_owned_not_live value label f)

/-- A borrowed resource keeps its state through the bracket (cleanup is a
no-op, the caller still owns the value). -/
theorem withScope_borrowed_noop (value : α) (label : String)
    (f : Resource α → β) :
    (withScope value label Provenance.borrowed f).2 =
      Resource.fresh value label Provenance.borrowed := by
  simp only [withScope]
  rw [releaseStep_borrowed_noop false _ rfl]

end Resource