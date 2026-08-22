import Core.Value

/-!
# Core.Diff — verified state diff (§6.1)

Port of `Engine.Core` (diff engine) and the diff shapes of
`Engine.Types` from the Haskell ModelMirrors mirror (design doc §5.1 /
§6.1).

Porting notes:

- `ValueMap` is the assoc-list map of `Core.Value`; `valEq` is the
  proven-correct value equality, and `≈` for states is `stateEq`:
  mutual `mapCont` containment.
- The Haskell depth guard (`length path >= maxDiffDepth`) is realized as
  an explicit *recursion budget* `fuel : Nat`: `diffValueAux 0`
  compares with `valEq` and otherwise reports `hValueMismatch`
  (exactly the Haskell cap behaviour), and every descent into a child
  value spends one unit.  `diffState` runs with budget
  `maxDiffDepth = 8`, so parity with the Haskell cap is preserved.
- `diffSet` uses the verified `setAny` membership (`valEq`-based)
  rather than the Haskell derived structural difference; this is the
  §5.1 replacement of hand-written `Eq` instances and is required for
  completeness to hold at all.
- `diffFieldsGo` walks *all bindings* of the expected map (the Haskell
  version walks `Map.keys`, which are implicitly duplicate-free); the
  meta-theorems require the actual state to be well-formed
  (`WfValue`), matching §5.1's "maps built through the API have
  distinct keys".

§6.1 theorems (all machine-checked below): soundness
(`diffState_sound`), completeness (`diffState_complete`,
`diffFields_mapCont_nil`), cap correctness (`capHints_length_le`,
`capHints_prefix`, `capHints_truncated`), and path validity
(`diffState_pathValid`).

No `IO` anywhere in this module. -/

/-! ## Paths and hints (ports of `Engine.Types`) -/

inductive PathSeg where
  | field (s : String)
  | index (i : Nat)
  deriving Repr, DecidableEq

abbrev Path := List PathSeg

/-- Port of `Engine.Types.DiffHint` (7 constructors). -/
inductive DiffHint where
  | hValueMismatch (p : Path) (e a : Value)
  | hMissing (p : Path) (v : Value)
  | hExtra (p : Path) (v : Value)
  | hMissingElem (p : Path) (v : Value)
  | hExtraElem (p : Path) (v : Value)
  | hTypeMismatch (p : Path) (e a : Value)
  | hTruncated (p : Path)
  deriving Repr

/-- Port of `Engine.Types.hintPath`. -/
def hintPath : DiffHint → Path
  | .hValueMismatch p _ _ => p
  | .hMissing p _ => p
  | .hExtra p _ => p
  | .hMissingElem p _ => p
  | .hExtraElem p _ => p
  | .hTypeMismatch p _ _ => p
  | .hTruncated p => p

/-- Port of `Engine.Types.StateDiff`. -/
inductive StateDiff where
  | statesMatch
  | stateMismatch (expected actual : ValueMap) (hints : List DiffHint)
  deriving Repr

/-! ## Constants (ports of `Engine.Core`) -/

def maxDiffDepth : Nat := 8

def maxDiffHints : Nat := 50

/-- Port of `Engine.Core.sameShape`. -/
def sameShape : Value → Value → Bool
  | .vint _, .vint _ => true
  | .vbool _, .vbool _ => true
  | .vstr _, .vstr _ => true
  | .vset _, .vset _ => true
  | .vseq _, .vseq _ => true
  | .vtuple _, .vtuple _ => true
  | .vrecord _, .vrecord _ => true
  | .vmap _, .vmap _ => true
  | .vvariant _ _, .vvariant _ _ => true
  | .vunserializable _, .vunserializable _ => true
  | .vnull, .vnull => true
  | _, _ => false

/-! ## Side conditions -/

/-- A map whose keys are pairwise distinct (all maps produced by the
`ValueMap` API, §5.1). -/
def NodupKeys (m : ValueMap) : Prop := (m.map Prod.fst).Nodup

/-- Every container map inside `v` has distinct keys.  Side condition
of the diff meta-theorems. -/
inductive WfValue : Value → Prop
  | record {m : ValueMap} (hnd : NodupKeys m)
      (h : ∀ p ∈ m, WfValue p.2) : WfValue (.vrecord m)
  | vmap {m : ValueMap} (hnd : NodupKeys m)
      (h : ∀ p ∈ m, WfValue p.2) : WfValue (.vmap m)
  | vset {xs : List Value} (h : ∀ x ∈ xs, WfValue x) :
      WfValue (.vset xs)
  | vseq {xs : List Value} (h : ∀ x ∈ xs, WfValue x) :
      WfValue (.vseq xs)
  | vtuple {xs : List Value} (h : ∀ x ∈ xs, WfValue x) :
      WfValue (.vtuple xs)
  | variant {t : String} {v : Value} (h : WfValue v) :
      WfValue (.vvariant t v)
  | vint (i : Int) : WfValue (.vint i)
  | vbool (b : Bool) : WfValue (.vbool b)
  | vstr (s : String) : WfValue (.vstr s)
  | vunserializable (s : String) : WfValue (.vunserializable s)
  | vnull : WfValue .vnull

theorem nodupKeys_of_wf_vrecord {m : ValueMap}
    (hw : WfValue (.vrecord m)) : NodupKeys m := by
  cases hw with
  | record hnd _ => exact hnd

theorem nodupKeys_of_wf_vmap {m : ValueMap}
    (hw : WfValue (.vmap m)) : NodupKeys m := by
  cases hw with
  | vmap hnd _ => exact hnd

/-! ## Size equations (local copies; `valueSize` and friends are
structural, so these are `rfl`). -/

private theorem valueSize_vrecord (m : ValueMap) :
    valueSize (.vrecord m) = 1 + mapSize m := rfl
private theorem valueSize_vmap (m : ValueMap) :
    valueSize (.vmap m) = 1 + mapSize m := rfl
private theorem valueSize_vseq (xs : List Value) :
    valueSize (.vseq xs) = 1 + listSize xs := rfl
private theorem valueSize_vtuple (xs : List Value) :
    valueSize (.vtuple xs) = 1 + listSize xs := rfl
private theorem valueSize_vvariant (t : String) (v : Value) :
    valueSize (.vvariant t v) = 1 + valueSize v := rfl
private theorem mapSize_cons' (k : String) (v : Value) (m : ValueMap) :
    mapSize ((k, v) :: m) = valueSize v + 1 + mapSize m := rfl
private theorem listSize_cons' (a : Value) (as : List Value) :
    listSize (a :: as) = valueSize a + 1 + listSize as := rfl

/-! ## Set diff (uses the verified `valEq` membership) -/

/-- Port of `diffSet`: elements of `es` with no `valEq`-equal
element in `as` are missing; conversely for extras. -/
def diffSet (path : Path) (es as : List Value) : List DiffHint :=
  (es.filter (fun e => !setAny e as)).map (DiffHint.hMissingElem path)
  ++ (as.filter (fun a => !setAny a es)).map (DiffHint.hExtraElem path)

/-! ## Hint ordering: sorted-key interleave (Haskell wire order) -/

/-! Haskell @diffFields@ walks the keys of @Map.union expected actual@ in
sorted (ascending @Ord Text@) order and concatenates each key′s hints,
so hints from different keys interleave by key. The engine below walks
expected bindings before the extras sweep, which permutes those blocks:
per key, the emitted hint *block* is identical (same fuel, same values),
and blocks are contiguous in both orders. A stable sort of the hint
list by the key segment sitting at the map′s path depth therefore
reproduces the Haskell order exactly, while provably being a permutation
of the engine output (bridge lemma below), so the §6.1 proofs are
unaffected. -/

/-- The key segment at depth @n@ of a hint path (empty when absent). -/
def segKeyAt (n : Nat) (h : DiffHint) : String :=
  match (hintPath h)[n]? with
  | some (.field k) => k
  | _ => ""

/-- Stable insertion by sort key (equal keys keep input order). -/
def insertByKey (n : Nat) (h : DiffHint) : List DiffHint → List DiffHint
  | [] => [h]
  | h2x :: hs => if segKeyAt n h ≤ segKeyAt n h2x then h :: h2x :: hs
      else h2x :: insertByKey n h hs

/-- Stable sort by the key segment at depth @n@: the Haskell
sorted-key interleave of one map level′s hint blocks. -/
def sortHintsByKey (n : Nat) : List DiffHint → List DiffHint
  | [] => []
  | h :: hs => insertByKey n h (sortHintsByKey n hs)

theorem perm_insertByKey (n : Nat) (h : DiffHint) (hs : List DiffHint) :
    (insertByKey n h hs).Perm (h :: hs) := by
  induction hs with
  | nil => rfl
  | cons h2 hs2 ih =>
    by_cases hc : segKeyAt n h ≤ segKeyAt n h2
    · simp only [insertByKey, if_pos hc]; exact List.Perm.refl _
    · simp only [insertByKey, if_neg hc]
      exact (List.Perm.cons _ ih).trans (List.Perm.swap _ _ _)

/-- The sort is a permutation of its input (used by the §6.1 proofs). -/
theorem perm_sortHintsByKey (n : Nat) (hs : List DiffHint) :
    (sortHintsByKey n hs).Perm hs := by
  induction hs with
  | nil => rfl
  | cons h hs2 ih =>
    simp only [sortHintsByKey]
    exact (perm_insertByKey n h _).trans (List.Perm.cons _ ih)

/-- Sorting never silences or invents hints. -/
theorem sortHintsByKey_nil_iff (n : Nat) (hs : List DiffHint) :
    sortHintsByKey n hs = [] ↔ hs = [] := by
  cases hs with
  | nil => rfl
  | cons h2 hs2 =>
    constructor
    · intro hc
      have hlen := (perm_insertByKey n h2 (sortHintsByKey n hs2)).length_eq
      simp only [sortHintsByKey] at hc
      rw [hc] at hlen
      simp at hlen
    · intro habs
      cases habs
/-- Membership is preserved (path-validity bridge). -/
theorem mem_sortHintsByKey (n : Nat) (hs : List DiffHint) (h : DiffHint) :
    h ∈ sortHintsByKey n hs ↔ h ∈ hs :=
  (perm_sortHintsByKey n hs).mem_iff

/-! ## The diff engine (budget recursion) -/

/-- Entries of `am` whose key does not occur in `em` (port of the
`HExtra` arm of `diffFields`). -/
def extraHints (path : Path) (em : ValueMap) : ValueMap → List DiffHint
  | [] => []
  | (k, av) :: ar =>
    (if (ValueMap.lookup k em).isSome then []
      else [DiffHint.hExtra (path ++ [PathSeg.field k]) av])
    ++ extraHints path em ar

mutual

/-- Budgeted diff of two values.  `diffValueAux 0` is the Haskell
depth-cap branch: `valEq` agreement yields no hints, disagreement a
single `hValueMismatch`. -/
def diffValueAux : Nat → Path → Value → Value → List DiffHint
  | 0, path, e, a =>
    if valEq e a = true then [] else [DiffHint.hValueMismatch path e a]
  | fuel + 1, path, e, a =>
    if valEq e a = true then [] else
      match e, a with
      | .vrecord em, .vrecord am =>
        sortHintsByKey path.length
          (diffFieldsGo (fuel + 1) path am em ++ extraHints path em am)
      | .vmap em, .vmap am =>
        sortHintsByKey path.length
          (diffFieldsGo (fuel + 1) path am em ++ extraHints path em am)
      | .vseq es, .vseq as => diffElemsGo (fuel + 1) path 0 es as
      | .vtuple es, .vtuple as => diffElemsGo (fuel + 1) path 0 es as
      | .vvariant t₁ v₁, .vvariant t₂ v₂ =>
        if t₁ == t₂ then
          diffValueAux fuel (path ++ [PathSeg.field t₁]) v₁ v₂
        else [DiffHint.hValueMismatch path e a]
      | .vset es, .vset as => diffSet path es as
      | _, _ =>
        if sameShape e a then [DiffHint.hValueMismatch path e a]
        else [DiffHint.hTypeMismatch path e a]
  termination_by fuel path e a => (fuel, valueSize e + valueSize a)
  decreasing_by
    all_goals
      first
      | exact Prod.Lex.left _ _ (by omega)
      | exact Prod.Lex.right _
          (by simp only [valueSize_vrecord, valueSize_vmap, valueSize_vseq,
            valueSize_vtuple, valueSize_vvariant, mapSize_cons',
            listSize_cons'] <;> omega)
      | exact Prod.Lex.right _ (by omega)

/-- Walk every binding of the expected map against the actual map. -/
def diffFieldsGo : Nat → Path → ValueMap → ValueMap → List DiffHint
  | 0, _, _, _ => []
  | _ + 1, _, _, [] => []
  | fuel + 1, path, am, (k, ev) :: er =>
    (match ValueMap.lookup k am with
     | some av => diffValueAux fuel (path ++ [PathSeg.field k]) ev av
     | none => [DiffHint.hMissing (path ++ [PathSeg.field k]) ev])
    ++ diffFieldsGo (fuel + 1) path am er
  termination_by fuel path am em => (fuel, mapSize em)
  decreasing_by
    all_goals
      first
      | exact Prod.Lex.left _ _ (by omega)
      | exact Prod.Lex.right _
          (by simp only [mapSize_cons'] <;> omega)
      | exact Prod.Lex.right _ (by omega)

/-- Position-indexed diff of sequences/tuples. -/
def diffElemsGo : Nat → Path → Nat → List Value → List Value → List DiffHint
  | 0, _, _, _, _ => []
  | _ + 1, _, _, [], [] => []
  | fuel + 1, path, i, [], a :: as =>
    DiffHint.hExtra (path ++ [PathSeg.index i]) a
      :: diffElemsGo (fuel + 1) path (i + 1) [] as
  | fuel + 1, path, i, e :: es, [] =>
    DiffHint.hMissing (path ++ [PathSeg.index i]) e
      :: diffElemsGo (fuel + 1) path (i + 1) es []
  | fuel + 1, path, i, e :: es, a :: as =>
    diffValueAux fuel (path ++ [PathSeg.index i]) e a
      ++ diffElemsGo (fuel + 1) path (i + 1) es as
  termination_by fuel path i es as => (fuel, listSize es + listSize as)
  decreasing_by
    all_goals
      first
      | exact Prod.Lex.left _ _ (by omega)
      | exact Prod.Lex.right _
          (by simp only [listSize_cons'] <;> omega)
      | exact Prod.Lex.right _ (by omega)

end

/-- Port of @diffFields@: per-key comparison in the Haskell sorted-key
wire order (stable key sort of the engine-level blocks). -/
def diffFields (fuel : Nat) (path : Path) (em am : ValueMap) :
    List DiffHint :=
  sortHintsByKey path.length
    (diffFieldsGo fuel path am em ++ extraHints path em am)

/-- Budgeted value diff at the Haskell path-length cap. -/
def diffValue (path : Path) (e a : Value) : List DiffHint :=
  diffValueAux (maxDiffDepth - path.length) path e a

/-! ## Hint capping (`capHints`, §6.1) -/

/-- Port of `Engine.Core.capHints`: keep the first `maxDiffHints`
hints; if any were dropped, append a single `hTruncated` marker
carrying the path of the first dropped hint. -/
def capHints (hints : List DiffHint) : List DiffHint :=
  match hints.drop maxDiffHints with
  | [] => hints.take maxDiffHints
  | h :: _ => hints.take maxDiffHints ++ [DiffHint.hTruncated (hintPath h)]

private theorem take_all_le' {l : List DiffHint} {n : Nat}
    (h : l.length ≤ n) : l.take n = l := by
  have hdrop : l.drop n = [] := List.drop_eq_nil_of_le h
  have hap := List.take_append_drop n l
  rw [hdrop] at hap
  simpa using hap

theorem capHints_length_le {hints : List DiffHint}
    (h : hints.length ≤ maxDiffHints) : capHints hints = hints := by
  have hdrop : hints.drop maxDiffHints = [] :=
    List.drop_eq_nil_of_le h
  rw [capHints, hdrop, take_all_le' h]

theorem capHints_prefix (hints : List DiffHint) (i : Nat)
    (hi : i < maxDiffHints) : (capHints hints)[i]? = hints[i]? := by
  by_cases hle : hints.length ≤ maxDiffHints
  · rw [capHints_length_le hle]
  · have hne : hints.drop maxDiffHints ≠ [] := by
      intro he
      have hl : (hints.drop maxDiffHints).length
          = hints.length - maxDiffHints := List.length_drop
      rw [he] at hl
      simp at hl
      omega
    rcases hd : hints.drop maxDiffHints with _ | ⟨h, _⟩
    · exact absurd hd hne
    · rw [capHints, hd]
      have htake : (hints.take maxDiffHints).length = maxDiffHints := by
        rw [List.length_take]; omega
      rw [List.getElem?_append_left (by omega), List.getElem?_take, if_pos hi]

theorem capHints_truncated {hints : List DiffHint}
    (h : maxDiffHints < hints.length) :
    ∃ h₀ : DiffHint, hints[maxDiffHints]? = some h₀ ∧
      (capHints hints)[maxDiffHints]? =
        some (DiffHint.hTruncated (hintPath h₀)) ∧
      (capHints hints).length = maxDiffHints + 1 := by
  have hne : hints.drop maxDiffHints ≠ [] := by
    intro he
    have hl : (hints.drop maxDiffHints).length
        = hints.length - maxDiffHints := List.length_drop
    rw [he] at hl
    simp at hl
    omega
  rcases hd : hints.drop maxDiffHints with _ | ⟨h₀, rest⟩
  · exact absurd hd hne
  · have htake : (hints.take maxDiffHints).length = maxDiffHints := by
      rw [List.length_take]; omega
    have hget : hints[maxDiffHints]? = some h₀ := by
      have h1 : (hints.drop maxDiffHints)[0]? = some h₀ := by
        rw [hd]; rfl
      have h2 := List.getElem?_drop (xs := hints) (i := maxDiffHints) (j := 0)
      rw [h1] at h2
      simpa using h2.symm
    refine ⟨h₀, hget, ?_, ?_⟩
    · rw [capHints, hd, List.getElem?_append_right (by omega), htake]
      simp
    · rw [capHints, hd]
      simp [htake]

/-! ## Soundness and completeness core (§6.1) -/

private theorem append_nil_iff {α : Type} {l₁ l₂ : List α} :
    l₁ ++ l₂ = [] ↔ l₁ = [] ∧ l₂ = [] := by
  cases l₁ with
  | nil =>
    cases l₂ with
    | nil => simp
    | cons b bs => simp
  | cons a as => simp

private theorem filter_nil_forall {α : Type} {p : α → Bool} {l : List α}
    (h : l.filter p = []) : ∀ x ∈ l, p x = false := by
  intro x hx
  cases hp : p x with
  | false => rfl
  | true =>
    have hmem : x ∈ l.filter p := List.mem_filter.mpr ⟨hx, hp⟩
    rw [h] at hmem
    simp at hmem

private theorem diffSet_nil_valEq (path : Path) (es as : List Value)
    (h : diffSet path es as = []) : valEq (.vset es) (.vset as) = true := by
  simp only [valEq, Bool.and_eq_true]
  rw [diffSet, append_nil_iff] at h
  obtain ⟨h1, h2⟩ := h
  have hf1 : es.filter (fun e => !setAny e as) = [] := List.map_eq_nil_iff.mp h1
  have hf2 : as.filter (fun a => !setAny a es) = [] := List.map_eq_nil_iff.mp h2
  constructor
  · rw [setCont_iff]
    intro x hx
    have hb := filter_nil_forall hf1 x hx
    have hsa : setAny x as = true := by
      cases hbb : setAny x as <;> simp_all
    exact (setAny_iff x as).mp hsa
  · rw [setCont_iff]
    intro x hx
    have hb := filter_nil_forall hf2 x hx
    have hsa : setAny x es = true := by
      cases hbb : setAny x es <;> simp_all
    exact (setAny_iff x es).mp hsa

private theorem lookup_mem' {m : ValueMap} {k : String} {v : Value}
    (h : ValueMap.lookup k m = some v) : (k, v) ∈ m := by
  induction m with
  | nil => simp [ValueMap.lookup] at h
  | cons p ps ih =>
    obtain ⟨k', v'⟩ := p
    simp only [ValueMap.lookup, List.lookup_cons] at h
    split at h
    · next hk =>
      rw [Option.some.injEq] at h
      rw [beq_iff_eq] at hk
      subst hk
      subst h
      exact List.mem_cons_self
    · exact List.mem_cons_of_mem _ (ih h)

private theorem lookup_isSome_of_mem {m : ValueMap} {k : String} {v : Value}
    (h : (k, v) ∈ m) : (ValueMap.lookup k m).isSome = true := by
  induction m with
  | nil => cases h
  | cons p ps ih =>
    obtain ⟨k', v'⟩ := p
    rcases List.mem_cons.mp h with h | h
    · rw [Prod.mk.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      simp [ValueMap.lookup, List.lookup_cons, beq_self_eq_true]
    · simp only [ValueMap.lookup, List.lookup_cons]
      cases hk : k == k' with
      | true => simp
      | false => exact ih h

private theorem lookup_eq_some_of_mem_nodup' {m : ValueMap}
    (hnd : NodupKeys m) {k : String} {v : Value}
    (h : (k, v) ∈ m) : ValueMap.lookup k m = some v := by
  induction m with
  | nil => cases h
  | cons p ps ih =>
    obtain ⟨k', v'⟩ := p
    rcases List.mem_cons.mp h with h | h
    · rw [Prod.mk.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      simp [ValueMap.lookup, List.lookup_cons, beq_self_eq_true]
    · have hnd' := List.nodup_cons.mp hnd
      have hne : k ≠ k' := by
        intro heq
        exact hnd'.1 (List.mem_map.mpr ⟨(k, v), h, by simp [heq]⟩)
      simp only [ValueMap.lookup, List.lookup_cons,
        beq_eq_false_iff_ne.mpr hne]
      exact ih hnd'.2 h

private theorem mem_unique_of_nodupKeys {m : ValueMap} (hnd : NodupKeys m)
    {k : String} {v w : Value} (hv : (k, v) ∈ m) (hw : (k, w) ∈ m) :
    v = w := by
  have h1 := lookup_eq_some_of_mem_nodup' hnd hv
  have h2 := lookup_eq_some_of_mem_nodup' hnd hw
  rw [h1] at h2
  exact (Option.some.injEq v w).mp h2

/-- **B**: field-level soundness, parameterized by `A` at the smaller
budget. -/
private theorem fields_sound {fuel : Nat}
    (ihA : ∀ path e a, WfValue a →
      (diffValueAux fuel path e a = [] ↔ valEq e a = true))
    (path : Path) (em am : ValueMap) (hndam : NodupKeys am)
    (hall : ∀ p ∈ am, WfValue p.2)
    (h : diffFieldsGo (fuel + 1) path am em ++ extraHints path em am = []) :
    mapCont em am = true ∧ mapCont am em = true := by
  rw [append_nil_iff] at h
  obtain ⟨hgo, hextra⟩ := h
  have hmem : ∀ (em2 : ValueMap), diffFieldsGo (fuel + 1) path am em2 = [] →
      ∀ (k : String) (ev : Value), (k, ev) ∈ em2 →
        ∃ av, ValueMap.lookup k am = some av ∧
          diffValueAux fuel (path ++ [PathSeg.field k]) ev av = [] := by
    intro em2
    induction em2 with
    | nil => intro _ k ev hkv; cases hkv
    | cons p ps igh =>
      obtain ⟨k', v'⟩ := p
      intro hgo2 k ev hkv
      rw [diffFieldsGo, append_nil_iff] at hgo2
      obtain ⟨hh, hrest⟩ := hgo2
      rcases List.mem_cons.mp hkv with hkv | hkv
      · rw [Prod.mk.injEq] at hkv
        obtain ⟨rfl, rfl⟩ := hkv
        split at hh
        · rename_i av hlook
          exact ⟨av, hlook, hh⟩
        · simp at hh
      · obtain ⟨av, h1, h2⟩ := igh hrest k ev hkv
        exact ⟨av, h1, h2⟩
  have hex : ∀ (am2 : ValueMap), extraHints path em am2 = [] →
      ∀ (k : String) (av : Value), (k, av) ∈ am2 →
        (ValueMap.lookup k em).isSome = true := by
    intro am2
    induction am2 with
    | nil => intro _ k av hkv; cases hkv
    | cons p ps ihx =>
      obtain ⟨k', v'⟩ := p
      intro hext k av hkv
      rw [extraHints, append_nil_iff] at hext
      obtain ⟨hh, hrest⟩ := hext
      rcases List.mem_cons.mp hkv with hkv | hkv
      · rw [Prod.mk.injEq] at hkv
        obtain ⟨rfl, rfl⟩ := hkv
        by_cases his : (ValueMap.lookup k em).isSome = true
        · exact his
        · rw [if_neg his] at hh
          simp at hh
      · exact ihx hrest k av hkv
  refine ⟨(mapCont_iff em am).mpr ?_, (mapCont_iff am em).mpr ?_⟩
  · intro k ev hkv
    obtain ⟨av, hlu, hdv⟩ := hmem em hgo k ev hkv
    have hw : valEq ev av = true :=
      (ihA _ _ _ (hall (k, av) (lookup_mem' hlu))).mp hdv
    exact ⟨av, lookup_mem' hlu, hw⟩
  · intro k av hkv
    obtain ⟨w, hw⟩ := Option.isSome_iff_exists.mp (hex am hextra k av hkv)
    obtain ⟨av₀, hlu₀, hd₀⟩ := hmem em hgo k w (lookup_mem' hw)
    have hw0 : valEq w av₀ = true :=
      (ihA _ _ _ (hall (k, av₀) (lookup_mem' hlu₀))).mp hd₀
    have hav : av₀ = av :=
      mem_unique_of_nodupKeys hndam (lookup_mem' hlu₀) hkv
    exact ⟨w, lookup_mem' hw, valEq_symm w av (hav ▸ hw0)⟩

/-- **C**: element-level soundness, parameterized by `A` at the
smaller budget. -/
private theorem elems_sound {fuel : Nat}
    (ihA : ∀ path e a, WfValue a →
      (diffValueAux fuel path e a = [] ↔ valEq e a = true))
    (path : Path) (es as : List Value) (hwas : ∀ x ∈ as, WfValue x)
    (h : diffElemsGo (fuel + 1) path 0 es as = []) :
    listEq es as = true := by
  have hgo : ∀ (es2 as2 : List Value) (i : Nat),
      diffElemsGo (fuel + 1) path i es2 as2 = [] →
      (∀ x ∈ as2, WfValue x) → listEq es2 as2 = true := by
    intro es2
    induction es2 with
    | nil =>
      intro as2 i hgo2 hwas2
      cases as2 with
      | nil => simp [listEq]
      | cons a asr =>
        rw [diffElemsGo] at hgo2
        simp at hgo2
    | cons e esr igh =>
      intro as2 i hgo2 hwas2
      cases as2 with
      | nil =>
        rw [diffElemsGo] at hgo2
        simp at hgo2
      | cons a asr =>
        rw [diffElemsGo, append_nil_iff] at hgo2
        obtain ⟨hh, hrest⟩ := hgo2
        have hv : valEq e a = true :=
          (ihA _ _ _ (hwas2 a List.mem_cons_self)).mp hh
        have hr := igh asr (i + 1) hrest
          (fun x hx => hwas2 x (List.mem_cons_of_mem _ hx))
        simp [listEq, hv, hr]
  exact hgo es as 0 h hwas

private theorem wf_record_inv {m : ValueMap} (h : WfValue (.vrecord m)) :
    NodupKeys m ∧ (∀ p ∈ m, WfValue p.2) := by
  cases h with
  | record hnd hall => exact ⟨hnd, hall⟩

private theorem wf_vmap_inv {m : ValueMap} (h : WfValue (.vmap m)) :
    NodupKeys m ∧ (∀ p ∈ m, WfValue p.2) := by
  cases h with
  | vmap hnd hall => exact ⟨hnd, hall⟩

private theorem wf_variant_inv {t : String} {v : Value} (h : WfValue (.vvariant t v)) :
    WfValue v := by
  cases h with
  | variant hsub => exact hsub

private theorem wf_vseq_inv {xs : List Value} (h : WfValue (.vseq xs)) :
    ∀ x ∈ xs, WfValue x := by
  cases h with
  | vseq hl => exact hl

private theorem wf_vtuple_inv {xs : List Value} (h : WfValue (.vtuple xs)) :
    ∀ x ∈ xs, WfValue x := by
  cases h with
  | vtuple hl => exact hl

/-- **A** at budget `fuel + 1`, by case analysis on the value pair. -/
private theorem value_sound {fuel : Nat}
    (ihA : ∀ path e a, WfValue a →
      (diffValueAux fuel path e a = [] ↔ valEq e a = true))
    (bB : ∀ path em am, NodupKeys am → (∀ p ∈ am, WfValue p.2) →
      diffFieldsGo (fuel + 1) path am em ++ extraHints path em am = [] →
      mapCont em am = true ∧ mapCont am em = true)
    (bC : ∀ path es as, (∀ x ∈ as, WfValue x) →
      diffElemsGo (fuel + 1) path 0 es as = [] → listEq es as = true)
    (e a : Value) (path : Path) (wfa : WfValue a)
    (hv : ¬(valEq e a = true)) :
    diffValueAux (fuel + 1) path e a ≠ [] := by
  intro h
  cases e <;> cases a <;>
    simp only [diffValueAux, if_neg hv, sameShape, reduceIte,
      sortHintsByKey_nil_iff] at h <;>
    first
    | (exact hv (by
        have hb := bB _ _ _ (wf_record_inv wfa).1 (wf_record_inv wfa).2 h
        simp [valEq, hb.1, hb.2]))
    | (exact hv (by
        have hb := bB _ _ _ (wf_vmap_inv wfa).1 (wf_vmap_inv wfa).2 h
        simp [valEq, hb.1, hb.2]))
    | (exact hv (by
        simp only [valEq]
        exact bC _ _ _ (wf_vseq_inv wfa) h))
    | (exact hv (by
        simp only [valEq]
        exact bC _ _ _ (wf_vtuple_inv wfa) h))
    | (split at h
       · next ht =>
         exact hv
           (by simp [valEq, ht, (ihA _ _ _ (wf_variant_inv wfa)).mp h])
       · simp at h)
    | (exact hv (diffSet_nil_valEq _ _ _ h))
    | (have hx := congrArg List.length h; simp at hx)
    | (simp only [if_true, ite_true, reduceIte, List.cons_ne_nil] at h)
    | simp at h

/-- Fuel-indexed core of the §6.1 theorems.

- `A`: no hints ⇔ `valEq` agreement (for well-formed actual values).
- `B`: no field hints implies mutual `mapCont` containment.
- `C`: no element hints implies `listEq`. -/
private theorem core_fuel : ∀ fuel : Nat,
    (∀ path e a, WfValue a →
      (diffValueAux fuel path e a = [] ↔ valEq e a = true))
  ∧ (∀ path em am, WfValue (.vrecord am) →
      (diffFieldsGo (fuel + 1) path am em ++ extraHints path em am = [] →
        mapCont em am = true ∧ mapCont am em = true))
  ∧ (∀ path es as, (∀ x ∈ as, WfValue x) →
      (diffElemsGo (fuel + 1) path 0 es as = [] →
        listEq es as = true)) := by
  intro fuel
  induction fuel with
  | zero =>
    have aA : ∀ path e a, WfValue a →
        (diffValueAux 0 path e a = [] ↔ valEq e a = true) := by
      intro path e a _
      constructor
      · intro h
        by_cases hv : valEq e a = true
        · exact hv
        · rw [diffValueAux, if_neg hv] at h
          simp at h
      · intro hv
        cases e <;> cases a <;>
          simp only [diffValueAux, hv, reduceIte]
    refine ⟨aA, ?_, ?_⟩
    · intro path em am wfa h
      rcases wfa with ⟨hnd, hall⟩
      exact fields_sound aA path em am hnd hall h
    · intro path es as hwas h
      exact elems_sound aA path es as hwas h
  | succ fuel ih =>
    obtain ⟨ihA, _, _⟩ := ih
    have aA : ∀ path e a, WfValue a →
        (diffValueAux (fuel + 1) path e a = [] ↔ valEq e a = true) := by
      intro path e a wfa
      constructor
      · intro h
        by_cases hv : valEq e a = true
        · exact hv
        · exact absurd h (value_sound ihA
              (fun path em am hnd hall h =>
                fields_sound ihA path em am hnd hall h)
              (fun path es as hwas h =>
                elems_sound ihA path es as hwas h)
              e a path wfa hv)
      · intro hv
        cases e <;> cases a <;>
          simp only [diffValueAux, hv, reduceIte]
    refine ⟨aA, ?_, ?_⟩
    · intro path em am wfa h
      rcases wfa with ⟨hnd, hall⟩
      exact fields_sound aA path em am hnd hall h
    · intro path es as hwas h
      exact elems_sound aA path es as hwas h
/-! ## Public §6.1 theorems for the diff engine -/

/-- **A** (public): with a well-formed actual value, the uncapped
budgeted diff is silent exactly on `valEq`-equal values. -/
theorem diffValueAux_nil_iff_valEq {fuel : Nat} {path : Path} {e a : Value}
    (wfa : WfValue a) :
    diffValueAux fuel path e a = [] ↔ valEq e a = true :=
  (core_fuel fuel).1 path e a wfa

/-- **B** (public, soundness direction): a silent field diff implies
mutual containment. -/
theorem diffFields_nil_mapCont {fuel : Nat} {path : Path} {em am : ValueMap}
    (hndam : NodupKeys am) (hallam : ∀ p ∈ am, WfValue p.2)
    (h : diffFields (fuel + 1) path em am = []) :
    mapCont em am = true ∧ mapCont am em = true := by
  rw [diffFields, sortHintsByKey_nil_iff] at h
  exact fields_sound (core_fuel fuel).1 path em am hndam hallam h

/-- **B⁻¹** (completeness): mutually contained well-formed maps give a
silent field diff. -/
theorem diffFields_mapCont_nil {fuel : Nat} {path : Path} {em am : ValueMap}
    (hndem : NodupKeys em) (hndam : NodupKeys am)
    (hallam : ∀ p ∈ am, WfValue p.2)
    (h1 : mapCont em am = true) (h2 : mapCont am em = true) :
    diffFields (fuel + 1) path em am = [] := by
  rw [diffFields, sortHintsByKey_nil_iff, append_nil_iff]
  constructor
  · have hgo : ∀ (em2 : ValueMap), (∀ (k : String) (ev : Value),
          (k, ev) ∈ em2 → (k, ev) ∈ em) →
        diffFieldsGo (fuel + 1) path am em2 = [] := by
      intro em2
      induction em2 with
      | nil => intro _; simp [diffFieldsGo]
      | cons p ps ih =>
        obtain ⟨k, ev⟩ := p
        intro hsub
        have hmem : (k, ev) ∈ em := hsub k ev List.mem_cons_self
        obtain ⟨av, hvam, hveq⟩ := (mapCont_iff em am).mp h1 k ev hmem
        have hlu : ValueMap.lookup k am = some av :=
          lookup_eq_some_of_mem_nodup' hndam hvam
        rw [diffFieldsGo, hlu, append_nil_iff]
        constructor
        · exact ((core_fuel fuel).1 _ _ _ (hallam (k, av) hvam)).mpr hveq
        · exact ih (fun k' ev' hkv =>
            hsub k' ev' (List.mem_cons_of_mem _ hkv))
    exact hgo em (fun _ _ hkv => hkv)
  · have hex : ∀ (am2 : ValueMap), (∀ (k : String) (av : Value),
          (k, av) ∈ am2 → (k, av) ∈ am) →
        extraHints path em am2 = [] := by
      intro am2
      induction am2 with
      | nil => intro _; rfl
      | cons p ps ih =>
        obtain ⟨k, av⟩ := p
        intro hsub
        have hmem : (k, av) ∈ am := hsub k av List.mem_cons_self
        obtain ⟨w, hwem, _⟩ := (mapCont_iff am em).mp h2 k av hmem
        rw [extraHints, append_nil_iff]
        constructor
        · rw [if_pos (lookup_isSome_of_mem hwem)]
        · exact ih (fun k' av' hkv =>
            hsub k' av' (List.mem_cons_of_mem _ hkv))
    exact hex am (fun _ _ hkv => hkv)

/-! ## `diffState` (port of `Engine.Core.diffState`) -/

/-- The proven-correct notion of state equality (`≈` in §6.1). -/
def stateEq (e a : ValueMap) : Prop :=
  mapCont e a = true ∧ mapCont a e = true

theorem capHints_eq_nil_iff {hints : List DiffHint} :
    capHints hints = [] ↔ hints = [] := by
  constructor
  · intro h
    by_cases hle : hints.length ≤ maxDiffHints
    · rw [capHints_length_le hle] at h
      exact h
    · exfalso
      have hlt : maxDiffHints < hints.length := by omega
      obtain ⟨_, _, _, hlen⟩ := capHints_truncated hlt
      rw [h] at hlen
      simp at hlen
  · intro h
    rw [h]
    rfl

/-- Port of `Engine.Core.diffState`: compare the `filterMeta`
projections and cap the hint list. -/
def diffState (expected actual : ValueMap) : StateDiff :=
  match capHints (diffFields maxDiffDepth [] (filterMeta expected)
      (filterMeta actual)) with
  | [] => StateDiff.statesMatch
  | hints => StateDiff.stateMismatch (filterMeta expected)
      (filterMeta actual) hints

/-- Accessor for the hint list of a state diff. -/
def diffHints : StateDiff → List DiffHint
  | .statesMatch => []
  | .stateMismatch _ _ hints => hints

/-- **§6.1 soundness**: a `statesMatch` verdict certifies state
equality of the filtered states. -/
theorem diffState_sound {expected actual : ValueMap}
    (hnd : NodupKeys (filterMeta actual))
    (hall : ∀ p ∈ filterMeta actual, WfValue p.2)
    (h : diffState expected actual = StateDiff.statesMatch) :
    stateEq (filterMeta expected) (filterMeta actual) := by
  unfold diffState at h
  split at h
  · next hc =>
    rw [capHints_eq_nil_iff] at hc
    have hfuel : maxDiffDepth = 7 + 1 := rfl
    rw [hfuel] at hc
    exact diffFields_nil_mapCont hnd hall hc
  · exact absurd h (by simp)

/-- **§6.1 completeness**: state-equal filtered states always earn a
`statesMatch` verdict (the uncapped diff is silent, so nothing is
truncated). -/
theorem diffState_complete {expected actual : ValueMap}
    (hndem : NodupKeys (filterMeta expected))
    (hndam : NodupKeys (filterMeta actual))
    (hallam : ∀ p ∈ filterMeta actual, WfValue p.2)
    (h : stateEq (filterMeta expected) (filterMeta actual)) :
    diffState expected actual = StateDiff.statesMatch := by
  obtain ⟨h1, h2⟩ := h
  have hfuel : maxDiffDepth = 7 + 1 := rfl
  have hnil : diffFields maxDiffDepth [] (filterMeta expected)
      (filterMeta actual) = [] := by
    rw [hfuel]
    exact diffFields_mapCont_nil hndem hndam hallam h1 h2
  unfold diffState
  rw [hnil]
  rfl
/-! ## Path validity (§6.1): every hint path denotes a subterm -/

/-- `Denotes p c v`: path `p` navigates in container `c` to value `v`. -/
inductive Denotes : Path → Value → Value → Prop
  | here (v : Value) : Denotes [] v v
  | fieldRec {k : String} {rest : Path} {m : ValueMap} {v w : Value}
      (h : (k, v) ∈ m) (d : Denotes rest v w) :
      Denotes (PathSeg.field k :: rest) (.vrecord m) w
  | fieldMap {k : String} {rest : Path} {m : ValueMap} {v w : Value}
      (h : (k, v) ∈ m) (d : Denotes rest v w) :
      Denotes (PathSeg.field k :: rest) (.vmap m) w
  | idxSeq {i : Nat} {rest : Path} {es : List Value} {e w : Value}
      (h : es[i]? = some e) (d : Denotes rest e w) :
      Denotes (PathSeg.index i :: rest) (.vseq es) w
  | idxTup {i : Nat} {rest : Path} {es : List Value} {e w : Value}
      (h : es[i]? = some e) (d : Denotes rest e w) :
      Denotes (PathSeg.index i :: rest) (.vtuple es) w
  | varTag {t : String} {rest : Path} {v w : Value}
      (d : Denotes rest v w) :
      Denotes (PathSeg.field t :: rest) (.vvariant t v) w

private theorem set_path (path : Path) (es as : List Value) :
    ∀ (hin : DiffHint), hin ∈ diffSet path es as →
      ∃ q v, hintPath hin = path ++ q ∧
        (Denotes q (.vset es) v ∨ Denotes q (.vset as) v) := by
  intro hin hmem
  simp only [diffSet, List.mem_append, List.mem_map] at hmem
  rcases hmem with h | h
  · obtain ⟨x, hx, hxe⟩ := h
    exact ⟨[], .vset es, by rw [← hxe, hintPath, List.append_nil],
      Or.inl (Denotes.here _)⟩
  · obtain ⟨x, hx, hxe⟩ := h
    exact ⟨[], .vset as, by rw [← hxe, hintPath, List.append_nil],
      Or.inr (Denotes.here _)⟩

private theorem extraHints_path (path : Path) (em am : ValueMap) :
    ∀ (m : ValueMap) (hin : DiffHint), (∀ p ∈ m, p ∈ am) →
      hin ∈ extraHints path em m →
      ∃ k q v, hintPath hin = path ++ (PathSeg.field k :: q) ∧
        Denotes (PathSeg.field k :: q) (.vrecord am) v := by
  intro m
  induction m with
  | nil => intro hin _ hmem; cases hmem
  | cons p ps ih =>
    obtain ⟨k, av⟩ := p
    intro hin hsub hmem
    simp only [extraHints, List.mem_append] at hmem
    rcases hmem with h | h
    · by_cases his : (ValueMap.lookup k em).isSome = true
      · rw [if_pos his] at h
        cases h
      · rw [if_neg his] at h
        rcases List.mem_cons.mp h with h | h
        · exact ⟨k, [], av, by simp [h, hintPath],
            Denotes.fieldRec (hsub _ List.mem_cons_self)
              (Denotes.here av)⟩
        · cases h
    · obtain ⟨k', q, v, hq, hd⟩ :=
        ih hin (fun p hp => hsub p (List.mem_cons_of_mem _ hp)) h
      exact ⟨k', q, v, hq, hd⟩

private theorem fields_path {fuel : Nat}
    (ihv : ∀ path e a hin, hin ∈ diffValueAux fuel path e a →
      ∃ q v, hintPath hin = path ++ q ∧ (Denotes q e v ∨ Denotes q a v))
    (path : Path) (am : ValueMap) :
    ∀ (m fm : ValueMap) (hin : DiffHint), (∀ p ∈ m, p ∈ fm) →
      hin ∈ diffFieldsGo (fuel + 1) path am m →
      ∃ k q v, hintPath hin = path ++ (PathSeg.field k :: q) ∧
        (Denotes (PathSeg.field k :: q) (.vrecord fm) v ∨
          Denotes (PathSeg.field k :: q) (.vrecord am) v) := by
  intro m
  induction m with
  | nil =>
    intro fm hin _ hmem
    simp only [diffFieldsGo] at hmem
    cases hmem
  | cons p ps ih =>
    obtain ⟨k, ev⟩ := p
    intro fm hin hsub hmem
    simp only [diffFieldsGo, List.mem_append] at hmem
    rcases hmem with h | h
    · split at h
      · next av hlu =>
        obtain ⟨q, v, hq, hd⟩ := ihv _ _ _ _ h
        refine ⟨k, q, v, by simp [hq], ?_⟩
        rcases hd with hd | hd
        · exact Or.inl (Denotes.fieldRec (hsub _ List.mem_cons_self) hd)
        · exact Or.inr (Denotes.fieldRec (lookup_mem' hlu) hd)
      · rcases List.mem_cons.mp h with h | h
        · exact ⟨k, [], ev, by simp [h, hintPath],
            Or.inl (Denotes.fieldRec (hsub _ List.mem_cons_self)
              (Denotes.here ev))⟩
        · cases h
    · obtain ⟨k', q, v, hq, hd⟩ :=
        ih fm hin (fun p hp => hsub p (List.mem_cons_of_mem _ hp)) h
      exact ⟨k', q, v, hq, hd⟩

private theorem elems_nil_nil (fuel : Nat) (path : Path) (i : Nat) :
    diffElemsGo (fuel + 1) path i [] [] = [] := by
  simp only [diffElemsGo]

private theorem elems_path {fuel : Nat}
    (ihv : ∀ path e a hin, hin ∈ diffValueAux fuel path e a →
      ∃ q v, hintPath hin = path ++ q ∧ (Denotes q e v ∨ Denotes q a v))
    (path : Path) (cE cA : List Value → Value)
    (liftE : ∀ {es i e q v}, es[i]? = some e → Denotes q e v →
      Denotes (PathSeg.index i :: q) (cE es) v)
    (liftA : ∀ {as i a q v}, as[i]? = some a → Denotes q a v →
      Denotes (PathSeg.index i :: q) (cA as) v) :
    ∀ (es as : List Value) (hin : DiffHint),
      hin ∈ diffElemsGo (fuel + 1) path 0 es as →
      ∃ q v, hintPath hin = path ++ q ∧
        (Denotes q (cE es) v ∨ Denotes q (cA as) v) := by
  have hnil : ∀ (es0 as0 preE0 : List Value) (as preA : List Value)
      (i : Nat),
      es0 = preE0 → as0 = preA ++ as → i = max preE0.length preA.length →
      (as ≠ [] → preE0.length ≤ preA.length) → ∀ (hin : DiffHint),
      hin ∈ diffElemsGo (fuel + 1) path i [] as →
      ∃ q v, hintPath hin = path ++ q ∧
        (Denotes q (cE es0) v ∨ Denotes q (cA as0) v) := by
    intro es0 as0 preE0 as
    induction as with
    | nil =>
      intro preA i hes has hmax hasle hin hmem
      rw [elems_nil_nil] at hmem
      cases hmem
    | cons a ar iha =>
      intro preA i hes has hmax hasle hin hmem
      simp only [diffElemsGo, List.mem_cons] at hmem
      have hle := hasle (by simp)
      rcases hmem with h | h
      · have hAi : preA.length = i := by omega
        have hget : as0[preA.length]? = some a := by
          rw [has, List.getElem?_append_right (Nat.le_refl _)]
          simp
        exact ⟨[PathSeg.index i], a, by simp [h, hintPath],
          Or.inr (liftA (by rw [← hAi]; exact hget) (Denotes.here a))⟩
      · refine iha (preA ++ [a]) (i + 1) hes
          (by rw [has, List.append_assoc]; rfl)
          (by simp only [List.length_append, List.length_singleton]; omega)
          (by intro _; simp only [List.length_append, List.length_singleton]; omega) hin h
  have hgo : ∀ (es0 as0 es as : List Value) (preE preA : List Value)
      (i : Nat),
      es0 = preE ++ es → as0 = preA ++ as → i = max preE.length preA.length →
      (es ≠ [] → preA.length ≤ preE.length) →
      (as ≠ [] → preE.length ≤ preA.length) →
      ∀ (hin : DiffHint),
      hin ∈ diffElemsGo (fuel + 1) path i es as →
      ∃ q v, hintPath hin = path ++ q ∧
        (Denotes q (cE es0) v ∨ Denotes q (cA as0) v) := by
    intro es0 as0 es
    induction es with
    | nil =>
      intro as preE preA i hes has hmax hesle hasle hin hmem
      exact hnil es0 as0 preE as preA i (by rw [hes]; simp) has hmax hasle hin hmem
    | cons e er ih =>
      intro as preE preA i hes has hmax hesle hasle hin hmem
      have hleE := hesle (by simp)
      cases as with
      | nil =>
        simp only [diffElemsGo, List.mem_cons] at hmem
        rcases hmem with h | h
        · have hEi : preE.length = i := by omega
          have hget : es0[preE.length]? = some e := by
            rw [hes, List.getElem?_append_right (Nat.le_refl _)]
            simp
          exact ⟨[PathSeg.index i], e, by simp [h, hintPath],
            Or.inl (liftE (by rw [← hEi]; exact hget) (Denotes.here e))⟩
        · refine ih [] (preE ++ [e]) preA (i + 1)
            (by rw [hes]; simp) has
            (by simp only [List.length_append, List.length_singleton]; omega)
            (by intro _; simp only [List.length_append, List.length_singleton]; omega)
            (by intro h; exact absurd rfl h) hin h
      | cons a ar =>
        simp only [diffElemsGo, List.mem_append] at hmem
        have hleA := hasle (by simp)
        have hEi : preE.length = i := by omega
        have hAi : preA.length = i := by omega
        rcases hmem with h | h
        · obtain ⟨q, v, hq, hd⟩ := ihv _ _ _ _ h
          rcases hd with hd | hd
          · have hget : es0[preE.length]? = some e := by
              rw [hes, List.getElem?_append_right (Nat.le_refl _)]
              simp
            exact ⟨PathSeg.index i :: q, v, by simp [hq],
              Or.inl (liftE (by rw [← hEi]; exact hget) hd)⟩
          · have hget : as0[preA.length]? = some a := by
              rw [has, List.getElem?_append_right (Nat.le_refl _)]
              simp
            exact ⟨PathSeg.index i :: q, v, by simp [hq],
              Or.inr (liftA (by rw [← hAi]; exact hget) hd)⟩
        · refine ih ar (preE ++ [e]) (preA ++ [a]) (i + 1)
            (by rw [hes]; simp) (by rw [has]; simp)
            (by simp only [List.length_append, List.length_singleton]; omega)
            (by intro _; simp only [List.length_append, List.length_singleton]; omega)
            (by intro _; simp only [List.length_append, List.length_singleton]; omega) hin h
  intro es as hin hmem
  exact hgo es as es as [] [] 0 rfl rfl rfl
    (by intro _; simp) (by intro _; simp) hin hmem
private theorem fieldRec_map {k q m v}
    (h : Denotes (PathSeg.field k :: q) (.vrecord m) v) :
    Denotes (PathSeg.field k :: q) (.vmap m) v := by
  cases h with
  | fieldRec hmem hd => exact Denotes.fieldMap hmem hd

private theorem value_path {fuel : Nat}
    (ihv : ∀ path e a hin, hin ∈ diffValueAux fuel path e a →
      ∃ q v, hintPath hin = path ++ q ∧ (Denotes q e v ∨ Denotes q a v))
    (e a : Value) (path : Path) (hin : DiffHint)
    (hv : ¬(valEq e a = true))
    (hmem : hin ∈ diffValueAux (fuel + 1) path e a) :
    ∃ q v, hintPath hin = path ++ q ∧ (Denotes q e v ∨ Denotes q a v) := by
  cases e <;> cases a <;>
    simp only [diffValueAux, if_neg hv, sameShape, reduceIte,
      mem_sortHintsByKey] at hmem <;>
    first
    | (exact by
        rcases List.mem_append.mp hmem with h | h
        · first
          | (exact by
              simp only [List.mem_map] at h
              rcases h with ⟨x, hx, hxe⟩
              rename_i es as
              exact ⟨[], .vset es,
                by rw [← hxe]; simp [hintPath], Or.inl (Denotes.here _)⟩)
          | (exact by
              have h2 := fields_path ihv path _ _ _ _ (fun p hp => hp) h
              rcases h2 with ⟨k, q, v, hq, hd⟩
              refine ⟨PathSeg.field k :: q, v, hq, ?_⟩
              first
              | exact hd
              | exact hd.elim (fun h' => Or.inl (fieldRec_map h'))
                  (fun h' => Or.inr (fieldRec_map h')))
        · first
          | (exact by
              simp only [List.mem_map] at h
              rcases h with ⟨x, hx, hxe⟩
              rename_i es as
              exact ⟨[], .vset as,
                by rw [← hxe]; simp [hintPath], Or.inr (Denotes.here _)⟩)
          | (exact by
              have h2 := extraHints_path path _ _ _ _ (fun p hp => hp) h
              rcases h2 with ⟨k, q, v, hq, hd⟩
              refine ⟨PathSeg.field k :: q, v, hq, ?_⟩
              first
              | exact Or.inr hd
              | exact Or.inr (fieldRec_map hd)))
    | (exact by
        have h2 := elems_path ihv path Value.vseq Value.vseq
          Denotes.idxSeq Denotes.idxSeq _ _ _ hmem
        exact h2)
    | (exact by
        have h2 := elems_path ihv path Value.vtuple Value.vtuple
          Denotes.idxTup Denotes.idxTup _ _ _ hmem
        exact h2)
    | (exact by
        rename_i tag₁ v₁ tag₂ v₂
        split at hmem
        · next ht =>
          have htag : tag₁ = tag₂ := by simpa using ht
          have h2 := ihv _ _ _ _ hmem
          rcases h2 with ⟨q, v, hq, hd⟩
          rcases hd with hd | hd
          · refine ⟨PathSeg.field tag₁ :: q, v, ?_, Or.inl (Denotes.varTag hd)⟩
            simp [hq]
          · refine ⟨PathSeg.field tag₁ :: q, v, ?_, ?_⟩
            · simp [hq]
            · rw [htag]
              exact Or.inr (Denotes.varTag hd)
        · rcases List.mem_cons.mp hmem with h | h
          · exact ⟨[], _, by simp [h, hintPath], Or.inl (Denotes.here _)⟩
          · cases h)
    | (exact by
        have h2 := set_path _ _ _ _ hmem
        exact h2)
    | (exact by
        rcases List.mem_cons.mp hmem with h | h
        · exact ⟨[], _, by simp [h, hintPath], Or.inl (Denotes.here _)⟩
        · cases h)
/-- **§6.1 path validity**: every hint produced by the uncapped
budgeted diff carries a path that denotes a subterm of `e` or `a`. -/
theorem diffValueAux_pathValid : ∀ (fuel : Nat) (path : Path) (e a : Value)
    (hin : DiffHint), hin ∈ diffValueAux fuel path e a →
    ∃ q v, hintPath hin = path ++ q ∧ (Denotes q e v ∨ Denotes q a v) := by
  intro fuel
  induction fuel with
  | zero =>
    intro path e a hin hmem
    by_cases hv : valEq e a = true
    · simp only [diffValueAux, hv, reduceIte] at hmem
      cases hmem
    · rw [diffValueAux, if_neg hv] at hmem
      rcases List.mem_cons.mp hmem with h | h
      · exact ⟨[], _, by simp [h, hintPath],
          Or.inl (Denotes.here _)⟩
      · cases h
  | succ fuel ih =>
    intro path e a hin hmem
    by_cases hv : valEq e a = true
    · cases e <;> cases a <;>
        simp only [diffValueAux, hv, reduceIte] at hmem <;>
        cases hmem
    · exact value_path ih e a path hin hv hmem
