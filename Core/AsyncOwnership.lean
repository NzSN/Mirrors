import Core.AsyncResources

set_option warningAsError true


/-! Global async ownership model, universally quantified over finite populations.
The per-job machine is the executable machine used by the shell. This module
proves the composition rules, including closing owners and borrowed awaits.
-/
namespace Core.AsyncResources

inductive ConnectionPhase where
  | open | closing | closed
  deriving DecidableEq, BEq

structure OwnedJob (owners : Nat) where
  owner : Fin owners
  stored : Bool := true
  body : Job

structure World (jobs owners slots : Nat) where
  connections : Fin owners → ConnectionPhase
  entries : Fin jobs → Option (OwnedJob owners)
  permits : Fin slots → Option (Fin jobs)
  waiting : Fin owners → Option (Fin jobs)

structure World.Valid (w : World jobs owners slots) : Prop where
  jobValid : ∀ i row, w.entries i = some row → row.body.Valid
  storedOwner : ∀ i row, w.entries i = some row → row.stored = true →
    w.connections row.owner ≠ .closed
  permitValid : ∀ slot i, w.permits slot = some i →
    ∃ row, w.entries i = some row ∧ row.body.slot = .held
  permitUnique : ∀ a b i, w.permits a = some i → w.permits b = some i → a = b
  activeCovered : ∀ i row, w.entries i = some row → row.body.slot = .held →
    ∃ slot, w.permits slot = some i
  waitOwned : ∀ c i, w.waiting c = some i → w.connections c = .open

def World.initial : World jobs owners slots :=
  ⟨fun _ => .open, fun _ => none, fun _ => none, fun _ => none⟩

theorem world_initial_valid : (World.initial : World jobs owners slots).Valid := by
  constructor <;> simp [World.initial]

/-- Local body operations preserve owner identity and metadata visibility. -/
def World.bodyUpdate (w : World jobs owners slots) (i : Fin jobs)
    (row : OwnedJob owners) (next : Job) : World jobs owners slots :=
  { w with entries := setAt w.entries i (some { row with body := next }) }

private theorem body_update_valid (w : World jobs owners slots) (h : w.Valid)
    (i : Fin jobs) (row : OwnedJob owners) (found : w.entries i = some row)
    (next : Job) (valid : next.Valid) (slotSame : next.slot = row.body.slot) :
    (w.bodyUpdate i row next).Valid := by
  constructor
  · intro k other hk
    by_cases eq : k = i
    · subst k; simp [World.bodyUpdate] at hk; subst other; exact valid
    · exact h.jobValid k other (by simpa [World.bodyUpdate, setAt, eq] using hk)
  · intro k other hk stored
    by_cases eq : k = i
    · subst k; simp [World.bodyUpdate] at hk; subst other
      exact h.storedOwner i row found stored
    · exact h.storedOwner k other (by simpa [World.bodyUpdate, setAt, eq] using hk) stored
  · intro s k hs
    obtain ⟨other, ho, held⟩ := h.permitValid s k hs
    by_cases eq : k = i
    · subst k; rw [found] at ho; cases ho
      exact ⟨{ row with body := next }, by simp [World.bodyUpdate], by simpa [slotSame] using held⟩
    · exact ⟨other, by simpa [World.bodyUpdate, setAt, eq] using ho, held⟩
  · exact h.permitUnique
  · intro k other hk held
    by_cases eq : k = i
    · subst k; simp [World.bodyUpdate] at hk; subst other
      exact h.activeCovered i row found (by simpa [slotSame] using held)
    · exact h.activeCovered k other (by simpa [World.bodyUpdate, setAt, eq] using hk) held
  · exact h.waitOwned

/-- A connection changes phase only when no blocked await is left behind and
no newly closed owner still has a stored job. These are close-operation guards,
not a test of the whole post-state invariant. -/
def World.connectionUpdate (w : World jobs owners slots) (c : Fin owners)
    (phase : ConnectionPhase) : World jobs owners slots :=
  { w with connections := setAt w.connections c phase, waiting := setAt w.waiting c none }

private theorem connection_update_valid (w : World jobs owners slots) (h : w.Valid)
    (c : Fin owners) (phase : ConnectionPhase)
    (drained : phase = .closed → ∀ i row, w.entries i = some row → row.owner = c → row.stored = false) :
    (w.connectionUpdate c phase).Valid := by
  constructor
  · exact h.jobValid
  · intro i row found stored
    by_cases eq : row.owner = c
    · simp only [World.connectionUpdate, setAt, eq, if_pos]
      intro closed
      have := drained closed i row found eq
      simp_all
    · simpa [World.connectionUpdate, setAt, eq] using h.storedOwner i row found stored
  · exact h.permitValid
  · exact h.permitUnique
  · exact h.activeCovered
  · intro other i waiter
    by_cases eq : other = c
    · subst other; simp [World.connectionUpdate] at waiter
    · simpa [World.connectionUpdate, setAt, eq] using
        h.waitOwned other i (by simpa [World.connectionUpdate, setAt, eq] using waiter)

def World.evict (w : World jobs owners slots) (i : Fin jobs) (row : OwnedJob owners) : World jobs owners slots :=
  { w with entries := setAt w.entries i (some { row with stored := false }) }

private theorem evict_valid (w : World jobs owners slots) (h : w.Valid)
    (i : Fin jobs) (row : OwnedJob owners) (found : w.entries i = some row) :
    (w.evict i row).Valid := by
  constructor
  · intro k other hk
    by_cases eq : k = i
    · subst k; simp [World.evict] at hk; subst other; exact h.jobValid i row found
    · exact h.jobValid k other (by simpa [World.evict, setAt, eq] using hk)
  · intro k other hk stored
    by_cases eq : k = i
    · subst k; simp [World.evict] at hk; subst other; contradiction
    · exact h.storedOwner k other (by simpa [World.evict, setAt, eq] using hk) stored
  · intro slot k hs
    obtain ⟨other, ho, held⟩ := h.permitValid slot k hs
    by_cases eq : k = i
    · subst k; rw [found] at ho; cases ho
      exact ⟨{ row with stored := false }, by simp [World.evict], held⟩
    · exact ⟨other, by simpa [World.evict, setAt, eq] using ho, held⟩
  · exact h.permitUnique
  · intro k other hk held
    by_cases eq : k = i
    · subst k; simp [World.evict] at hk; subst other
      exact h.activeCovered i row found held
    · exact h.activeCovered k other (by simpa [World.evict, setAt, eq] using hk) held
  · exact h.waitOwned

def World.awaitUpdate (w : World jobs owners slots) (c : Fin owners)
    (job : Option (Fin jobs)) : World jobs owners slots :=
  { w with waiting := setAt w.waiting c job }

private theorem await_update_valid (w : World jobs owners slots) (h : w.Valid)
    (c : Fin owners) (job : Option (Fin jobs)) (enabled : job.isSome = true → w.connections c = .open) :
    (w.awaitUpdate c job).Valid := by
  constructor
  · exact h.jobValid
  · exact h.storedOwner
  · exact h.permitValid
  · exact h.permitUnique
  · exact h.activeCovered
  · intro other i hi
    by_cases eq : other = c
    · subst other; simp [World.awaitUpdate] at hi
      exact enabled (by simp [hi])
    · exact h.waitOwned other i (by simpa [World.awaitUpdate, setAt, eq] using hi)

def World.admit (w : World jobs owners slots) (i : Fin jobs) (c : Fin owners)
    (ownedSpec : Bool) : World jobs owners slots :=
  { w with entries := setAt w.entries i (some ⟨c, true, Job.initial ownedSpec⟩) }

private theorem admit_valid (w : World jobs owners slots) (h : w.Valid)
    (i : Fin jobs) (c : Fin owners) (ownedSpec : Bool)
    (empty : w.entries i = none) (openOwner : w.connections c = .open) :
    (w.admit i c ownedSpec).Valid := by
  constructor
  · intro k row hk
    by_cases eq : k = i
    · subst k; simp [World.admit] at hk; subst row; exact initial_valid ownedSpec
    · exact h.jobValid k row (by simpa [World.admit, setAt, eq] using hk)
  · intro k row hk stored
    by_cases eq : k = i
    · subst k; simp [World.admit] at hk; subst row; simp [World.admit, openOwner]
    · exact h.storedOwner k row (by simpa [World.admit, setAt, eq] using hk) stored
  · intro slot k hs
    obtain ⟨row, hr, held⟩ := h.permitValid slot k hs
    have ne : k ≠ i := by intro eq; subst k; simp [empty] at hr
    exact ⟨row, by simpa [World.admit, setAt, ne] using hr, held⟩
  · exact h.permitUnique
  · intro k row hk held
    by_cases eq : k = i
    · subst k; simp [World.admit] at hk; subst row; simp [Job.initial] at held
    · exact h.activeCovered k row (by simpa [World.admit, setAt, eq] using hk) held
  · exact h.waitOwned

def World.grant (w : World jobs owners slots) (i : Fin jobs) (row : OwnedJob owners)
    (next : Job) (slot : Fin slots) : World jobs owners slots :=
  { w with entries := setAt w.entries i (some { row with body := next }),
           permits := setAt w.permits slot (some i) }

private theorem grant_valid (w : World jobs owners slots) (h : w.Valid)
    (i : Fin jobs) (row : OwnedJob owners) (found : w.entries i = some row)
    (next : Job) (valid : next.Valid) (oldFree : row.body.slot ≠ .held)
    (newHeld : next.slot = .held) (slot : Fin slots) (free : w.permits slot = none) :
    (w.grant i row next slot).Valid := by
  have notHeldElsewhere : ∀ s, w.permits s ≠ some i := by
    intro s hs
    obtain ⟨other, ho, held⟩ := h.permitValid s i hs
    rw [found] at ho; cases ho; exact oldFree held
  constructor
  · intro k other hk
    by_cases eq : k = i
    · subst k; simp [World.grant] at hk; subst other; exact valid
    · exact h.jobValid k other (by simpa [World.grant, setAt, eq] using hk)
  · intro k other hk stored
    by_cases eq : k = i
    · subst k; simp [World.grant] at hk; subst other; exact h.storedOwner i row found stored
    · exact h.storedOwner k other (by simpa [World.grant, setAt, eq] using hk) stored
  · intro s k hs
    by_cases eq : s = slot
    · subst s; simp [World.grant] at hs; subst k
      exact ⟨{ row with body := next }, by simp [World.grant], newHeld⟩
    · have old : w.permits s = some k := by simpa [World.grant, setAt, eq] using hs
      obtain ⟨other, ho, held⟩ := h.permitValid s k old
      have ne : k ≠ i := by intro eq; subst k; exact notHeldElsewhere s old
      exact ⟨other, by simpa [World.grant, setAt, ne] using ho, held⟩
  · intro a b k ha hb
    by_cases ea : a = slot
    · subst a; simp [World.grant] at ha; subst k
      by_cases eb : b = slot
      · exact eb.symm
      · have old : w.permits b = some i := by simpa [World.grant, setAt, eb] using hb
        exact False.elim (notHeldElsewhere b old)
    · by_cases eb : b = slot
      · subst b; simp [World.grant] at hb; subst k
        have old : w.permits a = some i := by simpa [World.grant, setAt, ea] using ha
        exact False.elim (notHeldElsewhere a old)
      · exact h.permitUnique a b k
          (by simpa [World.grant, setAt, ea] using ha)
          (by simpa [World.grant, setAt, eb] using hb)
  · intro k other hk held
    by_cases eq : k = i
    · subst k; exact ⟨slot, by simp [World.grant]⟩
    · have old : w.entries k = some other := by simpa [World.grant, setAt, eq] using hk
      obtain ⟨s, hs⟩ := h.activeCovered k other old held
      have ne : s ≠ slot := by intro eq; subst s; simp [free] at hs
      exact ⟨s, by simpa [World.grant, setAt, ne] using hs⟩
  · exact h.waitOwned

def World.reclaim (w : World jobs owners slots) (i : Fin jobs) (row : OwnedJob owners)
    (next : Job) (slot : Fin slots) : World jobs owners slots :=
  { w with entries := setAt w.entries i (some { row with body := next }),
           permits := setAt w.permits slot none }

private theorem reclaim_valid (w : World jobs owners slots) (h : w.Valid)
    (i : Fin jobs) (row : OwnedJob owners) (found : w.entries i = some row)
    (next : Job) (valid : next.Valid) (newFree : next.slot ≠ .held)
    (slot : Fin slots) (owned : w.permits slot = some i) :
    (w.reclaim i row next slot).Valid := by
  constructor
  · intro k other hk
    by_cases eq : k = i
    · subst k; simp [World.reclaim] at hk; subst other; exact valid
    · exact h.jobValid k other (by simpa [World.reclaim, setAt, eq] using hk)
  · intro k other hk stored
    by_cases eq : k = i
    · subst k; simp [World.reclaim] at hk; subst other; exact h.storedOwner i row found stored
    · exact h.storedOwner k other (by simpa [World.reclaim, setAt, eq] using hk) stored
  · intro s k hs
    have ne : s ≠ slot := by intro eq; subst s; simp [World.reclaim] at hs
    have old : w.permits s = some k := by simpa [World.reclaim, setAt, ne] using hs
    have otherKey : k ≠ i := by
      intro eq; subst k; exact ne (h.permitUnique s slot i old owned)
    obtain ⟨other, ho, held⟩ := h.permitValid s k old
    exact ⟨other, by simpa [World.reclaim, setAt, otherKey] using ho, held⟩
  · intro a b k ha hb
    have ea : a ≠ slot := by intro eq; subst a; simp [World.reclaim] at ha
    have eb : b ≠ slot := by intro eq; subst b; simp [World.reclaim] at hb
    exact h.permitUnique a b k (by simpa [World.reclaim, setAt, ea] using ha)
      (by simpa [World.reclaim, setAt, eb] using hb)
  · intro k other hk held
    by_cases eq : k = i
    · subst k; simp [World.reclaim] at hk; subst other; exact False.elim (newFree held)
    · have old : w.entries k = some other := by simpa [World.reclaim, setAt, eq] using hk
      obtain ⟨s, hs⟩ := h.activeCovered k other old held
      have ne : s ≠ slot := by
        intro eq; subst s; rw [owned] at hs; have := Option.some.inj hs; exact eq (this.symm)
      exact ⟨s, by simpa [World.reclaim, setAt, ne] using hs⟩
  · exact h.waitOwned

def liveEntry : Option (OwnedJob owners) → Bool
  | none => false
  | some row => row.stored && row.body.outcome.isNone

def World.liveCount (w : World jobs owners slots) : Nat :=
  (List.finRange jobs).countP (fun i => liveEntry (w.entries i))

def World.Invariant (capacity : Nat) (w : World jobs owners slots) : Prop :=
  w.Valid ∧ w.liveCount ≤ capacity

private theorem count_mono (xs : List α) (p q : α → Bool)
    (h : ∀ x, p x = true → q x = true) : xs.countP p ≤ xs.countP q := by
  induction xs with
  | nil => simp
  | cons x xs ih =>
    have hx := h x
    simp only [List.countP_cons]
    cases hp : p x <;> cases hq : q x <;> simp_all <;> omega

private theorem body_count (w : World jobs owners slots) (i : Fin jobs)
    (row : OwnedJob owners) (found : w.entries i = some row)
    (next : Job) (event : Event) (hs : row.body.step event = some next) :
    (w.bodyUpdate i row next).liveCount ≤ w.liveCount := by
  apply count_mono
  intro k live
  by_cases eq : k = i
  · subst k
    simp [World.bodyUpdate, liveEntry, found] at live ⊢
    exact ⟨live.1, by simpa using step_does_not_reopen row.body next event hs (by simp [live.2])⟩
  · simpa [World.bodyUpdate, setAt, eq] using live

private theorem evict_count (w : World jobs owners slots) (i : Fin jobs)
    (row : OwnedJob owners) : (w.evict i row).liveCount ≤ w.liveCount := by
  apply count_mono
  intro k live
  by_cases eq : k = i
  · subst k; simp [World.evict, liveEntry] at live
  · simpa [World.evict, setAt, eq] using live

/-- Operations of the resource/ownership projection. Observations (including
query, rejection and timeout) stutter after their wait reference is released.
Admission previews the new live count before committing; no other operation
increases it. Resource event guards are exactly Job.step's executable guards. -/
inductive World.Step {jobs owners slots : Nat} (capacity : Nat) : World jobs owners slots → World jobs owners slots → Prop where
  | admit (w : World jobs owners slots) (i) (c) (ownedSpec)
      (empty : w.entries i = none) (openOwner : w.connections c = .open)
      (capacityAvailable : (w.admit i c ownedSpec).liveCount ≤ capacity) :
      World.Step capacity w (w.admit i c ownedSpec)
  | body (w : World jobs owners slots) (i) (row) (next) (event)
      (found : w.entries i = some row) (localEvent : event.local = true)
      (accepted : row.body.step event = some next) : World.Step capacity w (w.bodyUpdate i row next)
  | start (w : World jobs owners slots) (i) (row) (next) (slot)
      (found : w.entries i = some row) (free : w.permits slot = none)
      (accepted : row.body.step .start = some next) : World.Step capacity w (w.grant i row next slot)
  | settle (w : World jobs owners slots) (i) (row) (next) (slot)
      (found : w.entries i = some row) (owned : w.permits slot = some i)
      (accepted : row.body.step .settle = some next) : World.Step capacity w (w.reclaim i row next slot)
  | beginClose (w : World jobs owners slots) (c) (isOpen : w.connections c = .open) :
      World.Step capacity w (w.connectionUpdate c .closing)
  | finishClose (w : World jobs owners slots) (c) (isClosing : w.connections c = .closing)
      (drained : ∀ i row, w.entries i = some row → row.owner = c → row.stored = false) :
      World.Step capacity w (w.connectionUpdate c .closed)
  | evict (w : World jobs owners slots) (i) (row) (found : w.entries i = some row)
      (closing : w.connections row.owner = .closing) (terminal : row.body.outcome.isSome = true) :
      World.Step capacity w (w.evict i row)
  | await (w : World jobs owners slots) (c) (i) (row) (isOpen : w.connections c = .open)
      (found : w.entries i = some row) (stored : row.stored = true) :
      World.Step capacity w (w.awaitUpdate c (some i))
  | reply (w : World jobs owners slots) (c) : World.Step capacity w (w.awaitUpdate c none)
  | observe (w : World jobs owners slots) : World.Step capacity w w

theorem world_step_preserves (w next : World jobs owners slots) (capacity : Nat)
    (h : w.Invariant capacity) (step : World.Step capacity w next) : next.Invariant capacity := by
  cases step with
  | admit i c owned empty isOpen room =>
    exact ⟨admit_valid w h.1 i c owned empty isOpen, room⟩
  | body i row next event found localEvent accepted =>
    exact ⟨body_update_valid w h.1 i row found next
        (step_preserves _ _ (h.1.jobValid i row found) event accepted)
        (local_step_keeps_slot _ _ event localEvent accepted),
      Nat.le_trans (body_count w i row found next event accepted) h.2⟩
  | start i row next slot found free accepted =>
    have slots := start_slot _ _ accepted
    refine ⟨grant_valid w h.1 i row found next
      (step_preserves _ _ (h.1.jobValid i row found) .start accepted)
      (by simp [slots.1]) slots.2 slot free, ?_⟩
    exact Nat.le_trans (body_count w i row found next .start accepted) h.2
  | settle i row next slot found owned accepted =>
    refine ⟨reclaim_valid w h.1 i row found next
      (step_preserves _ _ (h.1.jobValid i row found) .settle accepted)
      (by simp [settle_slot _ _ accepted]) slot owned, ?_⟩
    exact Nat.le_trans (body_count w i row found next .settle accepted) h.2
  | beginClose c isOpen =>
    exact ⟨connection_update_valid w h.1 c .closing (by simp), h.2⟩
  | finishClose c isClosing drained =>
    exact ⟨connection_update_valid w h.1 c .closed (fun _ => drained), h.2⟩
  | evict i row found closing terminal =>
    exact ⟨evict_valid w h.1 i row found, Nat.le_trans (evict_count w i row) h.2⟩
  | await c i row isOpen found stored =>
    exact ⟨await_update_valid w h.1 c (some i) (fun _ => isOpen), h.2⟩
  | reply c => exact ⟨await_update_valid w h.1 c none (by simp), h.2⟩
  | observe => exact h

inductive World.Reachable {jobs owners slots : Nat} (capacity : Nat) : World jobs owners slots → Prop where
  | initial : World.Reachable capacity World.initial
  | next : World.Reachable capacity w → World.Step capacity w next → World.Reachable capacity next

theorem world_reachable_invariant (w : World jobs owners slots)
    (h : w.Reachable capacity) : w.Invariant capacity := by
  induction h with
  | initial => exact ⟨world_initial_valid, by simp [World.liveCount, World.initial, liveEntry]⟩
  | next reachable step ih => exact world_step_preserves _ _ _ ih step

private theorem body_outcome (w : World jobs owners slots) (i : Fin jobs)
    (row : OwnedJob owners) (next : Job) (event : Event)
    (found : w.entries i = some row) (accepted : row.body.step event = some next)
    (k : Fin jobs) (prior : OwnedJob owners) (hk : w.entries k = some prior)
    (result : Outcome) (terminal : prior.body.outcome = some result) :
    ∃ later, (w.bodyUpdate i row next).entries k = some later ∧ later.body.outcome = some result := by
  by_cases eq : k = i
  · subst k; rw [found] at hk; cases hk
    exact ⟨{ row with body := next }, by simp [World.bodyUpdate],
      terminal_stable row.body next event result terminal accepted⟩
  · exact ⟨prior, by simpa [World.bodyUpdate, setAt, eq] using hk, terminal⟩

theorem world_terminal_stable (w next : World jobs owners slots)
    (step : World.Step capacity w next) (k : Fin jobs) (prior : OwnedJob owners)
    (hk : w.entries k = some prior) (result : Outcome) (terminal : prior.body.outcome = some result) :
    ∃ later, next.entries k = some later ∧ later.body.outcome = some result := by
  cases step with
  | admit i c owned empty isOpen room =>
    have ne : k ≠ i := by intro eq; subst k; simp [empty] at hk
    exact ⟨prior, by simpa [World.admit, setAt, ne] using hk, terminal⟩
  | body i row next event found localEvent accepted =>
    exact body_outcome w i row next event found accepted k prior hk result terminal
  | start i row next slot found free accepted =>
    exact body_outcome w i row next .start found accepted k prior hk result terminal
  | settle i row next slot found owned accepted =>
    exact body_outcome w i row next .settle found accepted k prior hk result terminal
  | beginClose c isOpen => exact ⟨prior, hk, terminal⟩
  | finishClose c isClosing drained => exact ⟨prior, hk, terminal⟩
  | evict i row found closing isTerminal =>
    by_cases eq : k = i
    · subst k; rw [found] at hk; cases hk
      exact ⟨{ prior with stored := false }, by simp [World.evict], terminal⟩
    · exact ⟨prior, by simpa [World.evict, setAt, eq] using hk, terminal⟩
  | await c i row isOpen found stored => exact ⟨prior, hk, terminal⟩
  | reply c => exact ⟨prior, hk, terminal⟩
  | observe => exact ⟨prior, hk, terminal⟩

/-- Closed owners have no job metadata, independently of task settlement. -/
theorem closed_owner_has_no_entries (w : World jobs owners slots) (h : w.Valid)
    (c : Fin owners) (closed : w.connections c = .closed)
    (i : Fin jobs) (row : OwnedJob owners) (found : w.entries i = some row)
    (owned : row.owner = c) : row.stored = false := by
  cases hs : row.stored with
  | false => rfl
  | true => have := h.storedOwner i row found hs; simp_all

/-- Physical slot ownership is injective: each active job has a distinct permit
in Fin slots, hence concurrency cannot exceed the configured slot domain. -/
theorem slots_do_not_alias (w : World jobs owners slots) (_h : w.Valid)
    (slot : Fin slots) (a b : Fin jobs)
    (ha : w.permits slot = some a) (hb : w.permits slot = some b) : a = b := by
  rw [ha] at hb; exact Option.some.inj hb

def World.ActiveJob (w : World jobs owners slots) :=
  { i : Fin jobs // ∃ row, w.entries i = some row ∧ row.body.slot = .held }

private theorem active_has_permit (w : World jobs owners slots) (h : w.Valid)
    (i : w.ActiveJob) : ∃ slot, w.permits slot = some i.val := by
  obtain ⟨row, found, held⟩ := i.property
  exact h.activeCovered i.val row found held

private noncomputable def activePermit (w : World jobs owners slots) (h : w.Valid)
    (i : w.ActiveJob) : Fin slots := Classical.choose (active_has_permit w h i)

private theorem activePermit_spec (w : World jobs owners slots) (h : w.Valid)
    (i : w.ActiveJob) : w.permits (activePermit w h i) = some i.val :=
  Classical.choose_spec (active_has_permit w h i)

/-- Any distinct collection of active jobs fits into the physical slot domain. -/
theorem active_jobs_bounded (w : World jobs owners slots) (h : w.Valid)
    (active : List w.ActiveJob) (distinct : active.Nodup) : active.length ≤ slots := by
  have injective : ∀ a b, activePermit w h a = activePermit w h b → a = b := by
    intro a b eq
    have ha := activePermit_spec w h a
    have hb := activePermit_spec w h b
    rw [eq] at ha
    rw [ha] at hb
    exact Subtype.ext (Option.some.inj hb)
  have mapped : (active.map (activePermit w h)).Nodup :=
    List.pairwise_map.mpr (List.Pairwise.imp (fun neq eq => neq (injective _ _ eq)) distinct)
  have bound := mapped.length_le_of_subset (fun i _ => List.mem_finRange i)
  simpa using bound

def World.Quiescent (w : World jobs owners slots) : Prop :=
  (∀ c, w.connections c = .closed) ∧
  (∀ i row, w.entries i = some row → row.body.stage = .settled)

def World.NoLeaks (w : World jobs owners slots) : Prop :=
  (∀ slot, w.permits slot = none) ∧
  (∀ c, w.waiting c = none) ∧
  (∀ i row, w.entries i = some row → row.stored = false ∧
    row.body.slot.live = 0 ∧ ∀ resource, (row.body.resources resource).live = 0)

/-- No finite population or history bound appears in this theorem. -/
theorem quiescent_no_leaks (w : World jobs owners slots) (h : w.Valid)
    (q : w.Quiescent) : w.NoLeaks := by
  constructor
  · intro slot
    cases found : w.permits slot with
    | none => rfl
    | some i =>
      obtain ⟨row, hr, held⟩ := h.permitValid slot i found
      have active := (h.jobValid i row hr).slotActive.mp held
      have settled := q.2 i row hr
      simp_all
  constructor
  · intro c
    cases found : w.waiting c with
    | none => rfl
    | some i => have := h.waitOwned c i found; have := q.1 c; simp_all
  · intro i row found
    obtain ⟨slot, resources⟩ := settled_no_leaks row.body (h.jobValid i row found) (q.2 i row found)
    constructor
    · exact closed_owner_has_no_entries w h row.owner (q.1 row.owner) i row found rfl
    constructor
    · cases hs : row.body.slot <;> simp_all [Lease.live]
    · intro resource
      have hr := resources resource
      cases hs : row.body.resources resource <;> simp_all [Lease.live]

theorem reachable_world_quiescence_leak_free (w : World jobs owners slots)
    (reachable : w.Reachable capacity) (quiescent : w.Quiescent) : w.NoLeaks :=
  quiescent_no_leaks w (world_reachable_invariant w reachable).1 quiescent

theorem quiescent_accounting_balanced (w : World jobs owners slots)
    (reachable : w.Reachable capacity) (quiescent : w.Quiescent)
    (i : Fin jobs) (row : OwnedJob owners) (found : w.entries i = some row) (r : ResourceKind) :
    row.body.acquisitions r = row.body.releases r := by
  have free := (reachable_world_quiescence_leak_free w reachable quiescent).2.2 i row found
  have accounting := job_resource_accounting row.body r
  rw [free.2.2 r] at accounting
  simpa using accounting.symm

theorem reachable_live_capacity (w : World jobs owners slots) (h : w.Reachable capacity) :
    w.liveCount ≤ capacity := (world_reachable_invariant w h).2

/-- A certificate API for consumers of the global model. Its history evidence
is a Prop and is erased; the effectful shell is not claimed to refine this API. -/
structure World.Checked (jobs owners slots capacity : Nat) where
  value : World jobs owners slots
  reachable : value.Reachable capacity

def World.Checked.initial : World.Checked jobs owners slots capacity :=
  ⟨World.initial, .initial⟩

def World.Checked.advance (w : World.Checked jobs owners slots capacity)
    (next : World jobs owners slots) (step : World.Step capacity w.value next) :
    World.Checked jobs owners slots capacity := ⟨next, .next w.reachable step⟩

end Core.AsyncResources
