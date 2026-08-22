/-!
# Core.Value — ITF values with verified set/map equality

Port of `Apalache.Types.Value` from the Haskell ModelMirrors mirror
(design doc §5.1, Layer 0).  Constructor naming follows Lean convention
(lowercase); the Haskell names map as `VInt → Value.vint`, etc.

Design notes (§5.1):

- `ValueMap` is an assoc-list-backed map (`List (String × Value)`).
  Map equality (`valEq` on `vrecord`/`vmap`) is *entry-wise mutual
  containment*: every binding of one side has an equal-valued binding
  under the same key on the other side, and vice versa.  This is an
  equivalence for arbitrary lists and coincides with pointwise lookup
  agreement on maps with distinct keys (`mapCont_lookup_of_nodup`).
  A hash map is deliberately avoided (§9.3).
- `VSet` keeps the list-of-elements representation; set equality is the
  *defined relation* `setEq` with a `Decidable` instance, and the §6.1
  law `setEq_iff_forall_setMem` (`setEq xs ys ↔ ∀ v, v ∈ xs ↔ v ∈ ys`)
  replaces the hand-rolled Haskell `Eq` instance.  Unlike the Haskell
  instance (length equality plus one-way containment — which admits
  `[a,a] == [a,b]`!), `setEq` is purely extensional and provably an
  equivalence.
- `isMetaKey` / `filterMeta` port `Engine.Core.isMetaKey` and the meta
  filtering applied by `diffState` (§6.1): drop keys starting with `#`,
  plus `action_taken` and `parameters`.
- No `IO` anywhere in this module.

Cf. the ITF trace format:
<https://apalache-mc.org/docs/adr/015adr-trace.html#summary>. -/

inductive Value where
  /- Haskell `VInt Integer`; `Int` is arbitrary precision in Lean. -/
  | vint (i : Int)
  | vbool (b : Bool)
  | vstr (s : String)
  /- Set semantics: equality is the defined relation `setEq`, not list
  equality; duplicates are preserved until interpreted (§5.1). -/
  | vset (xs : List Value)
  | vseq (xs : List Value)
  | vtuple (xs : List Value)
  /- Assoc-list map with entry-wise extensional equality; see module
  doc. -/
  | vrecord (m : List (String × Value))
  | vmap (m : List (String × Value))
  | vvariant (tag : String) (v : Value)
  /- Text of an ITF value apalache could not serialize. -/
  | vunserializable (s : String)
  | vnull
  deriving Repr

/-! ## Maps

Assoc-list map (§9.3: prove against the obviously correct structure).
`insert` replaces any previous binding and otherwise appends, so maps
built through the API have distinct keys; `lookup` takes the first
binding. -/

abbrev ValueMap := List (String × Value)

namespace ValueMap

  def empty : ValueMap := []

  def erase (k : String) (m : ValueMap) : ValueMap :=
    m.filter (fun p => p.1 != k)

  def insert (k : String) (v : Value) (m : ValueMap) : ValueMap :=
    (k, v) :: erase k m

  def lookup (k : String) (m : ValueMap) : Option Value :=
    List.lookup k m

  def keys (m : ValueMap) : List String :=
    m.map Prod.fst

  def contains (k : String) (m : ValueMap) : Bool :=
    (lookup k m).isSome

  theorem lookup_insert (k : String) (v : Value) (m : ValueMap) :
      (insert k v m).lookup k = some v := by
    simp [insert, erase, lookup, List.lookup_cons, beq_self_eq_true]

end ValueMap

/-! ## A size measure for well-founded proofs -/

mutual

  def valueSize : Value → Nat
    | .vint _ | .vbool _ | .vstr _ | .vunserializable _ | .vnull => 1
    | .vset xs | .vseq xs | .vtuple xs => 1 + listSize xs
    | .vrecord m | .vmap m => 1 + mapSize m
    | .vvariant _ v => 1 + valueSize v

  /- The `+ 1` per element gives every recursive call a strictly
  smaller measure even on singleton lists. -/
  def listSize : List Value → Nat
    | [] => 0
    | v :: vs => valueSize v + 1 + listSize vs

  def mapSize : ValueMap → Nat
    | [] => 0
    | (_, v) :: ps => valueSize v + 1 + mapSize ps

end

private theorem listSize_cons (a : Value) (as : List Value) :
    listSize (a :: as) = valueSize a + 1 + listSize as := rfl

private theorem mapSize_cons (k : String) (v : Value) (m : ValueMap) :
    mapSize ((k, v) :: m) = valueSize v + 1 + mapSize m := rfl

private theorem mapSize_pair_cons : ∀ (p : String × Value) (ps : ValueMap),
    mapSize (p :: ps) = valueSize p.2 + 1 + mapSize ps := fun _ _ => rfl

private theorem valueSize_pos (v : Value) : 0 < valueSize v := by
  cases v <;> simp only [valueSize, listSize, mapSize] <;> omega

private theorem valueSize_mem {x : Value} {xs : List Value} (h : x ∈ xs) :
    valueSize x < listSize xs := by
  induction xs with
  | nil => cases h
  | cons a as ih =>
    rw [listSize_cons]
    rcases List.mem_cons.mp h with h | h
    · subst h; omega
    · have := ih h; omega

private theorem valueSize_mem_map {k : String} {v : Value} {m : ValueMap}
    (h : (k, v) ∈ m) : valueSize v < mapSize m := by
  induction m with
  | nil => cases h
  | cons p ps ih =>
    rcases List.mem_cons.mp h with h | h
    · rw [Prod.mk.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      rw [mapSize_cons]
      omega
    · rw [mapSize_pair_cons]
      have := ih h
      omega

private theorem valueSize_vset (xs : List Value) :
    valueSize (Value.vset xs) = 1 + listSize xs := rfl
private theorem valueSize_vseq (xs : List Value) :
    valueSize (Value.vseq xs) = 1 + listSize xs := rfl
private theorem valueSize_vtuple (xs : List Value) :
    valueSize (Value.vtuple xs) = 1 + listSize xs := rfl
private theorem valueSize_vrecord (m : ValueMap) :
    valueSize (Value.vrecord m) = 1 + mapSize m := rfl
private theorem valueSize_vmap (m : ValueMap) :
    valueSize (Value.vmap m) = 1 + mapSize m := rfl
private theorem valueSize_vvariant (t : String) (v : Value) :
    valueSize (Value.vvariant t v) = 1 + valueSize v := rfl

/-! ## Value equality

`valEq` is the decision procedure; it is proved to be reflexive,
symmetric and transitive (`valEq_refl`, `valEq_symm`, `valEq_trans`).
It is *not* registered as a global `BEq` instance: equality of sets is
extensional, so `a == b → a = b` (required by `LawfulBEq`) does not
hold — e.g. `{1, 1}` and `{1}` are equal as sets but distinct trees.

The set/map walkers (`setCont`, `setAny`, `mapCont`, `mapAny`) recurse
structurally on their list arguments, so every recursive call is on a
pattern head and well-founded termination is discharged by the size
measures above. -/

mutual

  def valEq (v w : Value) : Bool :=
    match v, w with
    | .vint a, .vint b => a == b
    | .vbool a, .vbool b => a == b
    | .vstr a, .vstr b => a == b
    | .vset xs, .vset ys => setCont xs ys && setCont ys xs
    | .vseq a, .vseq b => listEq a b
    | .vtuple a, .vtuple b => listEq a b
    | .vrecord a, .vrecord b => mapCont a b && mapCont b a
    | .vmap a, .vmap b => mapCont a b && mapCont b a
    | .vvariant t₁ v₁, .vvariant t₂ v₂ => t₁ == t₂ && valEq v₁ v₂
    | .vunserializable a, .vunserializable b => a == b
    | .vnull, .vnull => true
    | _, _ => false
  termination_by valueSize v + valueSize w
  decreasing_by all_goals simp only [valueSize_vset, valueSize_vseq,
      valueSize_vtuple, valueSize_vrecord, valueSize_vmap, valueSize_vvariant,
      listSize_cons, mapSize_cons]; omega

  /- Pairwise equality for sequences/tuples. -/
  def listEq (as bs : List Value) : Bool :=
    match as, bs with
    | [], [] => true
    | a :: as, b :: bs => valEq a b && listEq as bs
    | _, _ => false
  termination_by listSize as + listSize bs
  decreasing_by all_goals simp only [valueSize_vset, valueSize_vseq,
      valueSize_vtuple, valueSize_vrecord, valueSize_vmap, valueSize_vvariant,
      listSize_cons, mapSize_cons]; omega

  /- Every element of `xs` has an equal element of `ys`. -/
  def setCont (xs ys : List Value) : Bool :=
    match xs with
    | [] => true
    | x :: xr => setAny x ys && setCont xr ys
  termination_by listSize xs + listSize ys
  decreasing_by all_goals simp only [valueSize_vset, valueSize_vseq,
      valueSize_vtuple, valueSize_vrecord, valueSize_vmap, valueSize_vvariant,
      listSize_cons, mapSize_cons]; omega

  /- `x` has an equal element of `ys`. -/
  def setAny (x : Value) (ys : List Value) : Bool :=
    match ys with
    | [] => false
    | y :: yr => valEq x y || setAny x yr
  termination_by valueSize x + listSize ys
  decreasing_by all_goals simp only [valueSize_vset, valueSize_vseq,
      valueSize_vtuple, valueSize_vrecord, valueSize_vmap, valueSize_vvariant,
      listSize_cons, mapSize_cons]; omega

  /- Every binding of `m` has an equal-valued binding under the same
  key in `n`. -/
  def mapCont : ValueMap → ValueMap → Bool
    | [], _ => true
    | (k, v) :: mr, n => mapAny k v n && mapCont mr n
  termination_by m n => mapSize m + mapSize n
  decreasing_by all_goals simp only [valueSize_vset, valueSize_vseq,
      valueSize_vtuple, valueSize_vrecord, valueSize_vmap, valueSize_vvariant,
      listSize_cons, mapSize_cons]; omega

  /- The key `k` has a binding in `n` whose value equals `v`. -/
  def mapAny : String → Value → ValueMap → Bool
    | _, _, [] => false
    | k, v, (k', w) :: nr => (k' == k && valEq v w) || mapAny k v nr
  termination_by _ v n => valueSize v + mapSize n
  decreasing_by all_goals simp only [valueSize_vset, valueSize_vseq,
      valueSize_vtuple, valueSize_vrecord, valueSize_vmap, valueSize_vvariant,
      listSize_cons, mapSize_cons]; omega

end

/-! ### `List.lookup` lemmas -/

private theorem lookup_mem {m : ValueMap} {k : String} {v : Value}
    (h : List.lookup k m = some v) : (k, v) ∈ m := by
  induction m with
  | nil => simp [List.lookup] at h
  | cons p ps ih =>
    obtain ⟨k', v'⟩ := p
    simp only [List.lookup_cons] at h
    split at h
    · next hk =>
      rw [Option.some.injEq] at h
      rw [beq_iff_eq] at hk
      subst hk
      subst h
      exact List.mem_cons_self
    · exact List.mem_cons_of_mem _ (ih h)

private theorem lookup_of_mem_keys {m : ValueMap} {k : String}
    (h : k ∈ m.map Prod.fst) : ∃ v, List.lookup k m = some v := by
  induction m with
  | nil => simp at h
  | cons p ps ih =>
    obtain ⟨k', v'⟩ := p
    simp only [List.lookup_cons]
    split
    · next _ => exact ⟨v', rfl⟩
    · next hkf =>
      refine ih ?_
      rcases List.mem_map.mp h with ⟨p', hp', hp2⟩
      rcases List.mem_cons.mp hp' with hp' | hp'
      · exfalso
        rw [hp'] at hp2
        simp only [Prod.fst] at hp2
        subst hp2
        simp at hkf
      · exact List.mem_map.mpr ⟨p', hp', hp2⟩

private theorem lookup_eq_some_of_mem_nodup {m : ValueMap}
    (hnd : (m.map Prod.fst).Nodup) {k : String} {v : Value}
    (h : (k, v) ∈ m) : List.lookup k m = some v := by
  induction m with
  | nil => cases h
  | cons p ps ih =>
    obtain ⟨k', v'⟩ := p
    rcases List.mem_cons.mp h with h | h
    · rw [Prod.mk.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      simp [List.lookup_cons, beq_self_eq_true]
    · have hnd' := List.nodup_cons.mp hnd
      have hne : k ≠ k' := by
        intro heq
        exact hnd'.1 (List.mem_map.mpr ⟨(k, v), h, by simp [heq]⟩)
      rw [List.lookup_cons, beq_eq_false_iff_ne.mpr hne]
      exact ih hnd'.2 h

/-! ### Characterizations of the walkers -/

theorem setAny_iff (x : Value) (ys : List Value) :
    setAny x ys = true ↔ ∃ y, y ∈ ys ∧ valEq x y = true := by
  induction ys with
  | nil => simp [setAny]
  | cons y yr ih =>
    simp only [setAny, Bool.or_eq_true, ih, List.mem_cons]
    constructor
    · rintro (h | ⟨y', hy', hxy⟩)
      · exact ⟨y, Or.inl rfl, h⟩
      · exact ⟨y', Or.inr hy', hxy⟩
    · rintro ⟨y', (rfl | hy'), hxy⟩
      · exact Or.inl hxy
      · exact Or.inr ⟨y', hy', hxy⟩

theorem setCont_iff (xs ys : List Value) :
    setCont xs ys = true ↔
      ∀ x, x ∈ xs → ∃ y, y ∈ ys ∧ valEq x y = true := by
  induction xs with
  | nil => simp [setCont]
  | cons x xr ih =>
    simp only [setCont, Bool.and_eq_true, ih, List.mem_cons]
    constructor
    · rintro ⟨h₁, h₂⟩ v (rfl | hv)
      · exact (setAny_iff _ _).mp h₁
      · exact h₂ v hv
    · intro h
      refine ⟨(setAny_iff _ _).mpr (let ⟨y, hy, hxy⟩ := h x (Or.inl rfl);
          ⟨y, hy, hxy⟩), fun v hv => h v (Or.inr hv)⟩

theorem mapAny_iff (k : String) (v : Value) (n : ValueMap) :
    mapAny k v n = true ↔ ∃ w, (k, w) ∈ n ∧ valEq v w = true := by
  induction n with
  | nil => simp [mapAny]
  | cons p ps ih =>
    obtain ⟨k', w⟩ := p
    constructor
    · intro h
      simp only [mapAny, Bool.or_eq_true] at h
      rcases h with h | h
      · rw [Bool.and_eq_true] at h
        obtain ⟨h1, h2⟩ := h
        rw [beq_iff_eq] at h1
        subst h1
        exact ⟨w, List.mem_cons_self, h2⟩
      · obtain ⟨w', hw', hxy⟩ := ih.mp h
        exact ⟨w', List.mem_cons_of_mem _ hw', hxy⟩
    · rintro ⟨w', hw', hxy⟩
      simp only [mapAny, Bool.or_eq_true]
      rcases List.mem_cons.mp hw' with hw' | hw'
      · rw [Prod.mk.injEq] at hw'
        obtain ⟨rfl, rfl⟩ := hw'
        refine Or.inl ?_
        simp only [Bool.and_eq_true, beq_self_eq_true]
        exact ⟨trivial, hxy⟩
      · exact Or.inr (ih.mpr ⟨w', hw', hxy⟩)

/-- `mapCont m n` holds iff every binding of `m` has an equal-valued
binding under the *same key* in `n`. -/
theorem mapCont_iff (m n : ValueMap) :
    mapCont m n = true ↔
      ∀ (k : String) (v : Value), (k, v) ∈ m →
        ∃ w, (k, w) ∈ n ∧ valEq v w = true := by
  induction m with
  | nil => simp [mapCont]
  | cons p ps ih =>
    obtain ⟨k', v'⟩ := p
    constructor
    · intro h k v hv
      simp only [mapCont, Bool.and_eq_true] at h
      rcases List.mem_cons.mp hv with hv | hv
      · rw [Prod.mk.injEq] at hv
        obtain ⟨rfl, rfl⟩ := hv
        obtain ⟨h1, _⟩ := h
        exact (mapAny_iff _ _ _).mp h1
      · obtain ⟨_, h2⟩ := h
        exact ih.mp h2 k v hv
    · intro h
      simp only [mapCont, Bool.and_eq_true]
      exact ⟨(mapAny_iff _ _ _).mpr (h k' v' List.mem_cons_self),
        ih.mpr (fun k v hv => h k v (List.mem_cons_of_mem _ hv))⟩

private theorem mapCont_refl_of (m : ValueMap)
    (H : ∀ k v, (k, v) ∈ m → valEq v v = true) : mapCont m m = true :=
  (mapCont_iff m m).mpr (fun k v hv => ⟨v, hv, H k v hv⟩)

private theorem setCont_refl_of (xs : List Value)
    (H : ∀ x ∈ xs, valEq x x = true) : setCont xs xs = true :=
  (setCont_iff xs xs).mpr (fun x hx => ⟨x, hx, H x hx⟩)

private theorem setCont_trans_of (xs ys zs : List Value)
    (H : ∀ a ∈ xs, ∀ b ∈ ys, ∀ c ∈ zs,
      valEq a b = true → valEq b c = true → valEq a c = true)
    (h₁ : setCont xs ys = true) (h₂ : setCont ys zs = true) :
    setCont xs zs = true := by
  rw [setCont_iff] at h₁ h₂ ⊢
  intro x hx
  obtain ⟨y, hy, hxy⟩ := h₁ x hx
  obtain ⟨z, hz, hyz⟩ := h₂ y hy
  exact ⟨z, hz, H x hx y hy z hz hxy hyz⟩

private theorem mapCont_trans_of (m n p : ValueMap)
    (H : ∀ (k : String) (a b c : Value), (k, a) ∈ m → (k, b) ∈ n →
      (k, c) ∈ p → valEq a b = true → valEq b c = true → valEq a c = true)
    (h₁ : mapCont m n = true) (h₂ : mapCont n p = true) :
    mapCont m p = true := by
  rw [mapCont_iff] at h₁ h₂ ⊢
  intro k a ha
  obtain ⟨b, hb, hab⟩ := h₁ k a ha
  obtain ⟨c, hc, hbc⟩ := h₂ k b hb
  exact ⟨c, hc, H k a b c ha hb hc hab hbc⟩

/-! ### List equality helpers (bounded induction) -/

private theorem listEq_refl_aux (n : Nat)
    (H : ∀ a, valueSize a ≤ n → valEq a a = true) :
    ∀ as : List Value, listSize as ≤ n → listEq as as = true := by
  intro as
  induction as with
  | nil => intro _; simp [listEq]
  | cons a as ihl =>
    intro hle
    simp only [listEq, Bool.and_eq_true]
    exact ⟨H a (by rw [listSize_cons] at hle; omega),
      ihl (by rw [listSize_cons] at hle; omega)⟩

private theorem listEq_symm_aux (n : Nat)
    (H : ∀ a b, valueSize a ≤ n → valueSize b ≤ n →
      valEq a b = true → valEq b a = true) :
    ∀ as bs : List Value, listSize as ≤ n → listSize bs ≤ n →
      listEq as bs = true → listEq bs as = true := by
  intro as bs
  induction as generalizing bs with
  | nil =>
    intro _ hbs h
    cases bs with
    | nil => exact h
    | cons b bsl => exact absurd h (by simp [listEq])
  | cons a asr ihl =>
    intro has hbs h
    cases bs with
    | nil => exact absurd h (by simp [listEq])
    | cons b bsl =>
      simp only [listEq, Bool.and_eq_true] at h ⊢
      exact ⟨H a b (by rw [listSize_cons] at has; omega)
          (by rw [listSize_cons] at hbs; omega) h.1,
        ihl bsl (by rw [listSize_cons] at has; omega)
          (by rw [listSize_cons] at hbs; omega) h.2⟩

private theorem listEq_trans_aux (n : Nat)
    (H : ∀ a b c, valueSize a ≤ n → valueSize b ≤ n → valueSize c ≤ n →
      valEq a b = true → valEq b c = true → valEq a c = true) :
    ∀ as bs cs : List Value, listSize as ≤ n → listSize bs ≤ n →
      listSize cs ≤ n → listEq as bs = true → listEq bs cs = true →
      listEq as cs = true := by
  intro as bs cs
  induction as generalizing bs cs with
  | nil =>
    intro _ _ _ h₁ h₂
    cases bs with
    | nil =>
      cases cs with
      | nil => exact h₁
      | cons c csl => exact absurd h₂ (by simp [listEq])
    | cons b bsl => exact absurd h₁ (by simp [listEq])
  | cons a asr ihl =>
    intro has hbs hcs h₁ h₂
    cases bs with
    | nil => exact absurd h₁ (by simp [listEq])
    | cons b bsl =>
      cases cs with
      | nil => exact absurd h₂ (by simp [listEq])
      | cons c csl =>
        simp only [listEq, Bool.and_eq_true] at h₁ h₂ ⊢
        exact ⟨H a b c (by rw [listSize_cons] at has; omega)
            (by rw [listSize_cons] at hbs; omega)
            (by rw [listSize_cons] at hcs; omega) h₁.1 h₂.1,
          ihl bsl csl (by rw [listSize_cons] at has; omega)
            (by rw [listSize_cons] at hbs; omega)
            (by rw [listSize_cons] at hcs; omega) h₁.2 h₂.2⟩

/-! ## `valEq` is an equivalence -/

/-- Reflexivity of the value-equality decision procedure. -/
theorem valEq_refl (v : Value) : valEq v v = true := by
  suffices H : ∀ n v', valueSize v' ≤ n → valEq v' v' = true by
    exact H (valueSize v) v (Nat.le_refl _)
  intro n
  induction n with
  | zero => intro v hv; have := valueSize_pos v; omega
  | succ n ih =>
    intro v hv
    cases v with
    | vint _ | vbool _ | vstr _ | vunserializable _ =>
      simp only [valEq, beq_self_eq_true]
    | vnull => simp only [valEq]
    | vset xs =>
      simp only [valEq, Bool.and_eq_true]
      have hb : ∀ x ∈ xs, valueSize x ≤ n := by
        intro x hx
        have h1 := valueSize_mem hx
        have h2 : valueSize (Value.vset xs) = 1 + listSize xs := rfl
        omega
      exact ⟨setCont_refl_of xs (fun x hx => ih x (hb x hx)),
        setCont_refl_of xs (fun x hx => ih x (hb x hx))⟩
    | vseq xs =>
      simp only [valEq]
      refine listEq_refl_aux n (fun a ha => ih a ha) xs ?_
      have h2 : valueSize (Value.vseq xs) = 1 + listSize xs := rfl
      omega
    | vtuple xs =>
      simp only [valEq]
      refine listEq_refl_aux n (fun a ha => ih a ha) xs ?_
      have h2 : valueSize (Value.vtuple xs) = 1 + listSize xs := rfl
      omega
    | vvariant t v =>
      simp only [valEq, Bool.and_eq_true, beq_self_eq_true, Bool.true_and]
      have h2 := valueSize_vvariant t v
      exact ih v (by omega)
    | vrecord m =>
      simp only [valEq, Bool.and_eq_true]
      have hb : ∀ k v, (k, v) ∈ m → valueSize v ≤ n := by
        intro k v hp
        have h1 := valueSize_mem_map hp
        have h2 : valueSize (Value.vrecord m) = 1 + mapSize m := rfl
        omega
      exact ⟨mapCont_refl_of m (fun k v hv => ih v (hb k v hv)),
        mapCont_refl_of m (fun k v hv => ih v (hb k v hv))⟩
    | vmap m =>
      simp only [valEq, Bool.and_eq_true]
      have hb : ∀ k v, (k, v) ∈ m → valueSize v ≤ n := by
        intro k v hp
        have h1 := valueSize_mem_map hp
        have h2 : valueSize (Value.vmap m) = 1 + mapSize m := rfl
        omega
      exact ⟨mapCont_refl_of m (fun k v hv => ih v (hb k v hv)),
        mapCont_refl_of m (fun k v hv => ih v (hb k v hv))⟩
/-- Symmetry of the value-equality decision procedure. -/
theorem valEq_symm : ∀ v w : Value, valEq v w = true → valEq w v = true := by
  suffices H : ∀ n v, valueSize v ≤ n → ∀ w, valueSize w ≤ n →
      valEq v w = true → valEq w v = true by
    intro v w hvw
    have hv : valueSize v ≤ valueSize v + valueSize w := by omega
    have hw : valueSize w ≤ valueSize v + valueSize w := by omega
    exact H _ v hv w hw hvw
  intro n
  induction n with
  | zero => intro v hv; have := valueSize_pos v; omega
  | succ n ih =>
    intro v hv w hw hvw
    cases v with
    | vint _ =>
      cases w with
      | vint _ => simp only [valEq, beq_iff_eq] at hvw ⊢; exact hvw.symm
      | _ => exact absurd hvw (by simp [valEq])
    | vbool _ =>
      cases w with
      | vbool _ => simp only [valEq, beq_iff_eq] at hvw ⊢; exact hvw.symm
      | _ => exact absurd hvw (by simp [valEq])
    | vstr _ =>
      cases w with
      | vstr _ => simp only [valEq, beq_iff_eq] at hvw ⊢; exact hvw.symm
      | _ => exact absurd hvw (by simp [valEq])
    | vunserializable _ =>
      cases w with
      | vunserializable _ =>
        simp only [valEq, beq_iff_eq] at hvw ⊢; exact hvw.symm
      | _ => exact absurd hvw (by simp [valEq])
    | vnull =>
      cases w with
      | vnull => simp only [valEq]
      | _ => exact absurd hvw (by simp [valEq])
    | vset xs =>
      cases w with
      | vset ys =>
        simp only [valEq, Bool.and_eq_true] at hvw ⊢
        exact ⟨hvw.2, hvw.1⟩
      | _ => exact absurd hvw (by simp [valEq])
    | vseq xs =>
      cases w with
      | vseq ys =>
        simp only [valEq] at hvw ⊢
        refine listEq_symm_aux n (fun a b ha hb hab => ih a ha b hb hab) xs ys ?_ ?_ hvw
        · have h2 : valueSize (Value.vseq xs) = 1 + listSize xs := rfl
          omega
        · have h3 : valueSize (Value.vseq ys) = 1 + listSize ys := rfl
          omega
      | _ => exact absurd hvw (by simp [valEq])
    | vtuple xs =>
      cases w with
      | vtuple ys =>
        simp only [valEq] at hvw ⊢
        refine listEq_symm_aux n (fun a b ha hb hab => ih a ha b hb hab) xs ys ?_ ?_ hvw
        · have h2 : valueSize (Value.vtuple xs) = 1 + listSize xs := rfl
          omega
        · have h3 : valueSize (Value.vtuple ys) = 1 + listSize ys := rfl
          omega
      | _ => exact absurd hvw (by simp [valEq])
    | vrecord m =>
      cases w with
      | vrecord n' =>
        simp only [valEq, Bool.and_eq_true] at hvw ⊢
        exact ⟨hvw.2, hvw.1⟩
      | _ => exact absurd hvw (by simp [valEq])
    | vmap m =>
      cases w with
      | vmap n' =>
        simp only [valEq, Bool.and_eq_true] at hvw ⊢
        exact ⟨hvw.2, hvw.1⟩
      | _ => exact absurd hvw (by simp [valEq])
    | vvariant t₁ v₁ =>
      cases w with
      | vvariant t₂ v₂ =>
        simp only [valEq, Bool.and_eq_true, beq_iff_eq] at hvw ⊢
        rw [valueSize_vvariant] at hv hw
        obtain ⟨rfl, hv⟩ := hvw
        exact ⟨rfl, ih v₁ (by omega) v₂ (by omega) hv⟩
      | _ => exact absurd hvw (by simp [valEq])

/-- Transitivity of the value-equality decision procedure. -/
theorem valEq_trans : ∀ v w u : Value, valEq v w = true →
    valEq w u = true → valEq v u = true := by
  suffices H : ∀ n v, valueSize v ≤ n → ∀ w u, valueSize w ≤ n →
      valueSize u ≤ n → valEq v w = true → valEq w u = true →
      valEq v u = true by
    intro v w u h₁ h₂
    have hv : valueSize v ≤ valueSize v + valueSize w + valueSize u := by omega
    have hw : valueSize w ≤ valueSize v + valueSize w + valueSize u := by omega
    have hu : valueSize u ≤ valueSize v + valueSize w + valueSize u := by omega
    exact H _ v hv w u hw hu h₁ h₂
  intro n
  induction n with
  | zero => intro v hv; have := valueSize_pos v; omega
  | succ n ih =>
    intro v hv w u hw hu hvw hvu
    cases v with
    | vint _ =>
      cases w with
      | vint _ =>
        cases u with
        | vint _ =>
          simp only [valEq, beq_iff_eq] at hvw hvu ⊢
          exact hvw.trans hvu
        | _ => exact absurd hvu (by simp [valEq])
      | _ => exact absurd hvw (by simp [valEq])
    | vbool _ =>
      cases w with
      | vbool _ =>
        cases u with
        | vbool _ =>
          simp only [valEq, beq_iff_eq] at hvw hvu ⊢
          exact hvw.trans hvu
        | _ => exact absurd hvu (by simp [valEq])
      | _ => exact absurd hvw (by simp [valEq])
    | vstr _ =>
      cases w with
      | vstr _ =>
        cases u with
        | vstr _ =>
          simp only [valEq, beq_iff_eq] at hvw hvu ⊢
          exact hvw.trans hvu
        | _ => exact absurd hvu (by simp [valEq])
      | _ => exact absurd hvw (by simp [valEq])
    | vunserializable _ =>
      cases w with
      | vunserializable _ =>
        cases u with
        | vunserializable _ =>
          simp only [valEq, beq_iff_eq] at hvw hvu ⊢
          exact hvw.trans hvu
        | _ => exact absurd hvu (by simp [valEq])
      | _ => exact absurd hvw (by simp [valEq])
    | vnull =>
      cases w with
      | vnull =>
        cases u with
        | vnull => simp only [valEq]
        | _ => exact absurd hvu (by simp [valEq])
      | _ => exact absurd hvw (by simp [valEq])
    | vset xs =>
      cases w with
      | vset ys =>
        cases u with
        | vset zs =>
          have e1 : valueSize (Value.vset xs) = 1 + listSize xs := rfl
          have e2 : valueSize (Value.vset ys) = 1 + listSize ys := rfl
          have e3 : valueSize (Value.vset zs) = 1 + listSize zs := rfl
          have bxs : ∀ a ∈ xs, valueSize a ≤ n := by
            intro a ha; have := valueSize_mem ha; omega
          have bys : ∀ b ∈ ys, valueSize b ≤ n := by
            intro b hb; have := valueSize_mem hb; omega
          have bzs : ∀ c ∈ zs, valueSize c ≤ n := by
            intro c hc; have := valueSize_mem hc; omega
          simp only [valEq, Bool.and_eq_true] at hvw hvu ⊢
          obtain ⟨h₁, h₂⟩ := hvw
          obtain ⟨h₃, h₄⟩ := hvu
          exact ⟨setCont_trans_of xs ys zs
              (fun a ha b hb c hc hab hbc =>
                ih a (bxs a ha) b c (bys b hb) (bzs c hc) hab hbc) h₁ h₃,
            setCont_trans_of zs ys xs
              (fun c hc b hb a ha hcb hba =>
                ih c (bzs c hc) b a (bys b hb) (bxs a ha) hcb hba) h₄ h₂⟩
        | _ => exact absurd hvu (by simp [valEq])
      | _ => exact absurd hvw (by simp [valEq])
    | vseq xs =>
      cases w with
      | vseq ys =>
        cases u with
        | vseq zs =>
          simp only [valEq] at hvw hvu ⊢
          refine listEq_trans_aux n (fun a b c ha hb hc hab hbc =>
              ih a ha b c hb hc hab hbc) xs ys zs ?_ ?_ ?_ hvw hvu
          · have e1 : valueSize (Value.vseq xs) = 1 + listSize xs := rfl
            omega
          · have e2 : valueSize (Value.vseq ys) = 1 + listSize ys := rfl
            omega
          · have e3 : valueSize (Value.vseq zs) = 1 + listSize zs := rfl
            omega
        | _ => exact absurd hvu (by simp [valEq])
      | _ => exact absurd hvw (by simp [valEq])
    | vtuple xs =>
      cases w with
      | vtuple ys =>
        cases u with
        | vtuple zs =>
          simp only [valEq] at hvw hvu ⊢
          refine listEq_trans_aux n (fun a b c ha hb hc hab hbc =>
              ih a ha b c hb hc hab hbc) xs ys zs ?_ ?_ ?_ hvw hvu
          · have e1 : valueSize (Value.vtuple xs) = 1 + listSize xs := rfl
            omega
          · have e2 : valueSize (Value.vtuple ys) = 1 + listSize ys := rfl
            omega
          · have e3 : valueSize (Value.vtuple zs) = 1 + listSize zs := rfl
            omega
        | _ => exact absurd hvu (by simp [valEq])
      | _ => exact absurd hvw (by simp [valEq])
    | vrecord m =>
      cases w with
      | vrecord n' =>
        cases u with
        | vrecord p =>
          have e1 : valueSize (Value.vrecord m) = 1 + mapSize m := rfl
          have e2 : valueSize (Value.vrecord n') = 1 + mapSize n' := rfl
          have e3 : valueSize (Value.vrecord p) = 1 + mapSize p := rfl
          have bm : ∀ k v, (k, v) ∈ m → valueSize v ≤ n := by
            intro k v hq; have := valueSize_mem_map hq; omega
          have bn : ∀ k v, (k, v) ∈ n' → valueSize v ≤ n := by
            intro k v hq; have := valueSize_mem_map hq; omega
          have bp : ∀ k v, (k, v) ∈ p → valueSize v ≤ n := by
            intro k v hq; have := valueSize_mem_map hq; omega
          simp only [valEq, Bool.and_eq_true] at hvw hvu ⊢
          obtain ⟨h₁, h₂⟩ := hvw
          obtain ⟨h₃, h₄⟩ := hvu
          exact ⟨mapCont_trans_of m n' p
              (fun k a b c ha hb hc hab hbc =>
                ih a (bm k a ha) b c (bn k b hb) (bp k c hc) hab hbc) h₁ h₃,
            mapCont_trans_of p n' m
              (fun k c b a hc hb ha hcb hba =>
                ih c (bp k c hc) b a (bn k b hb) (bm k a ha) hcb hba) h₄ h₂⟩
        | _ => exact absurd hvu (by simp [valEq])
      | _ => exact absurd hvw (by simp [valEq])
    | vmap m =>
      cases w with
      | vmap n' =>
        cases u with
        | vmap p =>
          have e1 : valueSize (Value.vmap m) = 1 + mapSize m := rfl
          have e2 : valueSize (Value.vmap n') = 1 + mapSize n' := rfl
          have e3 : valueSize (Value.vmap p) = 1 + mapSize p := rfl
          have bm : ∀ k v, (k, v) ∈ m → valueSize v ≤ n := by
            intro k v hq; have := valueSize_mem_map hq; omega
          have bn : ∀ k v, (k, v) ∈ n' → valueSize v ≤ n := by
            intro k v hq; have := valueSize_mem_map hq; omega
          have bp : ∀ k v, (k, v) ∈ p → valueSize v ≤ n := by
            intro k v hq; have := valueSize_mem_map hq; omega
          simp only [valEq, Bool.and_eq_true] at hvw hvu ⊢
          obtain ⟨h₁, h₂⟩ := hvw
          obtain ⟨h₃, h₄⟩ := hvu
          exact ⟨mapCont_trans_of m n' p
              (fun k a b c ha hb hc hab hbc =>
                ih a (bm k a ha) b c (bn k b hb) (bp k c hc) hab hbc) h₁ h₃,
            mapCont_trans_of p n' m
              (fun k c b a hc hb ha hcb hba =>
                ih c (bp k c hc) b a (bn k b hb) (bm k a ha) hcb hba) h₄ h₂⟩
        | _ => exact absurd hvu (by simp [valEq])
      | _ => exact absurd hvw (by simp [valEq])
    | vvariant _ v₁ =>
      cases w with
      | vvariant _ v₂ =>
        cases u with
        | vvariant _ v₃ =>
          simp only [valEq, Bool.and_eq_true, beq_iff_eq] at hvw hvu ⊢
          rw [valueSize_vvariant] at hv hw hu
          obtain ⟨rfl, hv₁⟩ := hvw
          obtain ⟨rfl, hv₂⟩ := hvu
          exact ⟨rfl, ih v₁ (by omega) v₂ v₃ (by omega) (by omega) hv₁ hv₂⟩
        | _ => exact absurd hvu (by simp [valEq])
      | _ => exact absurd hvw (by simp [valEq])

/-! ## Set equality (§6.1) -/

/-- Membership in a `VSet` element list, via `valEq`. -/
def setMem (v : Value) (xs : List Value) : Prop :=
  ∃ x, x ∈ xs ∧ valEq v x = true

/-- The defined set-equality relation: mutual containment of elements,
up to `valEq`. -/
def setEq (xs ys : List Value) : Prop :=
  (∀ x, x ∈ xs → ∃ y, y ∈ ys ∧ valEq x y = true)
    ∧ (∀ y, y ∈ ys → ∃ x, x ∈ xs ∧ valEq y x = true)

/-- **§6.1 `VSet` equality law**: `setEq` coincides exactly with
extensional membership equality.  This replaces the hand-rolled Haskell
`Eq` instance (which admits `[a,a] == [a,b]`) with a verified decision
procedure. -/
theorem setEq_iff_forall_setMem {xs ys : List Value} :
    setEq xs ys ↔ ∀ v, setMem v xs ↔ setMem v ys := by
  constructor
  · rintro ⟨h₁, h₂⟩ v
    constructor
    · rintro ⟨x, hx, hvx⟩
      obtain ⟨y, hy, hxy⟩ := h₁ x hx
      exact ⟨y, hy, valEq_trans v x y hvx hxy⟩
    · rintro ⟨y, hy, hvy⟩
      obtain ⟨x, hx, hxy⟩ := h₂ y hy
      exact ⟨x, hx, valEq_trans v y x hvy hxy⟩
  · intro h
    exact ⟨fun x hx => (h x).mp ⟨x, hx, valEq_refl x⟩,
      fun y hy => (h y).mpr ⟨y, hy, valEq_refl y⟩⟩

/-- The boolean decision procedure for `setEq`. -/
def setEqBool (xs ys : List Value) : Bool :=
  setCont xs ys && setCont ys xs

theorem setEqBool_iff_setEq {xs ys : List Value} :
    setEqBool xs ys = true ↔ setEq xs ys := by
  simp only [setEqBool, Bool.and_eq_true, setCont_iff, setEq]

/-- `Decidable` instance for the set-equality relation, via the boolean
decision procedure `setEqBool`. -/
instance (xs ys : List Value) : Decidable (setEq xs ys) :=
  decidable_of_decidable_of_iff
    (show (setEqBool xs ys = true) ↔ setEq xs ys from setEqBool_iff_setEq)

/-! ## Map-equality semantics

On maps with distinct keys (all maps produced by the API), value
equality of `vrecord`/`vmap` implies pointwise lookup agreement. -/

theorem mapCont_lookup_of_nodup {m n : ValueMap}
    (hn : (n.map Prod.fst).Nodup)
    (h₁ : mapCont m n = true) {k : String} {v : Value}
    (hl : List.lookup k m = some v) :
    ∃ w, List.lookup k n = some w ∧ valEq v w = true := by
  have hmem : (k, v) ∈ m := lookup_mem hl
  obtain ⟨w, hw, hvw⟩ := (mapCont_iff m n).mp h₁ k v hmem
  have hlk : List.lookup k n = some w :=
    lookup_eq_some_of_mem_nodup hn hw
  exact ⟨w, hlk, hvw⟩

/-! ## Meta keys and `filterMeta` (§6.1) -/

/-- Port of `Engine.Core.isMetaKey`: keys starting with `#`, plus
`action_taken` and `parameters`. -/
def isMetaKey (k : String) : Bool :=
  (!k.isEmpty && k.front == '#') || k == "action_taken" || k == "parameters"

/-- Port of the meta-key filtering applied by `diffState` to expected and
actual states before comparison. -/
def filterMeta (m : ValueMap) : ValueMap :=
  m.filter (fun p => !isMetaKey p.1)

@[simp] theorem mem_filterMeta {k : String} {v : Value} {m : ValueMap} :
    (k, v) ∈ filterMeta m ↔ ((k, v) ∈ m ∧ !isMetaKey k = true) := by
  simp [filterMeta, List.mem_filter]

instance : Inhabited Value := ⟨.vnull⟩