import Core.Value

/-!
# ITF traces and the trace pipeline (§6.2)

Ports `Apalache.Types.ItfTrace`/`TraceState`, `applyParamVars`
(`Apalache.Types`) and `traceSteps` (`Engine.Core`).

Design notes (design doc §5.1):

- Every Haskell `Map Text Value` is the assoc-list `ValueMap` with
  lookup semantics (`List.lookup`, first binding wins); `union` is
  list append, matching `Data.Map.union`'s left bias.
- All partiality is explicit: nothing here is partial, and the
  losslessness of `applyParamVars` (§6.2) is *conditional* on the
  parse-time key invariant `ResplitKeyInv`, mirroring the Haskell
  code, which silently drops keys that are neither parameter nor state
  variables.

## §6.2 theorem index

- `resplit_lookup_union`: pointwise union invariance (lossless
  repartition) under `ResplitKeyInv`.
- `resplit_exactly_one`: every key of the union lands on exactly one
  side of the repartition.
- `resplit_disjoint`: the two sides are unconditionally disjoint.
- `traceSteps_length`, `traceStepsAux_nth`: `traceSteps` preserves
  length and order, `Step.idx` is the state index.
- `stepOf_vars_actionTaken`, `traceSteps_act`: the injected
  `action_taken` binding equals the step's action name.
-/

/-! ## Map helpers -/

/-- Left-biased union (matches `Data.Map.union` under lookup
semantics: a key bound in `m` keeps `m`'s value). -/
def ValueMap.union (m n : ValueMap) : ValueMap := m ++ n

/-- The reserved key under which the action name rides in ITF states. -/
def actionTakenKey : String := "action_taken"

/-- Key-filter on a map. -/
def ValueMap.filterKeys (p : String → Bool) (m : ValueMap) : ValueMap :=
  m.filter (fun kv => p kv.1)

theorem ValueMap.lookup_filterKeys {p : String → Bool} (m : ValueMap) (k : String) :
    ValueMap.lookup k (m.filterKeys p) = if p k then ValueMap.lookup k m else none := by
  induction m with
  | nil => simp [filterKeys, ValueMap.lookup]
  | cons kv m ih =>
    obtain ⟨k', v'⟩ := kv
    simp only [filterKeys, ValueMap.lookup, List.filter_cons] at ih ⊢
    by_cases hp : p k'
    · have hkeep : (fun kv : String × Value => p kv.1) (k', v') = true := by
        simp [hp]
      rw [if_pos hkeep]
      by_cases hb : k == k'
      · simp only [List.lookup_cons, hb,
          show p k = true from by rw [beq_iff_eq.mp hb]; exact hp]
        simp
      · have hne : k ≠ k' := by
          intro he; apply hb; rw [he]; simp
        simp only [List.lookup_cons, beq_eq_false_iff_ne.mpr hne]
        by_cases hq : p k = true
        · first | rfl | rw [ih, if_pos hq]
        · first | rfl | rw [ih, if_neg hq]
    · have hdrop : ¬((fun kv : String × Value => p kv.1) (k', v')) := by
        simp [hp]
      rw [if_neg hdrop, List.lookup_cons]
      by_cases hb : k == k'
      · have hnpk : ¬(p k = true) := by rw [beq_iff_eq.mp hb]; exact hp
        simp only [hb]
        rw [ih, if_neg hnpk, if_neg hnpk]
      · have hne : k ≠ k' := by
          intro he; apply hb; rw [he]; simp
        simp only [List.lookup_cons, beq_eq_false_iff_ne.mpr hne]
        first | rfl | simp_all [ih]

/-- `List.lookup`-level restatement of `lookup_filterKeys`, for use
after `ValueMap.lookup` has been unfolded. -/
theorem lookup_filterKeys' {p : String → Bool} (m : ValueMap) (k : String) :
    List.lookup k (m.filterKeys p) = if p k then List.lookup k m else none :=
  ValueMap.lookup_filterKeys m k

/-! ## Trace structures (ports of `Apalache.Types`) -/

/-- Port of `Apalache.Types.TraceState`. -/
structure TraceState where
  /-- `actionTake`: the name of the transition that produced this state. -/
  actionTaken : String
  /-- Bindings of the parameter variables. -/
  parameters : ValueMap
  /-- Bindings of the state variables. -/
  stateVars : ValueMap
  deriving Repr

instance : Inhabited TraceState := ⟨⟨"", [], []⟩⟩

/-- Port of `Apalache.Types.ItfTrace`. -/
structure ItfTrace where
  /-- `traceVars`: the state-variable names. -/
  traceVars : List String
  /-- `paramVars`: the parameter-variable names. -/
  paramVars : List String
  /-- `traceParams`: the trace-level constants. -/
  traceParams : ValueMap
  /-- `traceStates`: the states, in order. -/
  traceStates : List TraceState
  deriving Repr

instance : Inhabited ItfTrace := ⟨⟨[], [], [], []⟩⟩

/-! ## `applyParamVars` (§6.2) -/

/-- Parameter side of the repartition: keys listed in `pvs`. -/
def paramKeyPred (pvs : List String) (k : String) : Bool :=
  List.elem k pvs

/-- State side of the repartition: keys that are not `action_taken`,
not in `pvs`, and listed in `vars`. -/
def stateKeyPred (pvs vars : List String) (k : String) : Bool :=
  (!paramKeyPred pvs k) && !(k == actionTakenKey) && List.elem k vars

theorem stateKeyPred_false_of_param {pvs vars : List String} {k : String}
    (h : List.elem k pvs = true) : stateKeyPred pvs vars k = false := by
  have h' : paramKeyPred pvs k = true := h
  simp [stateKeyPred, h', Bool.not_true, Bool.false_and]

/-- Port of the `resplit` helper of `Apalache.Types.applyParamVars`:
repartition the union of the two maps into parameters (keys in `pvs`)
and state variables (keys that are not `action_taken`, not in `pvs`,
and listed in `vars`). -/
def resplit (pvs vars : List String) (s : TraceState) : TraceState where
  actionTaken := s.actionTaken
  parameters := (ValueMap.union s.parameters s.stateVars).filterKeys
    (paramKeyPred pvs)
  stateVars := (ValueMap.union s.parameters s.stateVars).filterKeys
    (stateKeyPred pvs vars)

/-- Port of `Apalache.Types.applyParamVars`. -/
def applyParamVars (pvs : List String) (t : ItfTrace) : ItfTrace where
  traceVars := t.traceVars
  paramVars := pvs ++ t.paramVars
  traceParams := t.traceParams
  traceStates := t.traceStates.map (resplit pvs t.traceVars)

/-- Parse-time key invariant under which the repartition is lossless:
every key of the union is either a parameter variable or a proper state
variable.  It is exactly the invariant established by the `FromJSON`
split in the Haskell source (parameters come from `param_vars`,
state variables from `vars` minus `action_taken`). -/
def ResplitKeyInv (s : TraceState) (pvs vars : List String) : Prop :=
  ∀ k v, ValueMap.lookup k (ValueMap.union s.parameters s.stateVars) = some v →
    List.elem k pvs = true ∨
      (k ≠ actionTakenKey ∧ List.elem k pvs = false ∧ List.elem k vars = true)

/-- **§6.2 (lossless repartition).** Under the parse-time key
invariant, `resplit` preserves the union of the two maps pointwise. -/
theorem resplit_lookup_union (pvs vars : List String) (s : TraceState)
    (h : ResplitKeyInv s pvs vars) (k : String) :
    ValueMap.lookup k (ValueMap.union (resplit pvs vars s).parameters
        (resplit pvs vars s).stateVars)
      = ValueMap.lookup k (ValueMap.union s.parameters s.stateVars) := by
  simp only [resplit, ValueMap.union, ValueMap.lookup]
  rw [List.lookup_append, lookup_filterKeys', lookup_filterKeys']
  by_cases hp : List.elem k pvs = true
  · rw [if_pos (show paramKeyPred pvs k = true from hp),
      if_neg (fun hcon => Bool.noConfusion (hcon.symm.trans (stateKeyPred_false_of_param hp)))]
    exact Option.or_none
  · have hpf : List.elem k pvs = false := by
      cases h' : List.elem k pvs <;> simp_all
    rw [if_neg (fun hcon => Bool.noConfusion (hcon.symm.trans (show paramKeyPred pvs k = false from hpf)))]
    by_cases hq : stateKeyPred pvs vars k = true
    · rw [if_pos hq]
      exact Option.none_or
    · rw [if_neg hq]
      -- Neither side keeps k: by the invariant the original union does
      -- not bind k either.
      cases hlu : List.lookup k (s.parameters ++ s.stateVars) with
      | none => simp
      | some v =>
        have hlu' : ValueMap.lookup k (ValueMap.union s.parameters s.stateVars)
            = some v := hlu
        rcases h k v hlu' with hpv | ⟨hne, hpv, hvar⟩
        · exact absurd hpv hp
        · exfalso; apply hq
          simp only [stateKeyPred, paramKeyPred, Bool.and_eq_true,
            Bool.and_eq_true]
          exact ⟨⟨by rw [hpv]; exact Bool.not_false, by simp [hne]⟩, hvar⟩

/-- The two sides of a `resplit` are unconditionally disjoint (no key
is bound on both sides). -/
theorem resplit_disjoint (pvs vars : List String) (s : TraceState) (k : String)
    (v w : Value)
    (h₁ : ValueMap.lookup k (resplit pvs vars s).parameters = some v)
    (h₂ : ValueMap.lookup k (resplit pvs vars s).stateVars = some w) :
    False := by
  simp only [resplit] at h₁ h₂
  rw [ValueMap.lookup_filterKeys] at h₁ h₂
  split at h₂
  · next hq =>
    simp only [stateKeyPred] at hq
    rw [Bool.and_eq_true, Bool.and_eq_true] at hq
    obtain ⟨⟨hq1, _⟩, _⟩ := hq
    have hpf : paramKeyPred pvs k = false := by simpa using hq1
    split at h₁
    · next hp => exact absurd hp (fun hcon => Bool.noConfusion (hcon.symm.trans hpf))
    · simp at h₁
  · simp at h₂

/-- **§6.2 (exactly one side).** Under the parse-time key invariant,
every key bound in the union is bound on exactly one side of the
repartition (with its original value). -/
theorem resplit_exactly_one (pvs vars : List String) (s : TraceState)
    (h : ResplitKeyInv s pvs vars) (k : String) (v : Value)
    (hv : ValueMap.lookup k (ValueMap.union s.parameters s.stateVars)
      = some v) :
    (ValueMap.lookup k (resplit pvs vars s).parameters = some v ∧
      ValueMap.lookup k (resplit pvs vars s).stateVars = none)
    ∨ (ValueMap.lookup k (resplit pvs vars s).parameters = none ∧
      ValueMap.lookup k (resplit pvs vars s).stateVars = some v) := by
  have hlu : ValueMap.lookup k
      (ValueMap.union (resplit pvs vars s).parameters
        (resplit pvs vars s).stateVars) = some v := by
    rw [resplit_lookup_union pvs vars s h k]; exact hv
  have hor : (ValueMap.lookup k (resplit pvs vars s).parameters).or
      (ValueMap.lookup k (resplit pvs vars s).stateVars) = some v := by
    simpa [ValueMap.union, ValueMap.lookup, List.lookup_append] using hlu
  cases hP : ValueMap.lookup k (resplit pvs vars s).parameters with
  | none =>
    rw [hP] at hor
    cases hQ : ValueMap.lookup k (resplit pvs vars s).stateVars with
    | none => rw [hQ] at hor; simp at hor
    | some w =>
      rw [hQ] at hor
      simp only [Option.none_or, Option.some.injEq] at hor
      exact Or.inr ⟨rfl, by rw [hor]⟩
  | some v' =>
    rw [hP] at hor
    cases hQ : ValueMap.lookup k (resplit pvs vars s).stateVars with
    | none =>
      rw [hQ] at hor
      simp only [Option.or_none, Option.some.injEq] at hor
      exact Or.inl ⟨by rw [hor], rfl⟩
    | some w => exact absurd (resplit_disjoint pvs vars s k v' w hP hQ) (by simp)

/-- **§6.2 (ItfTrace level).** `applyParamVars` repartitions every
state losslessly. -/
theorem applyParamVars_lookup_union (pvs : List String) (t : ItfTrace)
    (h : ∀ s ∈ t.traceStates, ResplitKeyInv s pvs t.traceVars)
    (s : TraceState) (hs : s ∈ t.traceStates) (k : String) :
    ValueMap.lookup k
        (ValueMap.union (resplit pvs t.traceVars s).parameters
          (resplit pvs t.traceVars s).stateVars)
      = ValueMap.lookup k (ValueMap.union s.parameters s.stateVars) :=
  resplit_lookup_union pvs t.traceVars s (h s hs) k

/-! ## `traceSteps` (§6.2, port of `Engine.Core.traceSteps`) -/

/-- Port of `Engine.Types.Step`. -/
structure Step where
  /-- `stepIdx`: the 0-based state index. -/
  idx : Nat
  /-- `stepAct`: the action name. -/
  act : String
  /-- `stepParams`: the parameter bindings. -/
  params : ValueMap
  /-- `stepVars`: the state bindings plus the injected
  `action_taken` key. -/
  vars : ValueMap
  deriving Repr

instance : Inhabited Step := ⟨⟨0, "", [], []⟩⟩

/-- Port of the `toStep` helper of `Engine.Core.traceSteps`. -/
def stepOf (i : Nat) (s : TraceState) : Step where
  idx := i
  act := s.actionTaken
  params := s.parameters
  vars := ValueMap.insert actionTakenKey (.vstr s.actionTaken) s.stateVars

/-- The $n$-th step carries the $n$-th action name. -/
def traceStepsAux : Nat → List TraceState → List Step
  | _, [] => []
  | i, s :: ss => stepOf i s :: traceStepsAux (i + 1) ss

/-- Port of `Engine.Core.traceSteps`. -/
def traceSteps (t : ItfTrace) : List Step :=
  traceStepsAux 0 t.traceStates

/-- **§6.2 (length and order).** `traceSteps` preserves length. -/
theorem traceStepsAux_length : ∀ (i : Nat) (ss : List TraceState),
    (traceStepsAux i ss).length = ss.length
  | _, [] => rfl
  | i, s :: ss => by
      simp only [traceStepsAux, List.length_cons]
      exact congrArg (· + 1) (traceStepsAux_length (i + 1) ss)

theorem traceSteps_length (t : ItfTrace) :
    (traceSteps t).length = t.traceStates.length :=
  traceStepsAux_length 0 t.traceStates

/-- **§6.2 (order).** The $j$-th `Step` comes from the $j$-th
`TraceState` and carries index $j`. -/
theorem traceStepsAux_nth : ∀ (i j : Nat) (ss : List TraceState),
    (traceStepsAux i ss)[j]? = (ss[j]?.map (fun s => stepOf (i + j) s))
  | i, j, [] => by simp [traceStepsAux]
  | i, j, s :: ss => by
      cases j with
      | zero => simp [traceStepsAux, Nat.zero_add]
      | succ j' =>
        simp only [traceStepsAux, List.getElem?_cons_succ]
        rw [traceStepsAux_nth (i + 1) j' ss]
        simp only [show i + 1 + j' = i + (j' + 1) from by omega]

theorem traceSteps_nth (t : ItfTrace) (j : Nat) :
    (traceSteps t)[j]? = (t.traceStates[j]?.map (fun s => stepOf j s)) := by
  rw [show traceSteps t = traceStepsAux 0 t.traceStates from rfl,
    traceStepsAux_nth 0 j t.traceStates]
  simp only [Nat.zero_add]

/-- **§6.2 (action injection).** The injected `action_taken` binding
equals the state's action name. -/
theorem stepOf_vars_actionTaken (i : Nat) (s : TraceState) :
    ValueMap.lookup actionTakenKey (stepOf i s).vars
      = some (.vstr s.actionTaken) :=
  ValueMap.lookup_insert actionTakenKey (.vstr s.actionTaken) s.stateVars

theorem stepOf_params (i : Nat) (s : TraceState) :
    (stepOf i s).params = s.parameters := rfl

theorem stepOf_act (i : Nat) (s : TraceState) :
    (stepOf i s).act = s.actionTaken := rfl

/-- Combined statement of §6.2 for `traceSteps`: the $j$-th step has
index $j$, carries the $j$-th state's action name and parameters,
and its `action_taken` binding equals the action name. -/
theorem traceSteps_nth_act (t : ItfTrace) (j : Nat)
    (h : t.traceStates[j]? = some s) :
    ∃ st : Step, (traceSteps t)[j]? = some st ∧ st.idx = j ∧
      st.act = s.actionTaken ∧ st.params = s.parameters ∧
      ValueMap.lookup actionTakenKey st.vars = some (.vstr s.actionTaken) := by
  rw [traceSteps_nth t j, h]
  exact ⟨stepOf j s, rfl, rfl, stepOf_act j s, stepOf_params j s,
    stepOf_vars_actionTaken j s⟩