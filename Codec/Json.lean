import Core.Value
import Std.Data.TreeMap.Raw
import Lean.Data.Json

/-!
# Codec.Json — total wire codecs for the mirror protocol (Layer 1, §5.2)

Port of the Haskell `Protocol.Format.Json` aeson instances (413 LOC of
orphan instances) as **two total functions per message type**:

```
encodeClient : ClientMessage → Json
decodeClient : Json → Except DecodeError ClientMessage
```

Field names, sum encoding (tag field `proto_step` + inlined payload
fields), `Maybe`-field omission/null behavior and number formats are
frozen by the Phase 0 golden corpus (`test/fixtures`, generated from
ModelMirrors@3496251); see `tools/ReplayFixtures.lean` for the
byte-identity replay.

Design notes:

* `Lean.Json` objects are `Std.TreeMap.Raw String Json` — keys print in
  lexicographic order, exactly matching aeson's sorted-key fixture
  output.  `Json.compress` produces the compact `{"a":1}` form.
* `Lean.JsonNumber` is mantissa/exponent over `Int` (arbitrary
  precision), so `Json.getNat?`/`getInt?` round-trip exactly (`rfl`).
* ITF `#bigint` integers are carried as decimal *strings* on the wire;
  we implement the decimal codec ourselves with a machine-checked
  round-trip theorem (`parseDec_intRepr`) — `String.toInt?` has no such
  lemma in core.
* §6.6: `decode (encode m)` returns `ok m'` with `m ≈ m'`, where `≈`
  is equality up to `valEq` (the verified equality of `Core.Value`) at
  every `Value` position.  This is the strongest possible statement:
  ITF records are JSON objects, so key order and duplicate keys cannot
  survive a wire round trip, and `valEq` is exactly the extensional
  equality that makes the statement true.  Round-trip is stated under
  `WireOkClient`/`WireOkMirror` (record keys distinct and non-reserved)
  — the Haskell instances carry the same caveats as partiality.
-/
namespace Codec

open Lean Std DTreeMap

/-! ## Errors -/

/-- Decoding failure: human-readable reason. -/
structure DecodeError where
  msg : String
  deriving Repr

abbrev Dec (α : Type u) := Except DecodeError α

@[inline] def derr {α : Type u} (msg : String) : Dec α := .error { msg := msg }

/-! ## A proven decimal codec for `#bigint` strings -/

/-- Digit value of a character; `255` is a sentinel for "not a digit". -/
def digitVal : Char → Nat
  | '0' => 0 | '1' => 1 | '2' => 2 | '3' => 3 | '4' => 4
  | '5' => 5 | '6' => 6 | '7' => 7 | '8' => 8 | '9' => 9
  | _ => 255

def isDigit (c : Char) : Bool := digitVal c ≤ 9

/-- Character for a digit `d ≤ 9` (and `'0'` outside that range). -/
def digitChar : Nat → Char
  | 0 => '0' | 1 => '1' | 2 => '2' | 3 => '3' | 4 => '4'
  | 5 => '5' | 6 => '6' | 7 => '7' | 8 => '8' | 9 => '9'
  | _ => '0'

private theorem digits_table : ∀ (f : Fin 10),
    digitVal (digitChar (f : Nat)) = (f : Nat) := by decide

theorem digitVal_digitChar {d : Nat} (hd : d ≤ 9) : digitVal (digitChar d) = d :=
  digits_table ⟨d, by omega⟩

theorem isDigit_digitChar {d : Nat} (hd : d ≤ 9) : isDigit (digitChar d) = true := by
  simp [isDigit, digitVal_digitChar hd]
  omega

/-- Decimal digits of `k`, most significant first; `[]` for `0`. -/
def digitsAux (k : Nat) : List Char :=
  match k with
  | 0 => []
  | k + 1 =>
      if k + 1 < 10 then [digitChar (k + 1)]
      else digitsAux ((k + 1) / 10) ++ [digitChar ((k + 1) % 10)]
termination_by k
decreasing_by omega

/-- Decimal digits of any `Nat`; `0` renders as `["0"]`. -/
def natRepr (n : Nat) : List Char :=
  if 0 < n then digitsAux n else ['0']

/-- Parse a non-empty all-digit character list as a decimal natural. -/
def parseNatAux (cs : List Char) : Option Nat :=
  if cs.length > 0 && cs.all isDigit then
    some (cs.foldl (fun a c => a * 10 + digitVal c) 0)
  else none

def intChars : Int → List Char
  | .ofNat n => natRepr n
  | .negSucc n => '-' :: natRepr (n + 1)

/-- Decimal representation of an `Int` (no `+`, `-` only when negative). -/
def intRepr (i : Int) : String := String.ofList (intChars i)

/-- Parse a signed decimal character list as an `Int`. -/
def parseDec (cs : List Char) : Option Int :=
  match cs with
  | '-' :: rest =>
      match parseNatAux rest with
      | some n => some (-((n : Int)))
      | none => none
  | _ =>
      match parseNatAux cs with
      | some n => some (Int.ofNat n)
      | none => none

/-! ### Decimal round-trip -/

private theorem digitsAux_val : ∀ k j, j ≤ k → 0 < j →
    ((digitsAux j).foldl (fun a c => a * 10 + digitVal c) 0) = j := by
  intro k
  induction k with
  | zero =>
      intro j hj hjpos
      simp only [Nat.le_zero] at hj
      omega
  | succ k ih =>
      intro j hj hjpos
      have hj1 : j ≠ 0 := by omega
      obtain ⟨m, rfl⟩ : ∃ m, j = m + 1 := ⟨j - 1, by omega⟩
      rcases Nat.lt_or_ge (m + 1) 10 with h10 | h10
      · have h9 : m + 1 ≤ 9 := by omega
        simp only [digitsAux, if_pos h10, List.foldl_cons, List.foldl_nil,
          digitVal_digitChar h9]
        omega
      · have h10' : ¬ (m + 1 < 10) := by omega
        have hpos : (0 : Nat) < 10 := by omega
        have hdiv : 0 < (m + 1) / 10 := Nat.div_pos h10 hpos
        have hle : (m + 1) / 10 ≤ k := by
          have hlt : (m + 1) / 10 < k + 1 := by omega
          omega
        have hval := ih ((m + 1) / 10) hle hdiv
        have hmlt : (m + 1) % 10 < 10 := Nat.mod_lt _ hpos
        have hm : (m + 1) % 10 ≤ 9 := by omega
        simp only [digitsAux, if_neg h10']
        rw [List.foldl_append, hval, List.foldl_cons, List.foldl_nil,
          digitVal_digitChar hm]
        omega

private theorem digitsAux_all : ∀ j, (digitsAux j).all isDigit = true := by
  intro j
  induction j using Nat.strongRecOn with
  | ind j ih =>
      match j with
      | 0 => simp only [digitsAux, List.all_nil]
      | m + 1 =>
          rcases Nat.lt_or_ge (m + 1) 10 with h10 | h10
          · have h9 : m + 1 ≤ 9 := by omega
            simp only [digitsAux, if_pos h10, List.all_cons, List.all_nil,
              isDigit_digitChar h9]
            rfl
          · have h10' : ¬ (m + 1 < 10) := by omega
            have hpos : (0 : Nat) < 10 := by omega
            have hdiv : 0 < (m + 1) / 10 := Nat.div_pos h10 hpos
            have hlt : (m + 1) / 10 < m + 1 := by omega
            have hmlt : (m + 1) % 10 < 10 := Nat.mod_lt _ hpos
            have hm : (m + 1) % 10 ≤ 9 := by omega
            simp only [digitsAux, if_neg h10', List.all_append,
              List.all_cons, List.all_nil, ih _ hlt,
              isDigit_digitChar hm]
            rfl

private theorem digitsAux_len : ∀ j, 0 < j → 0 < (digitsAux j).length := by
  intro j
  induction j using Nat.strongRecOn with
  | ind j ih =>
      intro hj
      have hj1 : j ≠ 0 := by omega
      obtain ⟨m, rfl⟩ : ∃ m, j = m + 1 := ⟨j - 1, by omega⟩
      rcases Nat.lt_or_ge (m + 1) 10 with h10 | h10
      · simp only [digitsAux, if_pos h10, List.length_cons, List.length_nil]
        omega
      · have h10' : ¬ (m + 1 < 10) := by omega
        have hpos : (0 : Nat) < 10 := by omega
        have hdiv : 0 < (m + 1) / 10 := Nat.div_pos h10 hpos
        have hlt : (m + 1) / 10 < m + 1 := by omega
        have hlen := ih ((m + 1) / 10) hlt hdiv
        simp only [digitsAux, if_neg h10', List.length_append,
          List.length_cons, List.length_nil]
        omega

private theorem digitsAux_head (j : Nat) (hj : 0 < j) :
    ∃ c cs, digitsAux j = c :: cs ∧ isDigit c = true := by
  have hlen := digitsAux_len j hj
  have hall := digitsAux_all j
  obtain ⟨l, ls, heq⟩ := List.exists_cons_of_length_pos hlen
  rw [heq, List.all_cons, Bool.and_eq_true] at hall
  exact ⟨l, ls, heq, hall.1⟩

theorem parseNatAux_of (cs : List Char) (h1 : 0 < cs.length)
    (h2 : cs.all isDigit = true) :
    parseNatAux cs =
      some (cs.foldl (fun a c => a * 10 + digitVal c) 0) := by
  simp only [parseNatAux]
  rw [if_pos (by simp [h1, h2])]

theorem parseNatAux_natRepr {n : Nat} (hn : 0 < n) :
    parseNatAux (natRepr n) = some n := by
  have hval := digitsAux_val n n (Nat.le_refl n) hn
  have hall := digitsAux_all n
  have hlen := digitsAux_len n hn
  simp only [natRepr, if_pos hn]
  rw [parseNatAux_of (digitsAux n) hlen hall, hval]

theorem parseNatAux_zero : parseNatAux ['0'] = some 0 := by
  simp [parseNatAux, isDigit, digitVal]

theorem parseDec_intRepr (i : Int) : parseDec (intRepr i).toList = some i := by
  have hmk : ∀ (cs : List Char), (String.ofList cs).toList = cs := fun _ =>
    String.toList_ofList
  cases i with
  | ofNat n =>
      rcases Nat.eq_zero_or_pos n with rfl | hn
      · have h0 : (intRepr (Int.ofNat 0)).toList = ['0'] := rfl
        rw [h0, parseDec, parseNatAux_zero]
        intro rest h
        simp at h
      · obtain ⟨c, cs, heq, hcd⟩ := digitsAux_head n hn
        have hall : (digitsAux n).all isDigit = true := digitsAux_all n
        rw [heq, List.all_cons, Bool.and_eq_true] at hall
        simp only [intRepr, intChars, natRepr, if_pos hn, hmk, heq, parseDec]
        have hcne : c ≠ '-' := by
          intro h
          rw [h] at hcd
          simp [isDigit, digitVal] at hcd
        split
        · next heq' =>
            injection heq' with h1 _
            exact (hcne h1).elim
        · have hall' : (c :: cs).all isDigit = true := by
            simp only [List.all_cons, hcd, Bool.true_and]
            exact hall.2
          have hval := digitsAux_val n n (Nat.le_refl n) hn
          rw [heq] at hval
          rw [parseNatAux_of (c :: cs) (by simp) hall', hval]
  | negSucc n =>
      have hn : 0 < n + 1 := by omega
      simp only [intRepr, intChars, hmk, parseDec]
      rw [parseNatAux_natRepr hn]
      simp only [Option.some.injEq]
      omega


/-! ## JSON accessors (proof-friendly) -/

private theorem pairwise_keys_ne {l : List (String × Json)}
    (h : (l.map Prod.fst).Pairwise (fun a b => a ≠ b)) :
    l.Pairwise (fun a b => ¬ compare a.1 b.1 = .eq) := by
  induction l with
  | nil => simp
  | cons p ps ih =>
      simp only [List.map_cons, List.pairwise_cons] at h ⊢
      refine ⟨?_, ih h.2⟩
      intro q hq hcmp
      exact h.1 q.1 (List.mem_map_of_mem hq) (LawfulEqCmp.eq_of_compare hcmp)

/-- Master access lemma: looking up a present key in an object built from a
key-distinct assoc list yields exactly that value. -/
theorem getObjVal?_mkObj {l : List (String × Json)} {k : String} {v : Json}
    (hkeys : (l.map Prod.fst).Pairwise (fun a b => a ≠ b))
    (hm : (k, v) ∈ l) :
    (Json.mkObj l).getObjVal? k = Except.ok v := by
  have hp := pairwise_keys_ne hkeys
  have hget := Std.TreeMap.Raw.getElem?_ofList_of_mem (k_eq := compare_self) hp hm
  have hget' : (Std.TreeMap.Raw.ofList l compare).get? k = some v := hget
  simp only [Json.mkObj, Json.getObjVal?, hget']
  rfl

private theorem mem_dec {k : String} {v : Json} {l : List (String × Json)} :
    (k, v) ∈ l → (k : String) ∈ l.map Prod.fst := by
  intro h
  exact List.mem_map_of_mem (f := Prod.fst) h

/-- Option encoders (`none` is JSON `null`). -/
def optStr : Option String → Json
  | none => .null
  | some s => .str s

def optNat : Option Nat → Json
  | none => .null
  | some n => .num n

def optJson : Option Json → Json
  | none => .null
  | some j => j

def strsJson (xs : List String) : List Json := xs.map Json.str

/-- Field accessors returning `Dec`. -/
def jStr (j : Json) (k : String) : Dec String :=
  match j.getObjVal? k with
  | .ok (.str s) => .ok s
  | _ => derr s!"field {k}: string expected"

def jOptStr (j : Json) (k : String) : Dec (Option String) :=
  match j.getObjVal? k with
  | .ok .null => .ok none
  | .ok (.str s) => .ok (some s)
  | _ => derr s!"field {k}: string or null expected"

def jNat (j : Json) (k : String) : Dec Nat :=
  match j.getObjVal? k with
  | .ok (.num ⟨m, 0⟩) => if h : 0 ≤ m then .ok m.toNat else derr s!"field {k}: natural expected"
  | _ => derr s!"field {k}: natural expected"

def jOptNat (j : Json) (k : String) : Dec (Option Nat) :=
  match j.getObjVal? k with
  | .ok .null => .ok none
  | .ok (.num ⟨m, 0⟩) => if h : 0 ≤ m then .ok (some m.toNat) else derr s!"field {k}: natural or null expected"
  | _ => derr s!"field {k}: natural or null expected"

def jBool (j : Json) (k : String) : Dec Bool :=
  match j.getObjVal? k with
  | .ok (.bool b) => .ok b
  | _ => derr s!"field {k}: bool expected"

def jField (j : Json) (k : String) : Dec Json :=
  match j.getObjVal? k with
  | .ok v => .ok v
  | .error e => .error ⟨e⟩

def jOptField (j : Json) (k : String) : Dec (Option Json) :=
  match j.getObjVal? k with
  | .ok .null => .ok none
  | .ok v => .ok (some v)
  | .error e => .error ⟨e⟩

/-- `jOptField` resolves on a `mkObj` field whose value is non-null.  (A
JSON `null` encodes `none`; options whose `some` payload may itself be
`null` use key omission instead.) -/
theorem jOptField_mkObj {l : List (String × Json)} {k : String} {v : Json}
    (hkeys : (l.map Prod.fst).Pairwise (fun a b => a ≠ b))
    (hne : v ≠ Json.null)
    (hm : (k, v) ∈ l) : jOptField (Json.mkObj l) k = Except.ok (some v) := by
  have hget : (Json.mkObj l).getObjVal? k = Except.ok v := getObjVal?_mkObj hkeys hm
  simp only [jOptField, hget]

/-! ## Value sizes (public counterparts of the private measures in `Core.Value`) -/

mutual
  def sizeV : Value → Nat
    | .vint _ | .vbool _ | .vstr _ | .vunserializable _ | .vnull => 1
    | .vset xs | .vseq xs | .vtuple xs => 1 + sizeL xs
    | .vrecord m | .vmap m => 1 + sizeM m
    | .vvariant _ v => 1 + sizeV v

  def sizeL : List Value → Nat
    | [] => 0
    | v :: vs => sizeV v + 1 + sizeL vs

  def sizeM : ValueMap → Nat
    | [] => 0
    | (_, v) :: ms => sizeV v + 1 + sizeM ms
end

theorem sizeL_cons (v : Value) (vs : List Value) :
    sizeL (v :: vs) = sizeV v + 1 + sizeL vs := rfl
theorem sizeM_cons (k : String) (v : Value) (m : ValueMap) :
    sizeM ((k, v) :: m) = sizeV v + 1 + sizeM m := rfl

theorem sizeV_pos (v : Value) : 0 < sizeV v := by
  cases v <;> simp only [sizeV, sizeL, sizeM] <;> omega

theorem sizeV_mem {v : Value} {xs : List Value} (h : v ∈ xs) : sizeV v < sizeL xs := by
  induction xs with
  | nil => cases h
  | cons a as ih =>
      rw [sizeL_cons]
      rcases List.mem_cons.mp h with h | h
      · rw [h]; have := sizeV_pos v; omega
      · have := ih h; omega

theorem sizeV_mem_map {k : String} {v : Value} {m : ValueMap} (h : (k, v) ∈ m) :
    sizeV v < sizeM m := by
  induction m with
  | nil => cases h
  | cons p ps ih =>
      obtain ⟨k', v'⟩ := p
      rcases List.mem_cons.mp h with h | h
      · rw [Prod.mk.injEq] at h; obtain ⟨rfl, rfl⟩ := h
        rw [sizeM_cons]; have := sizeV_pos v; omega
      · rw [sizeM_cons]; have := ih h; omega
/-! ## TreeMap bridges for `ofList` -/

theorem ofList_wf (l : List (String × Json)) :
    (Std.TreeMap.Raw.ofList l compare).WF :=
  Std.TreeMap.Raw.WF.ofList

private theorem pairwise_ne_keys {l : List (String × Json)}
    (h : (l.map Prod.fst).Pairwise (fun a b => a ≠ b)) :
    l.Pairwise (fun a b => ¬ compare a.1 b.1 = .eq) := pairwise_keys_ne h

theorem toList_ofList_mem {l : List (String × Json)} {p : String × Json}
    (hkeys : (l.map Prod.fst).Pairwise (fun a b => a ≠ b)) (hm : p ∈ l) :
    p ∈ (Std.TreeMap.Raw.ofList l compare).toList := by
  rw [Std.TreeMap.Raw.mem_toList_iff_getElem?_eq_some (ofList_wf l)]
  have := Std.TreeMap.Raw.getElem?_ofList_of_mem (k_eq := compare_self)
    (pairwise_ne_keys hkeys) hm
  exact this

theorem toList_ofList_length {l : List (String × Json)}
    (hkeys : (l.map Prod.fst).Pairwise (fun a b => a ≠ b)) :
    (Std.TreeMap.Raw.ofList l compare).toList.length = l.length := by
  have := Std.TreeMap.Raw.size_ofList (pairwise_ne_keys hkeys)
  have h2 := Std.TreeMap.Raw.length_toList (ofList_wf l)
  omega

private theorem len_one {α} {l : List α} (hl : l.length = 1) : ∃ a, l = [a] := by
  cases l with
  | cons a l =>
      cases l with
      | cons b l => simp at hl
      | nil => exact ⟨a, rfl⟩
  | nil => simp at hl

theorem toList_ofList_singleton {k : String} {v : Json} :
    (Std.TreeMap.Raw.ofList [(k, v)] compare).toList = [(k, v)] := by
  have hm : (k, v) ∈ (Std.TreeMap.Raw.ofList [(k, v)] compare).toList :=
    toList_ofList_mem (by simp [List.pairwise_cons]) (by simp)
  have hl := toList_ofList_length (l := [(k, v)]) (by simp [List.pairwise_cons])
  obtain ⟨e, he⟩ := len_one hl
  rw [he] at hm ⊢
  simp only [List.mem_singleton, Prod.mk.injEq] at hm
  obtain ⟨rfl, rfl⟩ := hm
  rfl

private theorem len_two {α} {l : List α} (hl : l.length = 2) : ∃ a b, l = [a, b] := by
  cases l with
  | cons a l =>
      cases l with
      | cons b l =>
          cases l with
          | cons c l => simp at hl
          | nil => exact ⟨a, b, rfl⟩
      | nil => simp at hl
  | nil => simp at hl

private theorem two_mem_two {α} {l : List α} {p q : α}
    (hl : l.length = 2) (hp : p ∈ l) (hq : q ∈ l) (hne : p ≠ q) :
    l = [p, q] ∨ l = [q, p] := by
  obtain ⟨a, b, rfl⟩ := len_two hl
  by_cases hap : a = p
  · subst hap
    rcases List.mem_cons.mp hq with h' | h'
    · exact absurd h'.symm hne
    · simp only [List.mem_singleton] at h'
      rw [h']
      exact Or.inl rfl
  · rcases List.mem_cons.mp hq with hq' | hq'
    · subst hq'
      rcases List.mem_cons.mp hp with h' | h'
      · exact absurd h'.symm hap
      · simp only [List.mem_singleton] at h'
        rw [h']
        exact Or.inr rfl
    · exfalso
      have hpm : p ∈ [b] := by
        rcases List.mem_cons.mp hp with h' | h'
        · exact absurd h'.symm hap
        · exact h'
      simp only [List.mem_singleton] at hpm hq'
      exact hne (hpm ▸ hq'.symm)

theorem toList_ofList_pair {k1 : String} {v1 : Json} {k2 : String} {v2 : Json}
    (hne : k1 ≠ k2) :
    (Std.TreeMap.Raw.ofList [(k1, v1), (k2, v2)] compare).toList = [(k1, v1), (k2, v2)]
      ∨ (Std.TreeMap.Raw.ofList [(k1, v1), (k2, v2)] compare).toList = [(k2, v2), (k1, v1)] := by
  have hkeys : ([(k1, v1), (k2, v2)].map Prod.fst).Pairwise (fun a b => a ≠ b) := by
    simp [List.pairwise_cons, hne]
  have h1 := toList_ofList_mem (p := (k1, v1)) hkeys (by simp)
  have h2 := toList_ofList_mem (p := (k2, v2)) hkeys (by simp)
  have hl := toList_ofList_length hkeys
  have hne' : (k1, v1) ≠ (k2, v2) := by
    intro h; rw [Prod.mk.injEq] at h; exact hne h.1
  exact two_mem_two hl h1 h2 hne'

/-! ## Wire well-formedness -/

/-- Keys that the ITF wire encoding reserves for tagged values. -/
def reservedKey : String → Bool
  | "#bigint" | "#set" | "#tup" | "#map" | "#unserializable" | "tag" | "value" => true
  | _ => false

mutual
  /-- Well-formedness for the wire encoding: record and map keys are pairwise
  distinct, unreserved, and the property holds recursively. -/
  def wireOk : Value → Bool
    | .vint _ | .vbool _ | .vstr _ | .vunserializable _ | .vnull => true
    | .vset xs | .vseq xs | .vtuple xs => wireOkList xs
    | .vvariant _ v => wireOk v
    | .vrecord m | .vmap m => wireOkMap m

  def wireOkList : List Value → Bool
    | [] => true
    | v :: vs => wireOk v && wireOkList vs

  def wireOkMap : ValueMap → Bool
    | [] => true
    | (k, v) :: ms =>
        (!reservedKey k && !(k ∈ ms.map Prod.fst)) && (wireOk v && wireOkMap ms)
end

theorem wireOkList_of_forall {xs : List Value}
    (h : ∀ v ∈ xs, wireOk v = true) : wireOkList xs = true := by
  induction xs with
  | nil => rfl
  | cons x xs ih =>
      simp only [wireOkList, h x (List.mem_cons_self), Bool.and_true]
      exact ih (fun v hv => h v (List.mem_cons_of_mem _ hv))

/-! ## Encoding of values (§5.2) -/

mutual
  def encValue : Value → Json
    | .vint i => Json.mkObj [("#bigint", Json.str (intRepr i))]
    | .vbool b => Json.bool b
    | .vstr s => Json.str s
    | .vset xs => Json.mkObj [("#set", Json.arr (encList xs).toArray)]
    | .vseq xs => Json.arr (encList xs).toArray
    | .vtuple xs => Json.mkObj [("#tup", Json.arr (encList xs).toArray)]
    | .vrecord m => Json.mkObj (encMap m)
    | .vmap m => Json.mkObj [("#map", Json.arr (encPairs m).toArray)]
    | .vvariant t v => Json.mkObj [("tag", Json.str t), ("value", encValue v)]
    | .vunserializable s => Json.mkObj [("#unserializable", Json.str s)]
    | .vnull => Json.null
  termination_by v => sizeV v
  decreasing_by
    all_goals
      first
      | rfl
      | (simp only [sizeV, sizeL_cons, sizeM_cons]; omega)

  def encList : List Value → List Json
    | [] => []
    | v :: vs => encValue v :: encList vs
  termination_by xs => sizeL xs
  decreasing_by
    all_goals
      first
      | rfl
      | (simp only [sizeV, sizeL_cons, sizeM_cons]; omega)

  def encMap : ValueMap → List (String × Json)
    | [] => []
    | (k, v) :: ms => (k, encValue v) :: encMap ms
  termination_by m => sizeM m
  decreasing_by
    all_goals
      first
      | rfl
      | (simp only [sizeV, sizeL_cons, sizeM_cons]; omega)

  def encPairs : ValueMap → List Json
    | [] => []
    | (k, v) :: ms => Json.arr #[Json.str k, encValue v] :: encPairs ms
  termination_by m => sizeM m
  decreasing_by
    all_goals
      first
      | rfl
      | (simp only [sizeV, sizeL_cons, sizeM_cons]; omega)
end

/-! ## Decoding of values (§5.2)

Decoding recurses over the JSON structure, which Lean 4.33 cannot measure
(`Lean.Json` objects hide a `TreeMap` whose `sizeOf` is opaque), so the
recursion is bounded by an explicit fuel parameter.  The fuel bounds the
nesting depth; `defaultFuel` covers any realistic message. -/

/-- Default fuel: an astronomically large depth bound. -/
def defaultFuel : Nat := 4294967296

private def optVal (k : String) (dw : Dec Value) : Dec (String × Value) :=
  match dw with
  | .ok w => .ok (k, w)
  | .error e => .error e

private def optPair (k : String) (dw : Dec Value)
    (dms : Dec (List (String × Value))) : Dec (List (String × Value)) :=
  match dw, dms with
  | .ok w, .ok es => .ok ((k, w) :: es)
  | .error e, _ => .error e
  | .ok _, .error e => .error e

mutual
/-- Fuel-bounded decoding of an ITF value from a JSON tree. -/
def decValueF : Nat → Json → Dec Value
  | 0, _ => derr "value: nesting too deep"
  | fu+1, .null => .ok .vnull
  | fu+1, .bool b => .ok (.vbool b)
  | fu+1, .str s => .ok (.vstr s)
  | fu+1, .num n =>
      -- Haskell's @FromJSON Value@ accepts bare JSON numbers as @VInt@
      -- (its own @ToJSON@ always emits @#bigint@, but real clients send
      -- bare numbers in report_state). A @Lean.JsonNumber@ is
      -- @mantissa * 10 ^ (-exponent)@ with @exponent : Nat@, and the
      -- Haskell instance accepts exactly the numbers whose value is
      -- integral, so accept iff the mantissa is divisible by
      -- @10 ^ exponent@; the result is the integral quotient.
      if n.mantissa % ((10 : Nat) ^ n.exponent : Int) = 0 then
        .ok (.vint (n.mantissa / ((10 : Nat) ^ n.exponent : Int)))
      else derr "value: bare JSON number not in ITF grammar"
  | fu+1, .arr as =>
      match (as.toList.mapM (decValueF fu) : Dec (List Value)) with
      | .ok ws => .ok (.vseq ws)
      | .error e => .error e
  | fu+1, .obj kvs =>
      match kvs.toList with
      | [("#bigint", Json.str s)] =>
          match parseDec s.toList with
          | some i => .ok (.vint i)
          | none => derr "value: malformed #bigint"
      | [("#set", Json.arr as)] =>
          match (as.toList.mapM (decValueF fu) : Dec (List Value)) with
          | .ok ws => .ok (.vset ws)
          | .error e => .error e
      | [("#tup", Json.arr as)] =>
          match (as.toList.mapM (decValueF fu) : Dec (List Value)) with
          | .ok ws => .ok (.vtuple ws)
          | .error e => .error e
      | [("#unserializable", Json.str s)] => .ok (.vunserializable s)
      | [("#map", Json.arr as)] =>
          match (as.toList.mapM (fun j =>
              match j with
              | Json.arr a =>
                  match a.toList with
                  | [Json.str k, jv] => optVal k (decValueF fu jv)
                  | _ => derr "value: malformed #map entry"
              | _ => derr "value: malformed #map entry") : Dec (List (String × Value))) with
          | .ok es => .ok (.vmap es)
          | .error e => .error e
      | [e1, e2] =>
          if e1.1 == "tag" && e2.1 == "value" then
            match e1.2, e2.2 with
            | Json.str t, jv => (.vvariant t) <$> decValueF fu jv
            | _, _ => derr "value: malformed variant"
          else if e1.1 == "value" && e2.1 == "tag" then
            match e1.2, e2.2 with
            | jv, Json.str t => (.vvariant t) <$> decValueF fu jv
            | _, _ => derr "value: malformed variant"
          else
            match (decRecordF fu [e1, e2] : Dec ValueMap) with
            | .ok es => .ok (.vrecord es)
            | .error e => .error e
      | es =>
          match (decRecordF fu es : Dec ValueMap) with
          | .ok es => .ok (.vrecord es)
          | .error e => .error e
termination_by fu _ => (fu, 0)
decreasing_by
  all_goals
    first
    | (simp only [List.length_cons]; omega)
    | apply Prod.Lex.left; omega
    | apply Prod.Lex.right; omega

/-- Fuel-bounded decoding of an object into an ITF record. -/
def decRecordF : Nat → List (String × Json) → Dec ValueMap
  | _, [] => .ok []
  | 0, _ :: _ => derr "value: nesting too deep"
  | fu+1, (k, jv) :: es => optPair k (decValueF fu jv) (decRecordF (fu+1) es)
termination_by fu es => (fu, es.length + 1)
decreasing_by
  all_goals
    first
    | (simp only [List.length_cons]; omega)
    | apply Prod.Lex.left; omega
    | apply Prod.Lex.right; omega
end

/-- Public decoder for embedded values. -/
def decodeValue (j : Json) : Dec Value := decValueF defaultFuel j
/-! ### Fuel-parameterized round-trip statement -/

/-- "Encoding of `v` decodes back at any fuel `F ≥ 2·(size bound) + 4`". -/
def encOkAt (n : Nat) (v : Value) : Prop :=
  ∀ F, 2 * n + 4 ≤ F → ∃ w, decValueF F (encValue v) = Except.ok w ∧ valEq v w = true

/-! ### `wireOk` consequences -/

theorem wireOkMap_mem {m : ValueMap} (h : wireOkMap m = true) {k : String} {v : Value}
    (hm : (k, v) ∈ m) : wireOk v = true := by
  induction m with
  | nil => cases hm
  | cons p ps ih =>
      obtain ⟨k', v'⟩ := p
      simp only [wireOkMap, Bool.and_eq_true, Bool.not_eq_true', decide_eq_false_iff_not] at h
      rcases List.mem_cons.mp hm with hm | hm
      · rw [Prod.mk.injEq] at hm; obtain ⟨rfl, rfl⟩ := hm
        exact h.2.1
      · exact ih h.2.2 hm

theorem wireOkMap_mem_key {m : ValueMap} (h : wireOkMap m = true) {k : String} {v : Value}
    (hm : (k, v) ∈ m) : reservedKey k = false := by
  induction m with
  | nil => cases hm
  | cons p ps ih =>
      obtain ⟨k', v'⟩ := p
      simp only [wireOkMap, Bool.and_eq_true, Bool.not_eq_true', decide_eq_false_iff_not] at h
      rcases List.mem_cons.mp hm with hm | hm
      · rw [Prod.mk.injEq] at hm; obtain ⟨rfl, rfl⟩ := hm
        simpa using h.1.1
      · exact ih h.2.2 hm

theorem wireOkMap_pairwise {m : ValueMap} (h : wireOkMap m = true) :
    (m.map Prod.fst).Pairwise (fun a b => a ≠ b) := by
  induction m with
  | nil => simp
  | cons p ps ih =>
      obtain ⟨k', v'⟩ := p
      simp only [wireOkMap, Bool.and_eq_true, Bool.not_eq_true', decide_eq_false_iff_not] at h
      refine List.pairwise_cons.mpr ⟨?_, ih h.2.2⟩
      intro k hk heq
      have hk' : k' ∈ ps.map Prod.fst := by
        rcases List.mem_map.mp hk with ⟨p', hp, hpf⟩
        exact List.mem_map.mpr ⟨(k', p'.2), by
          rw [show k' = p'.1 from heq.trans hpf.symm]; exact hp, rfl⟩
      exact h.1.2 hk'

theorem mem_key_unique {m : ValueMap} (hkeys : (m.map Prod.fst).Pairwise (fun a b => a ≠ b))
    {k : String} {v v' : Value} (h1 : (k, v) ∈ m) (h2 : (k, v') ∈ m) : v = v' := by
  induction m with
  | nil => cases h1
  | cons p ps ih =>
      obtain ⟨k'', w⟩ := p
      simp only [List.map_cons, List.pairwise_cons] at hkeys
      rcases List.mem_cons.mp h1 with h1 | h1
      · rw [Prod.mk.injEq] at h1; obtain ⟨hk1, hv1⟩ := h1; subst hk1; subst hv1
        rcases List.mem_cons.mp h2 with h2 | h2
        · rw [Prod.mk.injEq] at h2; obtain ⟨_, hv2⟩ := h2; exact hv2.symm
        · exact absurd (hkeys.1 k (List.mem_map_of_mem h2) rfl) (by simp)
      · rcases List.mem_cons.mp h2 with h2 | h2
        · rw [Prod.mk.injEq] at h2; obtain ⟨hk2, hv2⟩ := h2; subst hk2; subst hv2
          rcases List.mem_cons.mp h1 with h1' | h1'
          · rw [Prod.mk.injEq] at h1'; obtain ⟨_, hv1'⟩ := h1'; exact hv1'
          · exact absurd (hkeys.1 k (List.mem_map_of_mem h1' ) rfl) (by simp)
        · exact ih hkeys.2 h1 h2

theorem wireOk_of_list {xs : List Value} (h : wireOkList xs = true) :
    ∀ x ∈ xs, wireOk x = true := by
  intro x hx
  induction xs with
  | nil => cases hx
  | cons a as ih =>
      simp only [wireOkList, Bool.and_eq_true] at h
      rcases List.mem_cons.mp hx with hx | hx
      · rw [hx]; exact h.1
      · exact ih h.2 hx

/-! ### Container bridges -/

theorem listEq_mem {xs : List Value} :
    ∀ (ws : List Value), listEq xs ws = true →
      ∀ x, x ∈ xs → ∃ w, w ∈ ws ∧ valEq x w = true := by
  induction xs with
  | nil => intro _ _ x hx; exact absurd hx (by simp)
  | cons x xr ih =>
      intro ws h y hy
      cases ws with
      | nil => simp [listEq] at h
      | cons w wr =>
          rw [listEq, Bool.and_eq_true] at h
          rcases List.mem_cons.mp hy with hy | hy
          · rw [hy]; exact ⟨w, by simp, h.1⟩
          · obtain ⟨w', hw', hval⟩ := ih wr h.2 y hy
            exact ⟨w', by simp [hw'], hval⟩

theorem listEq_mem_rev {xs : List Value} :
    ∀ (ws : List Value), listEq xs ws = true →
      ∀ w, w ∈ ws → ∃ x, x ∈ xs ∧ valEq w x = true := by
  induction xs with
  | nil =>
      intro ws h w hw
      cases ws with
      | nil => exact absurd hw (by simp)
      | cons _ _ => simp [listEq] at h
  | cons x xr ih =>
      intro ws h y hy
      cases ws with
      | nil => simp [listEq] at h
      | cons w wr =>
          rw [listEq, Bool.and_eq_true] at h
          rcases List.mem_cons.mp hy with hy | hy
          · rw [hy]
            exact ⟨x, by simp, valEq_symm _ _ h.1⟩
          · obtain ⟨x', hx', hval⟩ := ih wr h.2 y hy
            exact ⟨x', by simp [hx'], hval⟩

theorem listEq_setCont {xs ws : List Value} (h : listEq xs ws = true) :
    setCont xs ws = true :=
  setCont_iff xs ws |>.mpr (fun x hx =>
    let ⟨w, hw, hval⟩ := listEq_mem ws h x hx
    ⟨w, hw, hval⟩)

theorem listEq_setCont_rev {xs ws : List Value} (h : listEq xs ws = true) :
    setCont ws xs = true :=
  setCont_iff ws xs |>.mpr (fun w hw =>
    let ⟨x, hx, hval⟩ := listEq_mem_rev ws h w hw
    ⟨x, hx, hval⟩)

private theorem arrPair_toList (k : String) (jv : Json) :
    (#[Json.str k, jv] : Array Json).toList = [Json.str k, jv] := rfl

/-! ### Decoding soundness for lists and maps -/

private theorem mapM_cons_ok {α β : Type} {f : α → Dec β} {a : α} {l : List α}
    {b : β} {bs : List β}
    (ha : f a = Except.ok b) (hl : List.mapM f l = Except.ok bs) :
    List.mapM f (a :: l) = Except.ok (b :: bs) := by
  rw [List.mapM_cons, ha, hl]
  rfl

private theorem entryDec_ok (k : String) (jv : Json) (fu : Nat) :
    (fun j =>
        match j with
        | Json.arr a =>
            match a.toList with
            | [Json.str k, jv] => optVal k (decValueF fu jv)
            | _ => derr "value: malformed #map entry"
        | _ => derr "value: malformed #map entry") (Json.arr #[Json.str k, jv])
      = optVal k (decValueF fu jv) := rfl

theorem decList_mapM_ok {n : Nat} : ∀ (xs : List Value) (F : Nat), 2 * n + 4 ≤ F →
    wireOkList xs = true → (∀ x ∈ xs, sizeV x ≤ n) →
    (∀ v, wireOk v = true → sizeV v ≤ n → encOkAt n v) →
    ∃ ws, (encList xs).mapM (decValueF F) = Except.ok ws ∧
      listEq xs ws = true := by
  intro xs
  induction xs with
  | nil =>
      intro F _ _ _ _
      refine ⟨[], ?_, by simp [listEq]⟩
      rw [show encList [] = [] from by simp [encList], List.mapM_nil]
      rfl
  | cons x xs ihx =>
      intro F hF hwok hsz ih
      simp only [wireOkList, Bool.and_eq_true] at hwok
      obtain ⟨w, hw, hval⟩ := ih x hwok.1 (hsz x (by simp)) F hF
      obtain ⟨ws, hmap, hlist⟩ := ihx F hF hwok.2
        (fun v hv => hsz v (List.mem_cons_of_mem _ hv)) ih
      refine ⟨w :: ws, ?_, ?_⟩
      · simp only [encList, List.map_cons]
        exact mapM_cons_ok hw hmap
      · simp only [listEq, hval, hlist, Bool.and_true]

theorem decPairs_mapM_ok {n : Nat} : ∀ (m : ValueMap) (F : Nat), 2 * n + 4 ≤ F →
    wireOkMap m = true → (∀ k v, (k, v) ∈ m → sizeV v ≤ n) →
    (∀ v, wireOk v = true → sizeV v ≤ n → encOkAt n v) →
    ∃ ws, (encPairs m).mapM (fun j =>
        match j with
        | Json.arr a =>
            match a.toList with
            | [Json.str k, jv] => optVal k (decValueF F jv)
            | _ => derr "value: malformed #map entry"
        | _ => derr "value: malformed #map entry") = Except.ok ws ∧
      (∀ k v, (k, v) ∈ m → ∃ w, (k, w) ∈ ws ∧ valEq v w = true) ∧
      (∀ k w, (k, w) ∈ ws → ∃ v, (k, v) ∈ m ∧ valEq v w = true) := by
  intro m
  induction m with
  | nil =>
      intro F _ _ _ _
      refine ⟨[], ?_, by simp, by simp⟩
      rw [show encPairs [] = [] from by simp [encPairs], List.mapM_nil]
      rfl
  | cons p ps ihm =>
      intro F hF hwok hsz ih
      obtain ⟨k, v⟩ := p
      simp only [wireOkMap, Bool.and_eq_true, Bool.not_eq_true', decide_eq_false_iff_not] at hwok
      obtain ⟨w, hw, hval⟩ := ih v hwok.2.1 (hsz k v (by simp)) F hF
      obtain ⟨ws, hmap, hd1, hd2⟩ :=
        ihm F hF hwok.2.2 (fun k' v' hv' => hsz k' v' (List.mem_cons_of_mem _ hv')) ih
      refine ⟨(k, w) :: ws, ?_, ?_, ?_⟩
      · rw [show encPairs ((k, v) :: ps) =
          Json.arr #[Json.str k, encValue v] :: encPairs ps from by simp [encPairs]]
        rw [List.mapM_cons]
        simp only [entryDec_ok, hw, hmap]
        rfl
      · intro k' v' hv'
        rcases List.mem_cons.mp hv' with hv' | hv'
        · rw [Prod.mk.injEq] at hv'; obtain ⟨rfl, rfl⟩ := hv'
          exact ⟨w, List.mem_cons_self, hval⟩
        · obtain ⟨w2, hw2, hval2⟩ := hd1 k' v' hv'
          exact ⟨w2, List.mem_cons_of_mem _ hw2, hval2⟩
      · intro k' w' hw'
        rcases List.mem_cons.mp hw' with hw' | hw'
        · rw [Prod.mk.injEq] at hw'; obtain ⟨rfl, rfl⟩ := hw'
          exact ⟨v, List.mem_cons_self, hval⟩
        · obtain ⟨v2, hv2, hval2⟩ := hd2 k' w' hw'
          exact ⟨v2, List.mem_cons_of_mem _ hv2, hval2⟩

theorem decRecordF_ok {n : Nat} {m : ValueMap} :
    ∀ (es : List (String × Json)) (F : Nat), 2 * n + 5 ≤ F →
    (∀ k j, (k, j) ∈ es → ∃ v, (k, v) ∈ m ∧ encValue v = j) →
    wireOkMap m = true →
    (∀ v, wireOk v = true → sizeV v ≤ n → encOkAt n v) →
    (∀ k v, (k, v) ∈ m → sizeV v ≤ n) →
    ∃ ws, decRecordF F es = Except.ok ws ∧
      (∀ k w, (k, w) ∈ ws → ∃ v, (k, v) ∈ m ∧ valEq v w = true) ∧
      (∀ k j, (k, j) ∈ es → ∃ w, (k, w) ∈ ws ∧
        ∃ v, (k, v) ∈ m ∧ encValue v = j ∧ valEq v w = true) := by
  intro es
  induction es with
  | nil =>
      intro F hF _ _ _ _
      refine ⟨[], ?_, by simp, by simp⟩
      cases F with
      | zero => omega
      | succ F' => simp only [decRecordF]
  | cons e es' ihes =>
      intro F hF hd2 hwokm ich hsz
      obtain ⟨k, j⟩ := e
      obtain ⟨v, hv, hej⟩ := hd2 k j (by simp)
      rcases F with _ | F'
      · omega
      · obtain ⟨w, hw, hval⟩ :=
          ich v (wireOkMap_mem hwokm hv) (hsz k v hv) F' (by omega)
        obtain ⟨ws, hrec, hd2w, hd1w⟩ :=
          ihes (F'+1) (by omega)
            (fun k' j' hj' => hd2 k' j' (List.mem_cons_of_mem _ hj')) hwokm ich hsz
        refine ⟨(k, w) :: ws, ?_, ?_, ?_⟩
        · rw [← hej]
          simp only [decRecordF, optPair, hw, hrec]
        · intro k' w' hw'
          rcases List.mem_cons.mp hw' with hw' | hw'
          · rw [Prod.mk.injEq] at hw'; obtain ⟨rfl, rfl⟩ := hw'
            exact ⟨v, hv, hval⟩
          · obtain ⟨v2, hv2, hval2⟩ := hd2w k' w' hw'
            exact ⟨v2, hv2, hval2⟩
        · intro k' j' hj'
          rcases List.mem_cons.mp hj' with hj' | hj'
          · rw [Prod.mk.injEq] at hj'; obtain ⟨rfl, rfl⟩ := hj'
            exact ⟨w, List.mem_cons_self, v, hv, hej, hval⟩
          · obtain ⟨w', hw'', hv', hej', hval'⟩ := hd1w k' j' hj'
            exact ⟨w', List.mem_cons_of_mem _ hw'', hv', hej', hval'⟩
/-! ### encMap bridges -/

theorem encMap_keys (m : ValueMap) : (encMap m).map Prod.fst = m.map Prod.fst := by
  induction m with
  | nil => simp [encMap]
  | cons p ps ih =>
      obtain ⟨k, v⟩ := p
      simp only [encMap, List.map_cons, ih]

theorem encMap_length (m : ValueMap) : (encMap m).length = m.length := by
  induction m with
  | nil => simp [encMap]
  | cons p ps ih =>
      obtain ⟨k, v⟩ := p
      simp only [encMap, List.length_cons, ih]

theorem encMap_mem {m : ValueMap} {k : String} {v : Value} (h : (k, v) ∈ m) :
    (k, encValue v) ∈ encMap m := by
  induction m with
  | nil => cases h
  | cons p ps ih =>
      obtain ⟨k, v⟩ := p
      simp only [encMap, List.mem_cons]
      rcases List.mem_cons.mp h with h | h
      · rw [Prod.mk.injEq] at h; obtain ⟨rfl, rfl⟩ := h; exact Or.inl rfl
      · exact Or.inr (ih h)

theorem encMap_keys_mem {m : ValueMap} {k : String}
    (h : k ∈ (encMap m).map Prod.fst) : ∃ v, (k, v) ∈ m := by
  induction m with
  | nil =>
      have hnil : (encMap []).map Prod.fst = [] := by simp [encMap]
      rw [hnil] at h
      exact absurd h List.not_mem_nil
  | cons p ps ih =>
      obtain ⟨k', v'⟩ := p
      simp only [encMap, List.map_cons] at h
      rcases List.mem_cons.mp h with h | h
      · rw [← h]; exact ⟨v', List.mem_cons_self⟩
      · obtain ⟨v, hv⟩ := ih h
        exact ⟨v, List.mem_cons_of_mem _ hv⟩

/-! ### Record entries bridges -/

private theorem recordBridges {m : ValueMap} (hwokm : wireOkMap m = true) :
    (Std.TreeMap.Raw.ofList (encMap m) compare).toList.length = m.length ∧
    (∀ k v, (k, v) ∈ m → (k, encValue v) ∈ (Std.TreeMap.Raw.ofList (encMap m) compare).toList) ∧
    (∀ k j, (k, j) ∈ (Std.TreeMap.Raw.ofList (encMap m) compare).toList →
      ∃ v, (k, v) ∈ m ∧ encValue v = j) := by
  have hpw : ((encMap m).map Prod.fst).Pairwise (fun a b => a ≠ b) := by
    rw [encMap_keys]; exact wireOkMap_pairwise hwokm
  refine ⟨?_, ?_, ?_⟩
  · have h1 := Std.TreeMap.Raw.size_ofList (pairwise_ne_keys hpw)
    have h2 := Std.TreeMap.Raw.length_toList (ofList_wf (encMap m))
    have h3 := encMap_length m
    omega
  · intro k v h
    exact toList_ofList_mem hpw (encMap_mem h)
  · intro k j h
    rw [Std.TreeMap.Raw.mem_toList_iff_getElem?_eq_some (ofList_wf _)] at h
    have hkey : k ∈ (encMap m).map Prod.fst := by
      refine Classical.byContradiction fun hk => ?_
      have hnone : (Std.TreeMap.Raw.ofList (encMap m) compare)[k]? = none :=
        Std.TreeMap.Raw.getElem?_ofList_of_contains_eq_false
          (contains_eq_false := by simp [hk])
      rw [hnone] at h
      exact absurd h (by simp)
    obtain ⟨v, hv⟩ := encMap_keys_mem hkey
    rw [Std.TreeMap.Raw.getElem?_ofList_of_mem (k_eq := compare_self)
      (pairwise_ne_keys (by rw [encMap_keys]; exact wireOkMap_pairwise hwokm))
      (encMap_mem hv)] at h
    refine ⟨v, hv, ?_⟩
    exact (Option.some.injEq _ _).mp h

/-! ## §6.6: value round-trip -/

/-- Bare integral JSON numbers decode as @.vint@ (decode parity with
Haskell's @FromJSON Value@; encoding still emits the @#bigint@ form, so
§6.6 round-trips are unaffected). -/
theorem decValueF_num_integral (fu : Nat) (m : Int) (e : Nat)
    (hd : m % ((10 : Nat) ^ e : Int) = 0) :
    decValueF (fu+1) (Json.num (JsonNumber.mk m e))
      = Except.ok (.vint (m / ((10 : Nat) ^ e : Int))) := by
  simp only [decValueF, if_pos hd]

theorem decValueF_num (fu : Nat) (m : Int) :
    decValueF (fu+1) (Json.num (JsonNumber.mk m 0)) = Except.ok (.vint m) := by
  simpa using decValueF_num_integral fu m 0 (by simp)

/-- **Value round-trip (§6.6)**: for any wire-ok value `v` and any fuel
`F ≥ 2 · (size bound) + 4`, decoding what was encoded from `v` succeeds
with an equal value. -/
theorem decValueF_encValue :
    ∀ (n : Nat) (v : Value), wireOk v = true → sizeV v ≤ n → encOkAt n v := by
  intro n
  induction n with
  | zero => intro v _ hv; exact absurd (sizeV_pos v) (by omega)
  | succ n ih =>
    intro v hw hv F hF
    rcases F with _ | F'
    · omega
    · cases v with
      | vint i =>
          refine ⟨.vint i, ?_, by simp [valEq]⟩
          simp only [encValue, Json.mkObj, decValueF, toList_ofList_singleton,
            parseDec_intRepr]
      | vbool _ | vstr _ | vnull =>
          exact ⟨_, by simp only [encValue, decValueF], valEq_refl _⟩
      | vunserializable _ =>
          refine ⟨_, ?_, valEq_refl _⟩
          simp only [encValue, Json.mkObj, decValueF, toList_ofList_singleton]
      | vvariant t v =>
          obtain ⟨w, hw', hval⟩ :=
            ih v (by simp only [wireOk] at hw; exact hw)
              (by have := sizeV_pos v; simp only [sizeV] at hv ⊢; omega)
              F' (by omega)
          refine ⟨.vvariant t w, ?_, ?_⟩
          have hne : ("tag" : String) ≠ "value" := by decide
          have hpair : (Std.TreeMap.Raw.ofList
              [("tag", Json.str t), ("value", encValue v)] compare).toList
              = [("tag", Json.str t), ("value", encValue v)]
              ∨ (Std.TreeMap.Raw.ofList
              [("tag", Json.str t), ("value", encValue v)] compare).toList
              = [("value", encValue v), ("tag", Json.str t)] :=
            toList_ofList_pair hne
          rcases hpair with h | h
          · simp only [encValue, Json.mkObj, decValueF, h, hw']
            rfl
          · simp only [encValue, Json.mkObj, decValueF, h, hw']
            rfl
          · simp only [valEq, beq_self_eq_true, Bool.true_and, hval]
      | vseq xs =>
          simp only [wireOk] at hw
          obtain ⟨ws, hmap, hlist⟩ :=
            decList_mapM_ok xs F' (by omega) hw (fun x hx => by
              have := sizeV_pos x
              have := sizeV_mem hx
              simp only [sizeV] at hv ⊢
              omega) (fun x hxw hszx => ih x hxw hszx)
          refine ⟨.vseq ws, ?_, by simp only [valEq]; exact hlist⟩
          simp only [encValue, decValueF, List.toList_toArray, hmap]
      | vset xs =>
          simp only [wireOk] at hw
          obtain ⟨ws, hmap, hlist⟩ :=
            decList_mapM_ok xs F' (by omega) hw (fun x hx => by
              have := sizeV_pos x
              have := sizeV_mem hx
              simp only [sizeV] at hv ⊢
              omega) (fun x hxw hszx => ih x hxw hszx)
          refine ⟨.vset ws, ?_, ?_⟩
          · simp only [encValue, Json.mkObj, decValueF, toList_ofList_singleton,
              List.toList_toArray, hmap]
          · rw [valEq, Bool.and_eq_true]
            exact ⟨listEq_setCont hlist, listEq_setCont_rev hlist⟩
      | vtuple xs =>
          simp only [wireOk] at hw
          obtain ⟨ws, hmap, hlist⟩ :=
            decList_mapM_ok xs F' (by omega) hw (fun x hx => by
              have := sizeV_pos x
              have := sizeV_mem hx
              simp only [sizeV] at hv ⊢
              omega) (fun x hxw hszx => ih x hxw hszx)
          refine ⟨.vtuple ws, ?_, ?_⟩
          · simp only [encValue, Json.mkObj, decValueF, toList_ofList_singleton,
              List.toList_toArray, hmap]
          · rw [valEq]
            exact hlist
      | vmap m =>
          have hwokm : wireOkMap m = true := by
            simp only [wireOk] at hw
            exact hw
          obtain ⟨ws, hmap, hd1m, hd2m⟩ :=
            decPairs_mapM_ok m F' (by omega) hwokm (fun k v hmem => by
              have := sizeV_pos v
              have := sizeV_mem_map hmem
              simp only [sizeV] at hv ⊢
              omega) (fun x hxw hsz => ih x hxw (by
              have := sizeV_pos x
              simp only [sizeV] at hsz hv ⊢
              omega))
          refine ⟨.vmap ws, ?_, ?_⟩
          · simp only [encValue, Json.mkObj, decValueF, toList_ofList_singleton,
              List.toList_toArray, hmap]
          · simp only [valEq, Bool.and_eq_true]
            refine ⟨mapCont_iff m ws |>.mpr hd1m, mapCont_iff ws m |>.mpr (fun k w hwmem => by
              obtain ⟨v, hv, hval⟩ := hd2m k w hwmem
              exact ⟨v, hv, valEq_symm _ _ hval⟩)⟩
      | vrecord m =>
          have hwokm : wireOkMap m = true := by
            simp only [wireOk] at hw
            exact hw
          obtain ⟨hlen, hd1m, hd2m⟩ := recordBridges hwokm
          have hvr : sizeV (Value.vrecord m) = 1 + sizeM m := rfl
          have hszm : ∀ k v, (k, v) ∈ m → sizeV v ≤ n := by
            intro k v hmem
            have h1 := sizeV_mem_map hmem
            rw [hvr] at hv
            omega
          obtain ⟨es, hto⟩ : ∃ es,
              (Std.TreeMap.Raw.ofList (encMap m) compare).toList = es := ⟨_, rfl⟩
          rw [hto] at hd1m hd2m
          obtain ⟨ws, hrec, hd2w, hd1w⟩ :=
            decRecordF_ok es F' (by omega) hd2m hwokm
              (fun x hxw hszx => ih x hxw hszx) hszm
          refine ⟨.vrecord ws, ?_, ?_⟩
          · simp only [encValue, Json.mkObj, decValueF]
            rw [hto]
            cases es with
            | nil =>
                have hnil : decRecordF F' [] = Except.ok ([] : ValueMap) := by
                  simp only [decRecordF]
                rw [hnil] at hrec
                injection hrec with hws
                cases hws
                split
                · next s he => simp at he
                · next as he => simp at he
                · next as he => simp at he
                · next s he => simp at he
                · next as he => simp at he
                · next e1' e2' he => simp at he
                · rw [hnil]
            | cons e1 es' =>
                obtain ⟨k1, j1⟩ := e1
                have hd2e1 : ∃ v, (k1, v) ∈ m ∧ encValue v = j1 :=
                  hd2m k1 j1 List.mem_cons_self
                obtain ⟨v1, hv1, hej1⟩ := hd2e1
                have hres1 : reservedKey k1 = false := wireOkMap_mem_key hwokm hv1
                have hne1a : k1 ≠ "#bigint" := by intro hc; rw [hc] at hres1; simp [reservedKey] at hres1
                have hne1b : k1 ≠ "#set" := by intro hc; rw [hc] at hres1; simp [reservedKey] at hres1
                have hne1c : k1 ≠ "#tup" := by intro hc; rw [hc] at hres1; simp [reservedKey] at hres1
                have hne1d : k1 ≠ "#map" := by intro hc; rw [hc] at hres1; simp [reservedKey] at hres1
                have hne1e : k1 ≠ "#unserializable" := by intro hc; rw [hc] at hres1; simp [reservedKey] at hres1
                have hne1t : k1 ≠ "tag" := by intro hc; rw [hc] at hres1; simp [reservedKey] at hres1
                have hne1v : k1 ≠ "value" := by intro hc; rw [hc] at hres1; simp [reservedKey] at hres1
                cases es' with
                | nil =>
                    split
                    · next s he =>
                        injection he with he
                        rw [Prod.mk.injEq] at he; obtain ⟨hk, _⟩ := he
                        rw [hk] at hne1a; exact absurd rfl hne1a
                    · next as he =>
                        injection he with he
                        rw [Prod.mk.injEq] at he; obtain ⟨hk, _⟩ := he
                        rw [hk] at hne1b; exact absurd rfl hne1b
                    · next as he =>
                        injection he with he
                        rw [Prod.mk.injEq] at he; obtain ⟨hk, _⟩ := he
                        rw [hk] at hne1c; exact absurd rfl hne1c
                    · next s he =>
                        injection he with he
                        rw [Prod.mk.injEq] at he; obtain ⟨hk, _⟩ := he
                        rw [hk] at hne1e; exact absurd rfl hne1e
                    · next as he =>
                        injection he with he
                        rw [Prod.mk.injEq] at he; obtain ⟨hk, _⟩ := he
                        rw [hk] at hne1d; exact absurd rfl hne1d
                    · next e2' he => simp at he
                    · rw [hrec]
                | cons e2 es'' =>
                    obtain ⟨k2, j2⟩ := e2
                    have hd2e2 : ∃ v, (k2, v) ∈ m ∧ encValue v = j2 :=
                      hd2m k2 j2 (List.mem_cons_of_mem _ List.mem_cons_self)
                    obtain ⟨v2, hv2, _⟩ := hd2e2
                    have hres2 : reservedKey k2 = false := wireOkMap_mem_key hwokm hv2
                    have hne2t : k2 ≠ "tag" := by intro hc; rw [hc] at hres2; simp [reservedKey] at hres2
                    have hne2v : k2 ≠ "value" := by intro hc; rw [hc] at hres2; simp [reservedKey] at hres2
                    have hc1 : ((("tag" : String) == k1) && (("value" : String) == k2)) = false := by
                      simp [Ne.symm hne1t]
                    have hc2 : ((("value" : String) == k1) && (("tag" : String) == k2)) = false := by
                      simp [Ne.symm hne1v]
                    cases es'' with
                    | nil =>
                        split
                        · next s he => simp at he
                        · next as he => simp at he
                        · next as he => simp at he
                        · next s he => simp at he
                        · next as he => simp at he
                        · next e1' e2' he =>
                            injection he with he1 he2
                            subst he1
                            injection he2 with he2
                            subst he2
                            rw [if_neg (by simp [hne1t]), if_neg (by simp [hne1v])]
                            rw [hrec]
                        · rw [hrec]
                    | cons e3 es3 =>
                        split
                        · next s he => simp at he
                        · next as he => simp at he
                        · next as he => simp at he
                        · next s he => simp at he
                        · next as he => simp at he
                        · next e1' e2' he => simp at he
                        · rw [hrec]
          · rw [valEq, Bool.and_eq_true]
            refine ⟨mapCont_iff m ws |>.mpr ?_, mapCont_iff ws m |>.mpr ?_⟩
            · intro k v hmem
              obtain ⟨w, hwmem, v', hv', hevv, hval'⟩ :=
                hd1w k (encValue v) (hd1m k v hmem)
              have hvv : v' = v :=
                mem_key_unique (wireOkMap_pairwise hwokm) hv' hmem
              rw [← hvv]
              exact ⟨w, hwmem, hval'⟩
            · intro k w hwmem
              obtain ⟨v', hv', hval'⟩ := hd2w k w hwmem
              exact ⟨v', hv', valEq_symm _ _ hval'⟩
/-- Public form of the round-trip (§6.6): decoding with the default fuel
recovers a value equal to the original. The fuel side-condition is a
documented deviation: Lean 4.33's `sizeOf` over `Lean.Json` is opaque,
so a fuel bound is carried explicitly instead of an implicit sizeOf bound. -/
theorem decodeValue_encValue (v : Value) (hw : wireOk v = true)
    (hfuel : 2 * sizeV v + 4 ≤ defaultFuel) :
    ∃ w, decodeValue (encValue v) = Except.ok w ∧ valEq v w = true :=
  decValueF_encValue (sizeV v) v hw (Nat.le_refl _) defaultFuel hfuel

/-! ## Configuration types -/

structure ApalacheConfig where
  constInit : Option String
  initPredicate : Option String
  invariant : String
  lengthBound : Nat
  nextPredicate : Option String
  paramVars : String
  specPath : String
  deriving Repr

structure SpecConfig where
  sources : List String
  deriving Repr

structure TraceConfig where
  numTraces : Nat
  view : String
  deriving Repr

/-! ## Job and explorer result types -/

inductive ValidateResult where
  | valid
  | invalid (msg : String)
  deriving Repr

structure TraceGenResult where
  itfTracePaths : List String
  itfTraces : List Value
  deriving Repr

inductive JobKind where
  | validate
  | genTraces
  deriving Repr

inductive JobPhase where
  | pending
  | running
  | done
  | failed
  | cancelled
  | unknown
  deriving Repr

inductive JobOutcome where
  | validate (r : ValidateResult)
  | genTraces (r : TraceGenResult)
  | infraError (msg : String)
  deriving Repr

inductive DiffKind where
  | valueMismatch
  | missing
  | extra
  | missingElem
  | extraElem
  | typeMismatch
  | truncated
  deriving Repr

inductive PathSeg where
  | field (f : String)
  | index (i : Nat)
  deriving Repr

structure DiffHint where
  kind : DiffKind
  path : List PathSeg
  actual : Option Value
  expected : Option Value
  deriving Repr

/-! ## Messages -/

inductive ClientMessage where
  | register (cfg : ApalacheConfig) (spec : Option SpecConfig) (tcfg : TraceConfig)
  | registerTraces (cfg : ApalacheConfig) (paths : List String)
  | registerGenTraces (cfg : ApalacheConfig) (dest : Option String)
      (spec : Option SpecConfig) (tcfg : TraceConfig)
  | registerExplore (spec : SpecConfig) (exports : List String)
      (invariants : List String) (maxSteps : Nat)
  | registerExploreSession (spec : SpecConfig) (exports : List String)
      (invariants : List String)
  | registerValidate (cfg : ApalacheConfig) (bound : Nat) (spec : Option SpecConfig)
  | registerValidateAsync (cfg : ApalacheConfig) (bound : Nat) (spec : Option SpecConfig)
  | registerGenTracesAsync (cfg : ApalacheConfig) (dest : Option String)
      (spec : Option SpecConfig) (tcfg : TraceConfig)
  | queryJob (jobId : String)
  | awaitJob (jobId : String) (timeout : Option Nat)
  | cancelJob (jobId : String)
  | exploreAssumeTransition (tid : Nat)
  | exploreNextStep
  | exploreQueryState
  | exploreCheckInvariant (iid : Nat)
  | exploreAssumeState (st : ValueMap)
  | exploreRollback (sid : Nat)
  | exploreDone
  | reportState (st : ValueMap)
  deriving Repr

inductive MirrorMessage where
  | specValidated (result : ValidateResult)
  | initialState (action : String) (st : ValueMap)
  | nextStep (action : String) (params : ValueMap)
  | stepOk
  | stepMismatch (expected actual : ValueMap) (hints : List DiffHint)
  | allStepsDone
  | genTracesDone (r : TraceGenResult)
  | registerError (err : String)
  | protocolError (err : String)
  | explorerReady (initTransitions nextTransitions stateInvariants : Nat)
  | exploreTransitionStatus (status : String)
  | exploreStepDone (stepNo : Nat)
  | exploreState (st : ValueMap)
  | exploreInvariantStatus (status : String)
  | exploreAssumeStatus (status : String)
  | exploreRollbackDone (sid : Nat)
  | exploreSessionDone
  | jobAccepted (jobId : String) (kind : JobKind)
  | jobStatus (jobId : String) (phase : JobPhase)
  | jobResult (jobId : String) (outcome : JobOutcome)
  deriving Repr

/-! ## Message sub-encoders -/

def jApalacheConfig (c : ApalacheConfig) : Json :=
  Json.mkObj [
    ("constInit", optStr c.constInit),
    ("initPredicate", optStr c.initPredicate),
    ("invariant", Json.str c.invariant),
    ("lengthBound", Json.num c.lengthBound),
    ("nextPredicate", optStr c.nextPredicate),
    ("paramVars", Json.str c.paramVars),
    ("specPath", Json.str c.specPath)]

def jSpecConfig (s : SpecConfig) : Json :=
  Json.mkObj [("sources", Json.arr (strsJson s.sources).toArray)]

def jTraceConfig (t : TraceConfig) : Json :=
  Json.mkObj [("numTraces", Json.num t.numTraces), ("view", Json.str t.view)]

def jValidateResult : ValidateResult → Json
  | .valid => Json.str "valid"
  | .invalid msg => Json.mkObj [("invalid", Json.str msg)]

def jTraceGenResult (r : TraceGenResult) : Json :=
  Json.mkObj [
    ("itfTracePaths", Json.arr (strsJson r.itfTracePaths |>.toArray)),
    ("itfTraces", Json.arr (r.itfTraces.map encValue |>.toArray))]

def jJobKind : JobKind → Json
  | .validate => Json.str "validate"
  | .genTraces => Json.str "gen_traces"

def jJobPhase : JobPhase → Json
  | .pending => Json.str "pending"
  | .running => Json.str "running"
  | .done => Json.str "done"
  | .failed => Json.str "failed"
  | .cancelled => Json.str "cancelled"
  | .unknown => Json.str "unknown"

def jJobOutcome : JobOutcome → Json
  | .validate r => Json.mkObj [("validate", jValidateResult r)]
  | .genTraces r => Json.mkObj [("genTraces", jTraceGenResult r)]
  | .infraError msg => Json.mkObj [("error", Json.str msg)]

def jDiffKind : DiffKind → Json
  | .valueMismatch => Json.str "value_mismatch"
  | .missing => Json.str "missing"
  | .extra => Json.str "extra"
  | .missingElem => Json.str "missing_elem"
  | .extraElem => Json.str "extra_elem"
  | .typeMismatch => Json.str "type_mismatch"
  | .truncated => Json.str "truncated"

def jPathSeg : PathSeg → Json
  | .field f => Json.mkObj [("field", Json.str f)]
  | .index i => Json.mkObj [("index", Json.num i)]

def jOptValueRaw (v : Option Value) : Json :=
  match v with
  | some v' => encValue v'
  | none => Json.null

def jDiffHint (h : DiffHint) : Json :=
  let base := [("kind", jDiffKind h.kind), ("path", Json.arr (h.path.map jPathSeg |>.toArray))]
  Json.mkObj (base ++
    (match h.actual with
     | some v => [("actual", encValue v)]
     | none => []) ++
    (match h.expected with
     | some v => [("expected", encValue v)]
     | none => []))

def jStateMap (m : ValueMap) : Json := Json.mkObj (encMap m)

/-! ## Client encoder -/

def encodeClient : ClientMessage → Json
  | .register cfg spec tcfg =>
      Json.mkObj [("apalacheConfig", jApalacheConfig cfg),
        ("proto_step", Json.str "register"),
        ("spec", optJson (jSpecConfig <$> spec)),
        ("traceConfig", jTraceConfig tcfg)]
  | .registerTraces cfg paths =>
      Json.mkObj [("apalacheConfig", jApalacheConfig cfg),
        ("itfTracePaths", Json.arr (strsJson paths |>.toArray)), ("proto_step", Json.str "register_traces")]
  | .registerGenTraces cfg dest spec tcfg =>
      Json.mkObj [("apalacheConfig", jApalacheConfig cfg),
        ("destPath", optStr dest), ("proto_step", Json.str "register_trace_gen"),
        ("spec", optJson (jSpecConfig <$> spec)), ("traceConfig", jTraceConfig tcfg)]
  | .registerExplore spec exports invariants maxSteps =>
      Json.mkObj [("exports", Json.arr (strsJson exports |>.toArray)), ("invariants", Json.arr (strsJson invariants |>.toArray)),
        ("maxSteps", Json.num maxSteps), ("proto_step", Json.str "register_explore"),
        ("spec", jSpecConfig spec)]
  | .registerExploreSession spec exports invariants =>
      Json.mkObj [("exports", Json.arr (strsJson exports |>.toArray)), ("invariants", Json.arr (strsJson invariants |>.toArray)),
        ("proto_step", Json.str "register_explore_session"), ("spec", jSpecConfig spec)]
  | .registerValidate cfg bound spec =>
      Json.mkObj ([("apalacheConfig", jApalacheConfig cfg), ("bound", Json.num bound),
        ("proto_step", Json.str "register_validate")] ++
        (match spec with
         | some s => [("spec", jSpecConfig s)]
         | none => []))
  | .registerValidateAsync cfg bound spec =>
      Json.mkObj ([("apalacheConfig", jApalacheConfig cfg), ("bound", Json.num bound),
        ("proto_step", Json.str "register_validate_async")] ++
        (match spec with
         | some s => [("spec", jSpecConfig s)]
         | none => []))
  | .registerGenTracesAsync cfg dest spec tcfg =>
      Json.mkObj [("apalacheConfig", jApalacheConfig cfg),
        ("destPath", optStr dest), ("proto_step", Json.str "register_trace_gen_async"),
        ("spec", optJson (jSpecConfig <$> spec)), ("traceConfig", jTraceConfig tcfg)]
  | .queryJob jobId =>
      Json.mkObj [("jobId", Json.str jobId), ("proto_step", Json.str "query_job")]
  | .awaitJob jobId timeout =>
      Json.mkObj ([("jobId", Json.str jobId), ("proto_step", Json.str "await_job")] ++
        (match timeout with
         | some t => [("timeoutSecs", Json.num t)]
         | none => []))
  | .cancelJob jobId =>
      Json.mkObj [("jobId", Json.str jobId), ("proto_step", Json.str "cancel_job")]
  | .exploreAssumeTransition tid =>
      Json.mkObj [("proto_step", Json.str "explore_assume_transition"),
        ("transitionId", Json.num tid)]
  | .exploreNextStep =>
      Json.mkObj [("proto_step", Json.str "explore_next_step")]
  | .exploreQueryState =>
      Json.mkObj [("proto_step", Json.str "explore_query_state")]
  | .exploreCheckInvariant iid =>
      Json.mkObj [("invariantId", Json.num iid), ("proto_step", Json.str "explore_check_invariant")]
  | .exploreAssumeState st =>
      Json.mkObj [("proto_step", Json.str "explore_assume_state"), ("state", jStateMap st)]
  | .exploreRollback sid =>
      Json.mkObj [("proto_step", Json.str "explore_rollback"), ("snapshotId", Json.num sid)]
  | .exploreDone =>
      Json.mkObj [("proto_step", Json.str "explore_done")]
  | .reportState st =>
      Json.mkObj [("proto_step", Json.str "report_state"), ("state", jStateMap st)]

/-! ## Mirror encoder -/

def encodeMirror : MirrorMessage → Json
  | .specValidated result =>
      Json.mkObj [("proto_step", Json.str "spec_validated"), ("result", jValidateResult result)]
  | .initialState action st =>
      Json.mkObj [("action", Json.str action), ("proto_step", Json.str "initial_state"),
        ("state", jStateMap st)]
  | .nextStep action params =>
      Json.mkObj [("action", Json.str action), ("parameters", jStateMap params),
        ("proto_step", Json.str "next_step")]
  | .stepOk =>
      Json.mkObj [("proto_step", Json.str "step_ok")]
  | .stepMismatch expected actual hints =>
      Json.mkObj [("actual", jStateMap actual), ("expected", jStateMap expected),
        ("hints", Json.arr (hints.map jDiffHint |>.toArray)),
        ("proto_step", Json.str "step_mismatch")]
  | .allStepsDone =>
      Json.mkObj [("proto_step", Json.str "all_steps_done")]
  | .genTracesDone r =>
      Json.mkObj [
        ("itfTracePaths", Json.arr (strsJson r.itfTracePaths |>.toArray)),
        ("itfTraces", Json.arr (r.itfTraces.map encValue |>.toArray)),
        ("proto_step", Json.str "gen_traces_done")]
  | .registerError err =>
      Json.mkObj [("error", Json.str err), ("proto_step", Json.str "register_error")]
  | .protocolError err =>
      Json.mkObj [("error", Json.str err), ("proto_step", Json.str "protocol_error")]
  | .explorerReady i n s =>
      Json.mkObj [("initTransitions", Json.num i), ("nextTransitions", Json.num n),
        ("proto_step", Json.str "explorer_ready"), ("stateInvariants", Json.num s)]
  | .exploreTransitionStatus status =>
      Json.mkObj [("proto_step", Json.str "explore_transition_status"), ("status", Json.str status)]
  | .exploreStepDone stepNo =>
      Json.mkObj [("proto_step", Json.str "explore_step_done"), ("stepNo", Json.num stepNo)]
  | .exploreState st =>
      Json.mkObj [("proto_step", Json.str "explore_state"), ("state", jStateMap st)]
  | .exploreInvariantStatus status =>
      Json.mkObj [("proto_step", Json.str "explore_invariant_status"), ("status", Json.str status)]
  | .exploreAssumeStatus status =>
      Json.mkObj [("proto_step", Json.str "explore_assume_status"), ("status", Json.str status)]
  | .exploreRollbackDone sid =>
      Json.mkObj [("proto_step", Json.str "explore_rollback_done"), ("snapshotId", Json.num sid)]
  | .exploreSessionDone =>
      Json.mkObj [("proto_step", Json.str "explore_session_done")]
  | .jobAccepted jobId kind =>
      Json.mkObj [("jobId", Json.str jobId), ("kind", jJobKind kind),
        ("proto_step", Json.str "job_accepted")]
  | .jobStatus jobId phase =>
      Json.mkObj [("jobId", Json.str jobId), ("phase", jJobPhase phase),
        ("proto_step", Json.str "job_status")]
  | .jobResult jobId outcome =>
      Json.mkObj [("jobId", Json.str jobId), ("outcome", jJobOutcome outcome),
        ("proto_step", Json.str "job_result")]

/-! ## Decoding helpers -/

def reqStr (j : Json) (k : String) : Dec String := jStr j k

def reqNat (j : Json) (k : String) : Dec Nat := jNat j k

def reqField (j : Json) (k : String) (f : Json → Dec α) : Dec α :=
  match jOptField j k with
  | .ok (some v) => f v
  | .ok none => derr s!"missing field: {k}"
  | .error e => .error e

private def optFieldStr (j : Json) (k : String) : Dec (Option String) := jOptStr j k

private def optFieldNat (j : Json) (k : String) : Dec (Option Nat) :=
  match j.getObjVal? k with
  | .ok (Json.num ⟨m, 0⟩) => if h : 0 ≤ m then .ok (some m.toNat) else derr s!"field {k}: natural expected"
  | .ok Json.null => .ok none
  | .ok _ => derr s!"field {k}: natural expected"
  | .error _ => .ok none

def reqStrs (j : Json) (k : String) : Dec (List String) := do
  let v ← jField j k
  match v with
  | Json.arr as =>
      as.toList.mapM (fun jv =>
        match jv with
        | Json.str s => Except.ok s
        | x => derr s!"field {k}: expected string")
  | x => derr s!"field {k}: expected string array"

private def decApalacheConfig (j : Json) : Dec ApalacheConfig := do
  let constInit ← optFieldStr j "constInit"
  let initPredicate ← optFieldStr j "initPredicate"
  let invariant ← reqStr j "invariant"
  let lengthBound ← reqNat j "lengthBound"
  let nextPredicate ← optFieldStr j "nextPredicate"
  let paramVars ← reqStr j "paramVars"
  let specPath ← reqStr j "specPath"
  return { constInit, initPredicate, invariant, lengthBound, nextPredicate, paramVars, specPath }

private def decSpecConfig (j : Json) : Dec SpecConfig := do
  let sources ← reqStrs j "sources"
  return { sources }

private def decTraceConfig (j : Json) : Dec TraceConfig := do
  let numTraces ← reqNat j "numTraces"
  let view ← reqStr j "view"
  return { numTraces, view }

private def decStateMap (j : Json) : Dec ValueMap :=
  match j with
  | Json.obj kvs => decRecordF defaultFuel kvs.toList
  | _ => derr "expected state map object"

private def decOptStateMap (j : Json) (k : String) : Dec ValueMap :=
  reqField j k decStateMap

private def decOptSpec (j : Json) : Dec (Option SpecConfig) :=
  match j.getObjVal? "spec" with
  | .ok Json.null => .ok none
  | .ok v => some <$> decSpecConfig v
  | .error _ => .ok none

private def decValues (j : Json) : Dec (List Value) :=
  match j with
  | Json.arr as => as.toList.mapM decodeValue
  | _ => derr "expected array of values"

def decValidateResult (j : Json) : Dec ValidateResult :=
  match j with
  | Json.str "valid" => .ok .valid
  | Json.obj kvs =>
      match kvs.toList with
      | [("invalid", Json.str msg)] => .ok (.invalid msg)
      | _ => derr "malformed validate result"
  | _ => derr "malformed validate result"

def decTraceGenResult (j : Json) : Dec TraceGenResult := do
  let itfTracePaths ← reqStrs j "itfTracePaths"
  let itfTraces ← reqField j "itfTraces" decValues
  return { itfTracePaths, itfTraces }

def decJobKind (j : Json) : Dec JobKind :=
  match j with
  | Json.str "validate" => .ok .validate
  | Json.str "gen_traces" => .ok .genTraces
  | _ => derr "malformed job kind"

def decJobPhase (j : Json) : Dec JobPhase :=
  match j with
  | Json.str "pending" => .ok .pending
  | Json.str "running" => .ok .running
  | Json.str "done" => .ok .done
  | Json.str "failed" => .ok .failed
  | Json.str "cancelled" => .ok .cancelled
  | Json.str "unknown" => .ok .unknown
  | _ => derr "malformed job phase"

def decJobOutcome (j : Json) : Dec JobOutcome :=
  match j with
  | Json.obj kvs =>
      match kvs.toList with
      | [("validate", r)] => .validate <$> decValidateResult r
      | [("genTraces", r)] => .genTraces <$> decTraceGenResult r
      | [("error", Json.str msg)] => .ok (.infraError msg)
      | _ => derr "malformed job outcome"
  | _ => derr "malformed job outcome"

def decDiffKind (j : Json) : Dec DiffKind :=
  match j with
  | Json.str "value_mismatch" => .ok .valueMismatch
  | Json.str "missing" => .ok .missing
  | Json.str "extra" => .ok .extra
  | Json.str "missing_elem" => .ok .missingElem
  | Json.str "extra_elem" => .ok .extraElem
  | Json.str "type_mismatch" => .ok .typeMismatch
  | Json.str "truncated" => .ok .truncated
  | _ => derr "malformed diff kind"

def decPathSeg (j : Json) : Dec PathSeg :=
  match j with
  | Json.obj kvs =>
      match kvs.toList with
      | [("field", Json.str f)] => .ok (.field f)
      | [("index", Json.num ⟨m, 0⟩)] =>
          if h : 0 ≤ m then .ok (.index m.toNat) else derr "negative path index"
      | _ => derr "malformed path segment"
  | _ => derr "malformed path segment"

private def decPathArr (jv : Json) : Dec (List PathSeg) :=
  match jv with
  | Json.arr as => as.toList.mapM decPathSeg
  | _ => derr "malformed hint path"

private def decOptValueField (j : Json) (k : String) : Dec (Option Value) :=
  match j.getObjVal? k with
  | .ok v => some <$> decodeValue v
  | .error _ => .ok none

def decDiffHint (j : Json) : Dec DiffHint := do
  let kind ← reqField j "kind" decDiffKind
  let path ← reqField j "path" decPathArr
  let actual ← decOptValueField j "actual"
  let expected ← decOptValueField j "expected"
  return { kind, path, actual, expected }

private def decHintArr (jv : Json) : Dec (List DiffHint) :=
  match jv with
  | Json.arr as => as.toList.mapM decDiffHint
  | _ => derr "malformed hints"

/-! ## Client decoder -/

def decodeClient (j : Json) : Dec ClientMessage :=
  match jStr j "proto_step" with
  | .ok "register" => do
      let cfg ← reqField j "apalacheConfig" decApalacheConfig
      let spec ← decOptSpec j
      let tcfg ← reqField j "traceConfig" decTraceConfig
      return .register cfg spec tcfg
  | .ok "register_traces" => do
      let cfg ← reqField j "apalacheConfig" decApalacheConfig
      let paths ← reqStrs j "itfTracePaths"
      return .registerTraces cfg paths
  | .ok "register_trace_gen" => do
      let cfg ← reqField j "apalacheConfig" decApalacheConfig
      let dest ← optFieldStr j "destPath"
      let spec ← decOptSpec j
      let tcfg ← reqField j "traceConfig" decTraceConfig
      return .registerGenTraces cfg dest spec tcfg
  | .ok "register_explore" => do
      let spec ← reqField j "spec" decSpecConfig
      let exports ← reqStrs j "exports"
      let invariants ← reqStrs j "invariants"
      let maxSteps ← reqNat j "maxSteps"
      return .registerExplore spec exports invariants maxSteps
  | .ok "register_explore_session" => do
      let spec ← reqField j "spec" decSpecConfig
      let exports ← reqStrs j "exports"
      let invariants ← reqStrs j "invariants"
      return .registerExploreSession spec exports invariants
  | .ok "register_validate" => do
      let cfg ← reqField j "apalacheConfig" decApalacheConfig
      let bound ← reqNat j "bound"
      let spec ← decOptSpec j
      return .registerValidate cfg bound spec
  | .ok "register_validate_async" => do
      let cfg ← reqField j "apalacheConfig" decApalacheConfig
      let bound ← reqNat j "bound"
      let spec ← decOptSpec j
      return .registerValidateAsync cfg bound spec
  | .ok "register_trace_gen_async" => do
      let cfg ← reqField j "apalacheConfig" decApalacheConfig
      let dest ← optFieldStr j "destPath"
      let spec ← decOptSpec j
      let tcfg ← reqField j "traceConfig" decTraceConfig
      return .registerGenTracesAsync cfg dest spec tcfg
  | .ok "query_job" => do
      let jobId ← reqStr j "jobId"
      return .queryJob jobId
  | .ok "await_job" => do
      let jobId ← reqStr j "jobId"
      let timeout ← optFieldNat j "timeoutSecs"
      return .awaitJob jobId timeout
  | .ok "cancel_job" => do
      let jobId ← reqStr j "jobId"
      return .cancelJob jobId
  | .ok "explore_assume_transition" => do
      let tid ← reqNat j "transitionId"
      return .exploreAssumeTransition tid
  | .ok "explore_next_step" => return .exploreNextStep
  | .ok "explore_query_state" => return .exploreQueryState
  | .ok "explore_check_invariant" => do
      let iid ← reqNat j "invariantId"
      return .exploreCheckInvariant iid
  | .ok "explore_assume_state" => do
      let st ← decOptStateMap j "state"
      return .exploreAssumeState st
  | .ok "explore_rollback" => do
      let sid ← reqNat j "snapshotId"
      return .exploreRollback sid
  | .ok "explore_done" => return .exploreDone
  | .ok "report_state" => do
      let st ← decOptStateMap j "state"
      return .reportState st
  | .ok _ => derr "unknown client proto_step"
  | .error e => .error e

/-! ## Mirror decoder -/

def decodeMirror (j : Json) : Dec MirrorMessage :=
  match jStr j "proto_step" with
  | .ok "spec_validated" => do
      let r ← reqField j "result" decValidateResult
      return .specValidated r
  | .ok "initial_state" => do
      let action ← reqStr j "action"
      let st ← decOptStateMap j "state"
      return .initialState action st
  | .ok "next_step" => do
      let action ← reqStr j "action"
      let params ← decOptStateMap j "parameters"
      return .nextStep action params
  | .ok "step_ok" => return .stepOk
  | .ok "step_mismatch" => do
      let expected ← decOptStateMap j "expected"
      let actual ← decOptStateMap j "actual"
      let hints ← reqField j "hints" decHintArr
      return .stepMismatch expected actual hints
  | .ok "all_steps_done" => return .allStepsDone
  | .ok "gen_traces_done" => do
      let r ← decTraceGenResult j
      return .genTracesDone r
  | .ok "register_error" => do
      let err ← reqStr j "error"
      return .registerError err
  | .ok "protocol_error" => do
      let err ← reqStr j "error"
      return .protocolError err
  | .ok "explorer_ready" => do
      let i ← reqNat j "initTransitions"
      let n ← reqNat j "nextTransitions"
      let s ← reqNat j "stateInvariants"
      return .explorerReady i n s
  | .ok "explore_transition_status" => do
      let status ← reqStr j "status"
      return .exploreTransitionStatus status
  | .ok "explore_step_done" => do
      let stepNo ← reqNat j "stepNo"
      return .exploreStepDone stepNo
  | .ok "explore_state" => do
      let st ← decOptStateMap j "state"
      return .exploreState st
  | .ok "explore_invariant_status" => do
      let status ← reqStr j "status"
      return .exploreInvariantStatus status
  | .ok "explore_assume_status" => do
      let status ← reqStr j "status"
      return .exploreAssumeStatus status
  | .ok "explore_rollback_done" => do
      let sid ← reqNat j "snapshotId"
      return .exploreRollbackDone sid
  | .ok "explore_session_done" => return .exploreSessionDone
  | .ok "job_accepted" => do
      let jobId ← reqStr j "jobId"
      let kind ← reqField j "kind" decJobKind
      return .jobAccepted jobId kind
  | .ok "job_status" => do
      let jobId ← reqStr j "jobId"
      let phase ← reqField j "phase" decJobPhase
      return .jobStatus jobId phase
  | .ok "job_result" => do
      let jobId ← reqStr j "jobId"
      let outcome ← reqField j "outcome" decJobOutcome
      return .jobResult jobId outcome
  | .ok _ => derr "unknown mirror proto_step"
  | .error e => .error e
/-! ## §6.6 message-level round-trip

For every constructor we prove that decoding the encoded message succeeds
and returns a message equivalent to the original: equal on scalar fields,
equal up to `valEq` (and up to extensional map equality `mapEqV`) on
value fields.  Exact `= ok m` holds for every constructor without value
positions. -/

/-! ### Extensional equalities -/

/-- Extensional equality of state maps: same keys, `valEq` values. -/
def mapEqV (a b : ValueMap) : Prop :=
  (∀ k v, (k, v) ∈ a → ∃ w, (k, w) ∈ b ∧ valEq v w = true) ∧
  (∀ k w, (k, w) ∈ b → ∃ v, (k, v) ∈ a ∧ valEq v w = true)

/-- Equality up to `valEq` for optional values. -/
def optValEq : Option Value → Option Value → Prop
  | none, none => True
  | some v, some w => valEq v w = true
  | _, _ => False

/-- Wire-side well-formedness of an embedded value. -/
def valBounded (v : Value) : Prop := wireOk v = true ∧ 2 * sizeV v + 6 ≤ defaultFuel

/-- Wire-side well-formedness of a state map. -/
def mapOkBounded (m : ValueMap) : Prop :=
  wireOkMap m = true ∧ ∀ k v, (k, v) ∈ m → valBounded v

def hintOk (h : DiffHint) : Prop :=
  (∀ v ∈ h.actual, valBounded v) ∧ (∀ v ∈ h.expected, valBounded v)

def tracesOk (r : TraceGenResult) : Prop := ∀ v ∈ r.itfTraces, valBounded v

/-! ### Field access on encoded objects -/

theorem str_of_mkObj {l : List (String × Json)} {k : String} {v : String}
    (hkeys : (l.map Prod.fst).Pairwise (fun a b => a ≠ b)) (hm : (k, Json.str v) ∈ l) :
    jStr (Json.mkObj l) k = Except.ok v := by
  simp only [jStr, getObjVal?_mkObj hkeys hm]

theorem nat_of_mkObj {l : List (String × Json)} {k : String} {n : Nat}
    (hkeys : (l.map Prod.fst).Pairwise (fun a b => a ≠ b))
    (hm : (k, Json.num n) ∈ l) :
    jNat (Json.mkObj l) k = Except.ok n := by
  simp only [jNat, getObjVal?_mkObj hkeys hm]
  exact dif_pos (by omega)

theorem optFieldStr_mkObj {l : List (String × Json)} {k : String}
    {o : Option String}
    (hkeys : (l.map Prod.fst).Pairwise (fun a b => a ≠ b))
    (hm : (k, optStr o) ∈ l) :
    optFieldStr (Json.mkObj l) k = Except.ok o := by
  cases o with
  | none => simp only [optFieldStr, jOptStr, getObjVal?_mkObj hkeys hm, optStr]
  | some s => simp only [optFieldStr, jOptStr, getObjVal?_mkObj hkeys hm, optStr]

private theorem optFieldNat_mkObj {l : List (String × Json)} {k : String} {n : Nat}
    (hkeys : (l.map Prod.fst).Pairwise (fun a b => a ≠ b))
    (hm : (k, Json.num n) ∈ l) :
    optFieldNat (Json.mkObj l) k = Except.ok (some n) := by
  simp only [optFieldNat, getObjVal?_mkObj hkeys hm, JsonNumber.fromNat]
  have h1 : (↑n : Int).toNat = n := by omega
  rw [dif_pos (by omega), h1]

private theorem field_of_mkObj {l : List (String × Json)} {k : String} {v : Json}
    (hkeys : (l.map Prod.fst).Pairwise (fun a b => a ≠ b)) (hm : (k, v) ∈ l)
    (hne : v ≠ Json.null) (f : Json → Dec α) (hf : f v = Except.ok r) :
    reqField (Json.mkObj l) k f = Except.ok r := by
  have h1 : jOptField (Json.mkObj l) k = Except.ok (some v) :=
    by simp only [jOptField, getObjVal?_mkObj hkeys hm]
  simp only [reqField, h1, hf]

theorem strArr_mapM (msg : String) : ∀ ss : List String,
    List.mapM (fun jv =>
        match jv with
        | Json.str s => Except.ok s
        | x => derr msg) ((strsJson ss).toArray).toList = Except.ok ss := by
  intro ss
  induction ss with
  | nil => rfl
  | cons s rest ih =>
      have harr : ((strsJson (s :: rest)).toArray).toList
          = Json.str s :: ((strsJson rest).toArray).toList := by
        simp only [strsJson, List.map_cons, List.toList_toArray]
      show List.mapM (fun jv =>
          match jv with
          | Json.str s => Except.ok s
          | x => derr msg)
          (((strsJson (s :: rest)).toArray).toList) = _
      rw [harr, List.mapM_cons]
      have h1 : (match Json.str s with
          | Json.str s => Except.ok s
          | x => derr msg) = Except.ok s := rfl
      rw [h1, ih]
      rfl

theorem strs_of_mkObj {l : List (String × Json)} {k : String} {ss : List String}
    (hkeys : (l.map Prod.fst).Pairwise (fun a b => a ≠ b))
    (hm : (k, Json.arr (strsJson ss |>.toArray)) ∈ l) :
    reqStrs (Json.mkObj l) k = Except.ok ss := by
  simp only [reqStrs, jField, getObjVal?_mkObj hkeys hm]
  exact strArr_mapM s!"field {k}: expected string" ss
/-! ### Sub-config decoders round-trip -/

private theorem decApalacheConfig_jApalacheConfig (c : ApalacheConfig) :
    decApalacheConfig (jApalacheConfig c) = Except.ok c := by
  have hkeys : (([
    ("constInit", optStr c.constInit),
    ("initPredicate", optStr c.initPredicate),
    ("invariant", Json.str c.invariant),
    ("lengthBound", Json.num (JsonNumber.fromNat c.lengthBound)),
    ("nextPredicate", optStr c.nextPredicate),
    ("paramVars", Json.str c.paramVars),
    ("specPath", Json.str c.specPath)] : List (String × Json)).map Prod.fst).Pairwise
      (fun a b => a ≠ b) := by simp
  have m1 : ("constInit", optStr c.constInit) ∈ ([
    ("constInit", optStr c.constInit),
    ("initPredicate", optStr c.initPredicate),
    ("invariant", Json.str c.invariant),
    ("lengthBound", Json.num (JsonNumber.fromNat c.lengthBound)),
    ("nextPredicate", optStr c.nextPredicate),
    ("paramVars", Json.str c.paramVars),
    ("specPath", Json.str c.specPath)] : List (String × Json)) := by simp
  have m2 : ("initPredicate", optStr c.initPredicate) ∈ ([
    ("constInit", optStr c.constInit),
    ("initPredicate", optStr c.initPredicate),
    ("invariant", Json.str c.invariant),
    ("lengthBound", Json.num (JsonNumber.fromNat c.lengthBound)),
    ("nextPredicate", optStr c.nextPredicate),
    ("paramVars", Json.str c.paramVars),
    ("specPath", Json.str c.specPath)] : List (String × Json)) := by simp
  have m3 : ("invariant", Json.str c.invariant) ∈ ([
    ("constInit", optStr c.constInit),
    ("initPredicate", optStr c.initPredicate),
    ("invariant", Json.str c.invariant),
    ("lengthBound", Json.num (JsonNumber.fromNat c.lengthBound)),
    ("nextPredicate", optStr c.nextPredicate),
    ("paramVars", Json.str c.paramVars),
    ("specPath", Json.str c.specPath)] : List (String × Json)) := by simp
  have m4 : ("lengthBound", Json.num (JsonNumber.fromNat c.lengthBound)) ∈ ([
    ("constInit", optStr c.constInit),
    ("initPredicate", optStr c.initPredicate),
    ("invariant", Json.str c.invariant),
    ("lengthBound", Json.num (JsonNumber.fromNat c.lengthBound)),
    ("nextPredicate", optStr c.nextPredicate),
    ("paramVars", Json.str c.paramVars),
    ("specPath", Json.str c.specPath)] : List (String × Json)) := by simp
  have m5 : ("nextPredicate", optStr c.nextPredicate) ∈ ([
    ("constInit", optStr c.constInit),
    ("initPredicate", optStr c.initPredicate),
    ("invariant", Json.str c.invariant),
    ("lengthBound", Json.num (JsonNumber.fromNat c.lengthBound)),
    ("nextPredicate", optStr c.nextPredicate),
    ("paramVars", Json.str c.paramVars),
    ("specPath", Json.str c.specPath)] : List (String × Json)) := by simp
  have m6 : ("paramVars", Json.str c.paramVars) ∈ ([
    ("constInit", optStr c.constInit),
    ("initPredicate", optStr c.initPredicate),
    ("invariant", Json.str c.invariant),
    ("lengthBound", Json.num (JsonNumber.fromNat c.lengthBound)),
    ("nextPredicate", optStr c.nextPredicate),
    ("paramVars", Json.str c.paramVars),
    ("specPath", Json.str c.specPath)] : List (String × Json)) := by simp
  have m7 : ("specPath", Json.str c.specPath) ∈ ([
    ("constInit", optStr c.constInit),
    ("initPredicate", optStr c.initPredicate),
    ("invariant", Json.str c.invariant),
    ("lengthBound", Json.num (JsonNumber.fromNat c.lengthBound)),
    ("nextPredicate", optStr c.nextPredicate),
    ("paramVars", Json.str c.paramVars),
    ("specPath", Json.str c.specPath)] : List (String × Json)) := by simp
  simp only [jApalacheConfig, decApalacheConfig, reqStr, reqNat]
  rw [optFieldStr_mkObj hkeys m1, optFieldStr_mkObj hkeys m2, str_of_mkObj hkeys m3,
      nat_of_mkObj hkeys m4, optFieldStr_mkObj hkeys m5, str_of_mkObj hkeys m6,
      str_of_mkObj hkeys m7]
  rfl

private theorem decSpecConfig_jSpecConfig (s : SpecConfig) :
    decSpecConfig (jSpecConfig s) = Except.ok s := by
  simp only [jSpecConfig, decSpecConfig]
  rw [strs_of_mkObj (k := "sources") (ss := s.sources) (by simp) (by simp)]
  rfl

private theorem decTraceConfig_jTraceConfig (t : TraceConfig) :
    decTraceConfig (jTraceConfig t) = Except.ok t := by
  have hkeys : (([
    ("numTraces", Json.num (JsonNumber.fromNat t.numTraces)),
    ("view", Json.str t.view)] : List (String × Json)).map Prod.fst).Pairwise
      (fun a b => a ≠ b) := by simp
  have m1 : ("numTraces", Json.num (JsonNumber.fromNat t.numTraces)) ∈ ([
    ("numTraces", Json.num (JsonNumber.fromNat t.numTraces)),
    ("view", Json.str t.view)] : List (String × Json)) := by simp
  have m2 : ("view", Json.str t.view) ∈ ([
    ("numTraces", Json.num (JsonNumber.fromNat t.numTraces)),
    ("view", Json.str t.view)] : List (String × Json)) := by simp
  simp only [jTraceConfig, decTraceConfig, reqStr, reqNat]
  rw [nat_of_mkObj hkeys m1, str_of_mkObj hkeys m2]
  rfl

private theorem decOptSpec_of_field {l : List (String × Json)} {spec : Option SpecConfig}
    (hkeys : (l.map Prod.fst).Pairwise (fun a b => a ≠ b))
    (hm : ("spec", optJson (jSpecConfig <$> spec)) ∈ l) :
    decOptSpec (Json.mkObj l) = Except.ok spec := by
  simp only [decOptSpec, getObjVal?_mkObj hkeys hm]
  cases spec with
  | none => simp only [optJson]; rfl
  | some s =>
      rw [show jSpecConfig <$> some s = some (jSpecConfig s) from by
          first | rfl | simp]
      simp only [optJson]
      split
      · next hnull =>
          injection hnull with hnull
          exact absurd hnull (by intro h; exact Json.noConfusion h)
      · next v hv =>
          injection hv with hv
          rw [← hv, decSpecConfig_jSpecConfig]
          rfl
      · next herr => exact nomatch herr

private theorem decOptStateMap_of_field {l : List (String × Json)} {k : String}
    {st : ValueMap} (hkeys : (l.map Prod.fst).Pairwise (fun a b => a ≠ b))
    (hm : (k, Json.mkObj (encMap st)) ∈ l) :
    decOptStateMap (Json.mkObj l) k = decStateMap (Json.mkObj (encMap st)) := by
  have h1 : jOptField (Json.mkObj l) k = Except.ok (some (Json.mkObj (encMap st))) := by
    simp only [jOptField, getObjVal?_mkObj hkeys hm]
    split
    · next hnull =>
        injection hnull with hnull
        exact absurd hnull (by intro h'; exact Json.noConfusion h')
    · next v hv => injection hv with hv; rw [← hv]
    · next herr => exact nomatch herr
  simp only [decOptStateMap, reqField, h1]

/-! ### Value and map field round-trips -/

theorem decodeValue_bounded (v : Value) (h : valBounded v) :
    ∃ w, decodeValue (encValue v) = Except.ok w ∧ valEq v w = true :=
  decValueF_encValue (sizeV v) v h.1 (Nat.le_refl _) defaultFuel (by
    have h2 := h.2
    simp only [defaultFuel] at h2 ⊢
    omega)

theorem decStateMap_jStateMap (m : ValueMap) (h : mapOkBounded m) :
    ∃ ws, decStateMap (jStateMap m) = Except.ok ws ∧ mapEqV m ws := by
  obtain ⟨hlen, hd1m, hd2m⟩ := recordBridges h.1
  have hsz : ∀ k v, (k, v) ∈ m → sizeV v ≤ 2147483645 := by
    intro k v hmem
    have h2 := (h.2 k v hmem).2
    simp only [defaultFuel] at h2
    omega
  have hich : ∀ v, wireOk v = true → sizeV v ≤ 2147483645 → encOkAt 2147483645 v := by
    intro v hwok hszv F hF
    exact decValueF_encValue 2147483645 v hwok hszv F hF
  obtain ⟨ws, hrec, hd2w, hd1w⟩ :=
    decRecordF_ok (n := 2147483645)
      (Std.TreeMap.Raw.ofList (encMap m) compare).toList defaultFuel
      (by decide) hd2m h.1 hich hsz
  refine ⟨ws, ?_, ?_, ?_⟩
  · simp only [jStateMap, Json.mkObj, decStateMap, hrec]
  · intro k v hmem
    obtain ⟨w, hwmem, v', hv', _, hval⟩ := hd1w k (encValue v) (hd1m k v hmem)
    have hvv : v' = v := mem_key_unique (wireOkMap_pairwise h.1) hv' hmem
    rw [← hvv]
    exact ⟨w, hwmem, hval⟩
  · intro k w hwmem
    obtain ⟨v, hv, hval⟩ := hd2w k w hwmem
    exact ⟨v, hv, hval⟩
theorem getObjVal?_mkObj_error {l : List (String × Json)} {k : String}
    (hkeys : (l.map Prod.fst).Pairwise (fun a b => a ≠ b))
    (hnm : ∀ v, (k, v) ∉ l) :
    ∃ e, (Json.mkObj l).getObjVal? k = Except.error e := by
  have hp := pairwise_keys_ne hkeys
  have hk : ¬ k ∈ l.map Prod.fst := by
    intro hmem
    obtain ⟨⟨k', v'⟩, hv, hbeq⟩ := List.mem_map.mp hmem
    simp only [Prod.fst] at hbeq
    rw [hbeq] at hv
    exact hnm v' hv
  have hnone : (Std.TreeMap.Raw.ofList l compare)[k]? = none :=
    Std.TreeMap.Raw.getElem?_ofList_of_contains_eq_false
      (contains_eq_false := by simp [hk])
  have hnone' : (Std.TreeMap.Raw.ofList l compare).get? k = none := hnone
  simp only [Json.mkObj, Json.getObjVal?, hnone']
  exact ⟨_, rfl⟩

private theorem decOptSpec_absent {l : List (String × Json)}
    (hkeys : (l.map Prod.fst).Pairwise (fun a b => a ≠ b))
    (hnm : ∀ v, ("spec", v) ∉ l) :
    decOptSpec (Json.mkObj l) = Except.ok none := by
  obtain ⟨e, he⟩ := getObjVal?_mkObj_error hkeys hnm
  simp only [decOptSpec, he]

private theorem decOptSpec_present {l : List (String × Json)} {s : SpecConfig}
    (hkeys : (l.map Prod.fst).Pairwise (fun a b => a ≠ b))
    (hm : ("spec", jSpecConfig s) ∈ l) :
    decOptSpec (Json.mkObj l) = Except.ok (some s) := by
  simp only [decOptSpec, getObjVal?_mkObj hkeys hm]
  have hv : jSpecConfig s ≠ Json.null := by
    intro h
    simp only [jSpecConfig, Json.mkObj] at h
    exact Json.noConfusion h
  split
  · next hn =>
      injection hn with hn
      exact absurd hn hv
  · next v h2 =>
      injection h2 with h2
      rw [← h2, decSpecConfig_jSpecConfig]
      rfl
  · next herr => exact nomatch herr

private theorem optFieldNat_absent {l : List (String × Json)} {k : String}
    (hkeys : (l.map Prod.fst).Pairwise (fun a b => a ≠ b))
    (hnm : ∀ v, (k, v) ∉ l) :
    optFieldNat (Json.mkObj l) k = Except.ok none := by
  obtain ⟨e, he⟩ := getObjVal?_mkObj_error hkeys hnm
  simp only [optFieldNat, he]
/-! ### Generic field bridges -/

private theorem mkObj_ne_null (l : List (String × Json)) :
    Json.mkObj l ≠ Json.null := by
  intro h
  simp only [Json.mkObj] at h
  exact Json.noConfusion h

private theorem jApalacheConfig_ne_null (c : ApalacheConfig) :
    jApalacheConfig c ≠ Json.null := by
  intro h
  simp only [jApalacheConfig, Json.mkObj] at h
  exact Json.noConfusion h

private theorem jTraceConfig_ne_null (t : TraceConfig) :
    jTraceConfig t ≠ Json.null := by
  intro h
  simp only [jTraceConfig, Json.mkObj] at h
  exact Json.noConfusion h

private theorem jSpecConfig_ne_null (s : SpecConfig) :
    jSpecConfig s ≠ Json.null := by
  intro h
  simp only [jSpecConfig, Json.mkObj] at h
  exact Json.noConfusion h

private theorem jOptField_some {l : List (String × Json)} {k : String} {v : Json}
    (hkeys : (l.map Prod.fst).Pairwise (fun a b => a ≠ b)) (hm : (k, v) ∈ l)
    (hv : v ≠ Json.null) :
    jOptField (Json.mkObj l) k = Except.ok (some v) := by
  simp only [jOptField, getObjVal?_mkObj hkeys hm]

theorem reqField_of_field {l : List (String × Json)} {k : String} {v : Json}
    {f : Json → Dec α} {r : α}
    (hkeys : (l.map Prod.fst).Pairwise (fun a b => a ≠ b)) (hm : (k, v) ∈ l)
    (hv : v ≠ Json.null) (hf : f v = Except.ok r) :
    reqField (Json.mkObj l) k f = Except.ok r := by
  rw [show reqField (Json.mkObj l) k f =
      (match jOptField (Json.mkObj l) k with
       | .ok (some v) => f v
       | .ok none => derr s!"missing field: {k}"
       | .error e => .error e) from rfl,
      jOptField_some hkeys hm hv]
  exact hf

private theorem apField {l : List (String × Json)} {cfg : ApalacheConfig}
    (hkeys : (l.map Prod.fst).Pairwise (fun a b => a ≠ b))
    (hm : ("apalacheConfig", jApalacheConfig cfg) ∈ l) :
    reqField (Json.mkObj l) "apalacheConfig" decApalacheConfig = Except.ok cfg :=
  reqField_of_field hkeys hm (jApalacheConfig_ne_null cfg)
    (decApalacheConfig_jApalacheConfig cfg)

private theorem tcfgField {l : List (String × Json)} {t : TraceConfig}
    (hkeys : (l.map Prod.fst).Pairwise (fun a b => a ≠ b))
    (hm : ("traceConfig", jTraceConfig t) ∈ l) :
    reqField (Json.mkObj l) "traceConfig" decTraceConfig = Except.ok t :=
  reqField_of_field hkeys hm (jTraceConfig_ne_null t)
    (decTraceConfig_jTraceConfig t)

/-! ### Client message round-trip -/

/-- Wire well-formedness for client messages: value-carrying fields bounded. -/
def ClientOk : ClientMessage → Prop
  | .exploreAssumeState st => mapOkBounded st
  | .reportState st => mapOkBounded st
  | _ => True

/-- Client message equality up to `valEq` at value positions. -/
def ClientEquiv : ClientMessage → ClientMessage → Prop
  | .exploreAssumeState a, .exploreAssumeState b => mapEqV a b
  | .reportState a, .reportState b => mapEqV a b
  | a, b => a = b

/-- **§6.6 client round-trip**: decoding an encoded client message yields an
equivalent message. For constructors without value positions this is exact:
`decodeClient (encodeClient m) = Except.ok m`. -/
theorem decodeClient_encodeClient :
    ∀ m : ClientMessage, ClientOk m →
      ∃ m', decodeClient (encodeClient m) = Except.ok m' ∧ ClientEquiv m m' := by
  intro m hm
  cases m with
  | register cfg spec tcfg =>
      refine ⟨.register cfg spec tcfg, ?_, rfl⟩
      have hkeys : (([
        ("apalacheConfig", jApalacheConfig cfg),
        ("proto_step", Json.str "register"),
        ("spec", optJson (jSpecConfig <$> spec)),
        ("traceConfig", jTraceConfig tcfg)] : List (String × Json)).map Prod.fst).Pairwise
          (fun a b => a ≠ b) := by simp
      have mt : ("proto_step", Json.str "register") ∈ ([
        ("apalacheConfig", jApalacheConfig cfg),
        ("proto_step", Json.str "register"),
        ("spec", optJson (jSpecConfig <$> spec)),
        ("traceConfig", jTraceConfig tcfg)] : List (String × Json)) := by simp
      have ma : ("apalacheConfig", jApalacheConfig cfg) ∈ ([
        ("apalacheConfig", jApalacheConfig cfg),
        ("proto_step", Json.str "register"),
        ("spec", optJson (jSpecConfig <$> spec)),
        ("traceConfig", jTraceConfig tcfg)] : List (String × Json)) := by simp
      have ms : ("spec", optJson (jSpecConfig <$> spec)) ∈ ([
        ("apalacheConfig", jApalacheConfig cfg),
        ("proto_step", Json.str "register"),
        ("spec", optJson (jSpecConfig <$> spec)),
        ("traceConfig", jTraceConfig tcfg)] : List (String × Json)) := by simp
      have mc : ("traceConfig", jTraceConfig tcfg) ∈ ([
        ("apalacheConfig", jApalacheConfig cfg),
        ("proto_step", Json.str "register"),
        ("spec", optJson (jSpecConfig <$> spec)),
        ("traceConfig", jTraceConfig tcfg)] : List (String × Json)) := by simp
      simp only [encodeClient, decodeClient, reqStr]
      rw [str_of_mkObj hkeys mt, apField hkeys ma, decOptSpec_of_field hkeys ms,
          tcfgField hkeys mc]
      rfl
  | registerTraces cfg paths =>
      refine ⟨.registerTraces cfg paths, ?_, rfl⟩
      have hkeys : (([
        ("apalacheConfig", jApalacheConfig cfg),
        ("itfTracePaths", Json.arr (strsJson paths |>.toArray)),
        ("proto_step", Json.str "register_traces")] : List (String × Json)).map Prod.fst).Pairwise
          (fun a b => a ≠ b) := by simp
      have mt : ("proto_step", Json.str "register_traces") ∈ ([
        ("apalacheConfig", jApalacheConfig cfg),
        ("itfTracePaths", Json.arr (strsJson paths |>.toArray)),
        ("proto_step", Json.str "register_traces")] : List (String × Json)) := by simp
      have ma : ("apalacheConfig", jApalacheConfig cfg) ∈ ([
        ("apalacheConfig", jApalacheConfig cfg),
        ("itfTracePaths", Json.arr (strsJson paths |>.toArray)),
        ("proto_step", Json.str "register_traces")] : List (String × Json)) := by simp
      have mp : ("itfTracePaths", Json.arr (strsJson paths |>.toArray)) ∈ ([
        ("apalacheConfig", jApalacheConfig cfg),
        ("itfTracePaths", Json.arr (strsJson paths |>.toArray)),
        ("proto_step", Json.str "register_traces")] : List (String × Json)) := by simp
      simp only [encodeClient, decodeClient, reqStr]
      rw [str_of_mkObj hkeys mt, apField hkeys ma, strs_of_mkObj hkeys mp]
      rfl
  | registerGenTraces cfg dest spec tcfg =>
      refine ⟨.registerGenTraces cfg dest spec tcfg, ?_, rfl⟩
      have hkeys : (([
        ("apalacheConfig", jApalacheConfig cfg),
        ("destPath", optStr dest),
        ("proto_step", Json.str "register_trace_gen"),
        ("spec", optJson (jSpecConfig <$> spec)),
        ("traceConfig", jTraceConfig tcfg)] : List (String × Json)).map Prod.fst).Pairwise
          (fun a b => a ≠ b) := by simp
      have mt : ("proto_step", Json.str "register_trace_gen") ∈ ([
        ("apalacheConfig", jApalacheConfig cfg),
        ("destPath", optStr dest),
        ("proto_step", Json.str "register_trace_gen"),
        ("spec", optJson (jSpecConfig <$> spec)),
        ("traceConfig", jTraceConfig tcfg)] : List (String × Json)) := by simp
      have ma : ("apalacheConfig", jApalacheConfig cfg) ∈ ([
        ("apalacheConfig", jApalacheConfig cfg),
        ("destPath", optStr dest),
        ("proto_step", Json.str "register_trace_gen"),
        ("spec", optJson (jSpecConfig <$> spec)),
        ("traceConfig", jTraceConfig tcfg)] : List (String × Json)) := by simp
      have md : ("destPath", optStr dest) ∈ ([
        ("apalacheConfig", jApalacheConfig cfg),
        ("destPath", optStr dest),
        ("proto_step", Json.str "register_trace_gen"),
        ("spec", optJson (jSpecConfig <$> spec)),
        ("traceConfig", jTraceConfig tcfg)] : List (String × Json)) := by simp
      have ms : ("spec", optJson (jSpecConfig <$> spec)) ∈ ([
        ("apalacheConfig", jApalacheConfig cfg),
        ("destPath", optStr dest),
        ("proto_step", Json.str "register_trace_gen"),
        ("spec", optJson (jSpecConfig <$> spec)),
        ("traceConfig", jTraceConfig tcfg)] : List (String × Json)) := by simp
      have mc : ("traceConfig", jTraceConfig tcfg) ∈ ([
        ("apalacheConfig", jApalacheConfig cfg),
        ("destPath", optStr dest),
        ("proto_step", Json.str "register_trace_gen"),
        ("spec", optJson (jSpecConfig <$> spec)),
        ("traceConfig", jTraceConfig tcfg)] : List (String × Json)) := by simp
      simp only [encodeClient, decodeClient, reqStr]
      rw [str_of_mkObj hkeys mt, apField hkeys ma, optFieldStr_mkObj hkeys md,
          decOptSpec_of_field hkeys ms, tcfgField hkeys mc]
      rfl
  | registerExplore spec exports invariants maxSteps =>
      refine ⟨.registerExplore spec exports invariants maxSteps, ?_, rfl⟩
      have hkeys : (([
        ("exports", Json.arr (strsJson exports |>.toArray)),
        ("invariants", Json.arr (strsJson invariants |>.toArray)),
        ("maxSteps", Json.num (JsonNumber.fromNat maxSteps)),
        ("proto_step", Json.str "register_explore"),
        ("spec", jSpecConfig spec)] : List (String × Json)).map Prod.fst).Pairwise
          (fun a b => a ≠ b) := by simp
      have mt : ("proto_step", Json.str "register_explore") ∈ ([
        ("exports", Json.arr (strsJson exports |>.toArray)),
        ("invariants", Json.arr (strsJson invariants |>.toArray)),
        ("maxSteps", Json.num (JsonNumber.fromNat maxSteps)),
        ("proto_step", Json.str "register_explore"),
        ("spec", jSpecConfig spec)] : List (String × Json)) := by simp
      have me : ("exports", Json.arr (strsJson exports |>.toArray)) ∈ ([
        ("exports", Json.arr (strsJson exports |>.toArray)),
        ("invariants", Json.arr (strsJson invariants |>.toArray)),
        ("maxSteps", Json.num (JsonNumber.fromNat maxSteps)),
        ("proto_step", Json.str "register_explore"),
        ("spec", jSpecConfig spec)] : List (String × Json)) := by simp
      have mi : ("invariants", Json.arr (strsJson invariants |>.toArray)) ∈ ([
        ("exports", Json.arr (strsJson exports |>.toArray)),
        ("invariants", Json.arr (strsJson invariants |>.toArray)),
        ("maxSteps", Json.num (JsonNumber.fromNat maxSteps)),
        ("proto_step", Json.str "register_explore"),
        ("spec", jSpecConfig spec)] : List (String × Json)) := by simp
      have mm : ("maxSteps", Json.num (JsonNumber.fromNat maxSteps)) ∈ ([
        ("exports", Json.arr (strsJson exports |>.toArray)),
        ("invariants", Json.arr (strsJson invariants |>.toArray)),
        ("maxSteps", Json.num (JsonNumber.fromNat maxSteps)),
        ("proto_step", Json.str "register_explore"),
        ("spec", jSpecConfig spec)] : List (String × Json)) := by simp
      have ms : ("spec", jSpecConfig spec) ∈ ([
        ("exports", Json.arr (strsJson exports |>.toArray)),
        ("invariants", Json.arr (strsJson invariants |>.toArray)),
        ("maxSteps", Json.num (JsonNumber.fromNat maxSteps)),
        ("proto_step", Json.str "register_explore"),
        ("spec", jSpecConfig spec)] : List (String × Json)) := by simp
      simp only [encodeClient, decodeClient, reqStr, reqNat]
      rw [str_of_mkObj hkeys mt, strs_of_mkObj hkeys me, strs_of_mkObj hkeys mi,
          nat_of_mkObj hkeys mm, reqField_of_field hkeys ms (jSpecConfig_ne_null spec)
          (decSpecConfig_jSpecConfig spec)]
      rfl
  | registerExploreSession spec exports invariants =>
      refine ⟨.registerExploreSession spec exports invariants, ?_, rfl⟩
      have hkeys : (([
        ("exports", Json.arr (strsJson exports |>.toArray)),
        ("invariants", Json.arr (strsJson invariants |>.toArray)),
        ("proto_step", Json.str "register_explore_session"),
        ("spec", jSpecConfig spec)] : List (String × Json)).map Prod.fst).Pairwise
          (fun a b => a ≠ b) := by simp
      have mt : ("proto_step", Json.str "register_explore_session") ∈ ([
        ("exports", Json.arr (strsJson exports |>.toArray)),
        ("invariants", Json.arr (strsJson invariants |>.toArray)),
        ("proto_step", Json.str "register_explore_session"),
        ("spec", jSpecConfig spec)] : List (String × Json)) := by simp
      have me : ("exports", Json.arr (strsJson exports |>.toArray)) ∈ ([
        ("exports", Json.arr (strsJson exports |>.toArray)),
        ("invariants", Json.arr (strsJson invariants |>.toArray)),
        ("proto_step", Json.str "register_explore_session"),
        ("spec", jSpecConfig spec)] : List (String × Json)) := by simp
      have mi : ("invariants", Json.arr (strsJson invariants |>.toArray)) ∈ ([
        ("exports", Json.arr (strsJson exports |>.toArray)),
        ("invariants", Json.arr (strsJson invariants |>.toArray)),
        ("proto_step", Json.str "register_explore_session"),
        ("spec", jSpecConfig spec)] : List (String × Json)) := by simp
      have ms : ("spec", jSpecConfig spec) ∈ ([
        ("exports", Json.arr (strsJson exports |>.toArray)),
        ("invariants", Json.arr (strsJson invariants |>.toArray)),
        ("proto_step", Json.str "register_explore_session"),
        ("spec", jSpecConfig spec)] : List (String × Json)) := by simp
      simp only [encodeClient, decodeClient, reqStr]
      rw [str_of_mkObj hkeys mt, strs_of_mkObj hkeys me, strs_of_mkObj hkeys mi,
          reqField_of_field hkeys ms (jSpecConfig_ne_null spec)
          (decSpecConfig_jSpecConfig spec)]
      rfl
  | registerValidate cfg bound spec =>
      cases spec with
      | none =>
          refine ⟨.registerValidate cfg bound none, ?_, rfl⟩
          have hkeys : (([
            ("apalacheConfig", jApalacheConfig cfg), ("bound", Json.num bound),
            ("proto_step", Json.str "register_validate")] : List (String × Json)).map Prod.fst).Pairwise
              (fun a b => a ≠ b) := by simp
          have mt : ("proto_step", Json.str "register_validate") ∈ ([
            ("apalacheConfig", jApalacheConfig cfg), ("bound", Json.num bound),
            ("proto_step", Json.str "register_validate")] : List (String × Json)) := by simp
          have ma : ("apalacheConfig", jApalacheConfig cfg) ∈ ([
            ("apalacheConfig", jApalacheConfig cfg), ("bound", Json.num bound),
            ("proto_step", Json.str "register_validate")] : List (String × Json)) := by simp
          have mb : ("bound", Json.num (JsonNumber.fromNat bound)) ∈ ([
            ("apalacheConfig", jApalacheConfig cfg), ("bound", Json.num bound),
            ("proto_step", Json.str "register_validate")] : List (String × Json)) := by simp
          have hno : ∀ v, ("spec", v) ∉ ([
            ("apalacheConfig", jApalacheConfig cfg), ("bound", Json.num bound),
            ("proto_step", Json.str "register_validate")] : List (String × Json)) := by
            intro v hv
            have : "spec" ∈ ([
              ("apalacheConfig", jApalacheConfig cfg), ("bound", Json.num bound),
              ("proto_step", Json.str "register_validate")] : List (String × Json)).map Prod.fst :=
              List.mem_map_of_mem hv
            simp at this
          have henc : encodeClient (ClientMessage.registerValidate cfg bound none) =
              Json.mkObj ([
                ("apalacheConfig", jApalacheConfig cfg), ("bound", Json.num bound),
                ("proto_step", Json.str "register_validate")]) := by
            simp [encodeClient]
          simp only [henc, decodeClient, reqStr, reqNat]
          rw [str_of_mkObj hkeys mt, apField hkeys ma, nat_of_mkObj hkeys mb,
              decOptSpec_absent hkeys hno]
          rfl
      | some s =>
          refine ⟨.registerValidate cfg bound (some s), ?_, rfl⟩
          have hkeys : ((([
            ("apalacheConfig", jApalacheConfig cfg), ("bound", Json.num bound),
            ("proto_step", Json.str "register_validate")] ++
            [("spec", jSpecConfig s)]) : List (String × Json)).map Prod.fst).Pairwise
              (fun a b => a ≠ b) := by simp
          have mt : ("proto_step", Json.str "register_validate") ∈ ([
            ("apalacheConfig", jApalacheConfig cfg), ("bound", Json.num bound),
            ("proto_step", Json.str "register_validate")] ++
            [("spec", jSpecConfig s)] : List (String × Json)) := by simp
          have ma : ("apalacheConfig", jApalacheConfig cfg) ∈ ([
            ("apalacheConfig", jApalacheConfig cfg), ("bound", Json.num bound),
            ("proto_step", Json.str "register_validate")] ++
            [("spec", jSpecConfig s)] : List (String × Json)) := by simp
          have mb : ("bound", Json.num (JsonNumber.fromNat bound)) ∈ ([
            ("apalacheConfig", jApalacheConfig cfg), ("bound", Json.num bound),
            ("proto_step", Json.str "register_validate")] ++
            [("spec", jSpecConfig s)] : List (String × Json)) := by simp
          have ms : ("spec", jSpecConfig s) ∈ ([
            ("apalacheConfig", jApalacheConfig cfg), ("bound", Json.num bound),
            ("proto_step", Json.str "register_validate")] ++
            [("spec", jSpecConfig s)] : List (String × Json)) := by simp
          have henc : encodeClient (ClientMessage.registerValidate cfg bound (some s)) =
              Json.mkObj ([
                ("apalacheConfig", jApalacheConfig cfg), ("bound", Json.num bound),
                ("proto_step", Json.str "register_validate")] ++
                [("spec", jSpecConfig s)]) := by
            simp [encodeClient]
          simp only [henc, decodeClient, reqStr, reqNat]
          rw [str_of_mkObj hkeys mt, apField hkeys ma, nat_of_mkObj hkeys mb,
              decOptSpec_present hkeys ms]
          rfl
  | registerValidateAsync cfg bound spec =>
      cases spec with
      | none =>
          refine ⟨.registerValidateAsync cfg bound none, ?_, rfl⟩
          have hkeys : (([
            ("apalacheConfig", jApalacheConfig cfg), ("bound", Json.num bound),
            ("proto_step", Json.str "register_validate_async")] : List (String × Json)).map Prod.fst).Pairwise
              (fun a b => a ≠ b) := by simp
          have mt : ("proto_step", Json.str "register_validate_async") ∈ ([
            ("apalacheConfig", jApalacheConfig cfg), ("bound", Json.num bound),
            ("proto_step", Json.str "register_validate_async")] : List (String × Json)) := by simp
          have ma : ("apalacheConfig", jApalacheConfig cfg) ∈ ([
            ("apalacheConfig", jApalacheConfig cfg), ("bound", Json.num bound),
            ("proto_step", Json.str "register_validate_async")] : List (String × Json)) := by simp
          have mb : ("bound", Json.num (JsonNumber.fromNat bound)) ∈ ([
            ("apalacheConfig", jApalacheConfig cfg), ("bound", Json.num bound),
            ("proto_step", Json.str "register_validate_async")] : List (String × Json)) := by simp
          have hno : ∀ v, ("spec", v) ∉ ([
            ("apalacheConfig", jApalacheConfig cfg), ("bound", Json.num bound),
            ("proto_step", Json.str "register_validate_async")] : List (String × Json)) := by
            intro v hv
            have : "spec" ∈ ([
              ("apalacheConfig", jApalacheConfig cfg), ("bound", Json.num bound),
              ("proto_step", Json.str "register_validate_async")] : List (String × Json)).map Prod.fst :=
              List.mem_map_of_mem hv
            simp at this
          have henc : encodeClient (ClientMessage.registerValidateAsync cfg bound none) =
              Json.mkObj ([
                ("apalacheConfig", jApalacheConfig cfg), ("bound", Json.num bound),
                ("proto_step", Json.str "register_validate_async")]) := by
            simp [encodeClient]
          simp only [henc, decodeClient, reqStr, reqNat]
          rw [str_of_mkObj hkeys mt, apField hkeys ma, nat_of_mkObj hkeys mb,
              decOptSpec_absent hkeys hno]
          rfl
      | some s =>
          refine ⟨.registerValidateAsync cfg bound (some s), ?_, rfl⟩
          have hkeys : ((([
            ("apalacheConfig", jApalacheConfig cfg), ("bound", Json.num bound),
            ("proto_step", Json.str "register_validate_async")] ++
            [("spec", jSpecConfig s)]) : List (String × Json)).map Prod.fst).Pairwise
              (fun a b => a ≠ b) := by simp
          have mt : ("proto_step", Json.str "register_validate_async") ∈ ([
            ("apalacheConfig", jApalacheConfig cfg), ("bound", Json.num bound),
            ("proto_step", Json.str "register_validate_async")] ++
            [("spec", jSpecConfig s)] : List (String × Json)) := by simp
          have ma : ("apalacheConfig", jApalacheConfig cfg) ∈ ([
            ("apalacheConfig", jApalacheConfig cfg), ("bound", Json.num bound),
            ("proto_step", Json.str "register_validate_async")] ++
            [("spec", jSpecConfig s)] : List (String × Json)) := by simp
          have mb : ("bound", Json.num (JsonNumber.fromNat bound)) ∈ ([
            ("apalacheConfig", jApalacheConfig cfg), ("bound", Json.num bound),
            ("proto_step", Json.str "register_validate_async")] ++
            [("spec", jSpecConfig s)] : List (String × Json)) := by simp
          have ms : ("spec", jSpecConfig s) ∈ ([
            ("apalacheConfig", jApalacheConfig cfg), ("bound", Json.num bound),
            ("proto_step", Json.str "register_validate_async")] ++
            [("spec", jSpecConfig s)] : List (String × Json)) := by simp
          have henc : encodeClient (ClientMessage.registerValidateAsync cfg bound (some s)) =
              Json.mkObj ([
                ("apalacheConfig", jApalacheConfig cfg), ("bound", Json.num bound),
                ("proto_step", Json.str "register_validate_async")] ++
                [("spec", jSpecConfig s)]) := by
            simp [encodeClient]
          simp only [henc, decodeClient, reqStr, reqNat]
          rw [str_of_mkObj hkeys mt, apField hkeys ma, nat_of_mkObj hkeys mb,
              decOptSpec_present hkeys ms]
          rfl
  | registerGenTracesAsync cfg dest spec tcfg =>
      refine ⟨.registerGenTracesAsync cfg dest spec tcfg, ?_, rfl⟩
      have hkeys : (([
        ("apalacheConfig", jApalacheConfig cfg),
        ("destPath", optStr dest),
        ("proto_step", Json.str "register_trace_gen_async"),
        ("spec", optJson (jSpecConfig <$> spec)),
        ("traceConfig", jTraceConfig tcfg)] : List (String × Json)).map Prod.fst).Pairwise
          (fun a b => a ≠ b) := by simp
      have mt : ("proto_step", Json.str "register_trace_gen_async") ∈ ([
        ("apalacheConfig", jApalacheConfig cfg),
        ("destPath", optStr dest),
        ("proto_step", Json.str "register_trace_gen_async"),
        ("spec", optJson (jSpecConfig <$> spec)),
        ("traceConfig", jTraceConfig tcfg)] : List (String × Json)) := by simp
      have ma : ("apalacheConfig", jApalacheConfig cfg) ∈ ([
        ("apalacheConfig", jApalacheConfig cfg),
        ("destPath", optStr dest),
        ("proto_step", Json.str "register_trace_gen_async"),
        ("spec", optJson (jSpecConfig <$> spec)),
        ("traceConfig", jTraceConfig tcfg)] : List (String × Json)) := by simp
      have md : ("destPath", optStr dest) ∈ ([
        ("apalacheConfig", jApalacheConfig cfg),
        ("destPath", optStr dest),
        ("proto_step", Json.str "register_trace_gen_async"),
        ("spec", optJson (jSpecConfig <$> spec)),
        ("traceConfig", jTraceConfig tcfg)] : List (String × Json)) := by simp
      have ms : ("spec", optJson (jSpecConfig <$> spec)) ∈ ([
        ("apalacheConfig", jApalacheConfig cfg),
        ("destPath", optStr dest),
        ("proto_step", Json.str "register_trace_gen_async"),
        ("spec", optJson (jSpecConfig <$> spec)),
        ("traceConfig", jTraceConfig tcfg)] : List (String × Json)) := by simp
      have mc : ("traceConfig", jTraceConfig tcfg) ∈ ([
        ("apalacheConfig", jApalacheConfig cfg),
        ("destPath", optStr dest),
        ("proto_step", Json.str "register_trace_gen_async"),
        ("spec", optJson (jSpecConfig <$> spec)),
        ("traceConfig", jTraceConfig tcfg)] : List (String × Json)) := by simp
      simp only [encodeClient, decodeClient, reqStr]
      rw [str_of_mkObj hkeys mt, apField hkeys ma, optFieldStr_mkObj hkeys md,
          decOptSpec_of_field hkeys ms, tcfgField hkeys mc]
      rfl
  | queryJob jobId =>
      refine ⟨.queryJob jobId, ?_, rfl⟩
      have hkeys : (([("jobId", Json.str jobId), ("proto_step", Json.str "query_job")] :
          List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have mt : ("proto_step", Json.str "query_job") ∈ ([("jobId", Json.str jobId),
          ("proto_step", Json.str "query_job")] : List (String × Json)) := by simp
      have mj : ("jobId", Json.str jobId) ∈ ([("jobId", Json.str jobId),
          ("proto_step", Json.str "query_job")] : List (String × Json)) := by simp
      simp only [encodeClient, decodeClient, reqStr]
      rw [str_of_mkObj hkeys mt, str_of_mkObj hkeys mj]
      rfl
  | awaitJob jobId timeout =>
      cases timeout with
      | none =>
          refine ⟨.awaitJob jobId none, ?_, rfl⟩
          have hkeys : (([("jobId", Json.str jobId), ("proto_step", Json.str "await_job")] :
              List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
          have mt : ("proto_step", Json.str "await_job") ∈ ([("jobId", Json.str jobId),
              ("proto_step", Json.str "await_job")] : List (String × Json)) := by simp
          have mj : ("jobId", Json.str jobId) ∈ ([("jobId", Json.str jobId),
              ("proto_step", Json.str "await_job")] : List (String × Json)) := by simp
          have hno : ∀ v, ("timeoutSecs", v) ∉ ([("jobId", Json.str jobId),
              ("proto_step", Json.str "await_job")] : List (String × Json)) := by
            intro v hv
            have : "timeoutSecs" ∈ ([("jobId", Json.str jobId),
                ("proto_step", Json.str "await_job")] : List (String × Json)).map Prod.fst :=
              List.mem_map_of_mem hv
            simp at this
          have henc : encodeClient (ClientMessage.awaitJob jobId none) =
              Json.mkObj ([("jobId", Json.str jobId), ("proto_step", Json.str "await_job")]) := by
            simp [encodeClient]
          simp only [henc, decodeClient, reqStr]
          rw [str_of_mkObj hkeys mt, str_of_mkObj hkeys mj, optFieldNat_absent hkeys hno]
          rfl
      | some t =>
          refine ⟨.awaitJob jobId (some t), ?_, rfl⟩
          have hkeys : ((([("jobId", Json.str jobId), ("proto_step", Json.str "await_job")] ++
              [("timeoutSecs", Json.num t)]) : List (String × Json)).map Prod.fst).Pairwise
              (fun a b => a ≠ b) := by simp
          have mt : ("proto_step", Json.str "await_job") ∈ ([("jobId", Json.str jobId),
              ("proto_step", Json.str "await_job")] ++
              [("timeoutSecs", Json.num t)] : List (String × Json)) := by simp
          have mj : ("jobId", Json.str jobId) ∈ ([("jobId", Json.str jobId),
              ("proto_step", Json.str "await_job")] ++
              [("timeoutSecs", Json.num t)] : List (String × Json)) := by simp
          have mm : ("timeoutSecs", Json.num (JsonNumber.fromNat t)) ∈ ([
              ("jobId", Json.str jobId), ("proto_step", Json.str "await_job")] ++
              [("timeoutSecs", Json.num t)] : List (String × Json)) := by simp
          simp only [encodeClient, decodeClient, reqStr]
          rw [str_of_mkObj hkeys mt, str_of_mkObj hkeys mj, optFieldNat_mkObj hkeys mm]
          rfl
  | cancelJob jobId =>
      refine ⟨.cancelJob jobId, ?_, rfl⟩
      have hkeys : (([("jobId", Json.str jobId), ("proto_step", Json.str "cancel_job")] :
          List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have mt : ("proto_step", Json.str "cancel_job") ∈ ([("jobId", Json.str jobId),
          ("proto_step", Json.str "cancel_job")] : List (String × Json)) := by simp
      have mj : ("jobId", Json.str jobId) ∈ ([("jobId", Json.str jobId),
          ("proto_step", Json.str "cancel_job")] : List (String × Json)) := by simp
      simp only [encodeClient, decodeClient, reqStr]
      rw [str_of_mkObj hkeys mt, str_of_mkObj hkeys mj]
      rfl
  | exploreAssumeTransition tid =>
      refine ⟨.exploreAssumeTransition tid, ?_, rfl⟩
      have hkeys : (([("proto_step", Json.str "explore_assume_transition"),
          ("transitionId", Json.num tid)] :
          List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have mt : ("proto_step", Json.str "explore_assume_transition") ∈ ([
          ("proto_step", Json.str "explore_assume_transition"),
          ("transitionId", Json.num tid)] : List (String × Json)) := by simp
      have mi : ("transitionId", Json.num (JsonNumber.fromNat tid)) ∈ ([
          ("proto_step", Json.str "explore_assume_transition"),
          ("transitionId", Json.num tid)] : List (String × Json)) := by simp
      simp only [encodeClient, decodeClient, reqStr, reqNat]
      rw [str_of_mkObj hkeys mt, nat_of_mkObj hkeys mi]
      rfl
  | exploreNextStep =>
      refine ⟨.exploreNextStep, ?_, rfl⟩
      have hkeys : (([("proto_step", Json.str "explore_next_step")] :
          List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have mt : ("proto_step", Json.str "explore_next_step") ∈ ([
          ("proto_step", Json.str "explore_next_step")] : List (String × Json)) := by simp
      simp only [encodeClient, decodeClient]
      rw [str_of_mkObj hkeys mt]
      rfl
  | exploreQueryState =>
      refine ⟨.exploreQueryState, ?_, rfl⟩
      have hkeys : (([("proto_step", Json.str "explore_query_state")] :
          List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have mt : ("proto_step", Json.str "explore_query_state") ∈ ([
          ("proto_step", Json.str "explore_query_state")] : List (String × Json)) := by simp
      simp only [encodeClient, decodeClient]
      rw [str_of_mkObj hkeys mt]
      rfl
  | exploreCheckInvariant iid =>
      refine ⟨.exploreCheckInvariant iid, ?_, rfl⟩
      have hkeys : (([("invariantId", Json.num iid),
          ("proto_step", Json.str "explore_check_invariant")] :
          List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have mt : ("proto_step", Json.str "explore_check_invariant") ∈ ([
          ("invariantId", Json.num iid),
          ("proto_step", Json.str "explore_check_invariant")] : List (String × Json)) := by simp
      have mi : ("invariantId", Json.num (JsonNumber.fromNat iid)) ∈ ([
          ("invariantId", Json.num iid),
          ("proto_step", Json.str "explore_check_invariant")] : List (String × Json)) := by simp
      simp only [encodeClient, decodeClient, reqStr, reqNat]
      rw [str_of_mkObj hkeys mt, nat_of_mkObj hkeys mi]
      rfl
  | exploreAssumeState st =>
      obtain ⟨ws, hws, hmeq⟩ := decStateMap_jStateMap st hm
      refine ⟨.exploreAssumeState ws, ?_, hmeq⟩
      have hkeys : (([("proto_step", Json.str "explore_assume_state"), ("state", jStateMap st)] :
          List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have mt : ("proto_step", Json.str "explore_assume_state") ∈ ([
          ("proto_step", Json.str "explore_assume_state"), ("state", jStateMap st)] :
          List (String × Json)) := by simp
      have ms : ("state", Json.mkObj (encMap st)) ∈ ([
          ("proto_step", Json.str "explore_assume_state"), ("state", jStateMap st)] :
          List (String × Json)) := by simp [jStateMap]
      simp only [jStateMap] at hws
      simp only [encodeClient, decodeClient, reqStr]
      rw [str_of_mkObj hkeys mt, decOptStateMap_of_field hkeys ms, hws]
      rfl
  | exploreRollback sid =>
      refine ⟨.exploreRollback sid, ?_, rfl⟩
      have hkeys : (([("proto_step", Json.str "explore_rollback"),
          ("snapshotId", Json.num sid)] :
          List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have mt : ("proto_step", Json.str "explore_rollback") ∈ ([
          ("proto_step", Json.str "explore_rollback"),
          ("snapshotId", Json.num sid)] : List (String × Json)) := by simp
      have mi : ("snapshotId", Json.num (JsonNumber.fromNat sid)) ∈ ([
          ("proto_step", Json.str "explore_rollback"),
          ("snapshotId", Json.num sid)] : List (String × Json)) := by simp
      simp only [encodeClient, decodeClient, reqStr, reqNat]
      rw [str_of_mkObj hkeys mt, nat_of_mkObj hkeys mi]
      rfl
  | exploreDone =>
      refine ⟨.exploreDone, ?_, rfl⟩
      have hkeys : (([("proto_step", Json.str "explore_done")] :
          List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have mt : ("proto_step", Json.str "explore_done") ∈ ([
          ("proto_step", Json.str "explore_done")] : List (String × Json)) := by simp
      simp only [encodeClient, decodeClient]
      rw [str_of_mkObj hkeys mt]
      rfl
  | reportState st =>
      obtain ⟨ws, hws, hmeq⟩ := decStateMap_jStateMap st hm
      refine ⟨.reportState ws, ?_, hmeq⟩
      have hkeys : (([("proto_step", Json.str "report_state"), ("state", jStateMap st)] :
          List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have mt : ("proto_step", Json.str "report_state") ∈ ([
          ("proto_step", Json.str "report_state"), ("state", jStateMap st)] :
          List (String × Json)) := by simp
      have ms : ("state", Json.mkObj (encMap st)) ∈ ([
          ("proto_step", Json.str "report_state"), ("state", jStateMap st)] :
          List (String × Json)) := by simp [jStateMap]
      simp only [jStateMap] at hws
      simp only [encodeClient, decodeClient, reqStr]
      rw [str_of_mkObj hkeys mt, decOptStateMap_of_field hkeys ms, hws]
      rfl
/-! ### Mirror sub-codec round-trips -/

private theorem str_ne_null (s : String) : Json.str s ≠ Json.null := by
  intro h
  exact Json.noConfusion h

private theorem arr_ne_null (as : Array Json) : Json.arr as ≠ Json.null := by
  intro h
  exact Json.noConfusion h

private theorem decValidateResult_jValidateResult (r : ValidateResult) :
    decValidateResult (jValidateResult r) = Except.ok r := by
  cases r with
  | valid => rfl
  | invalid msg =>
      simp only [jValidateResult, Json.mkObj, decValidateResult, toList_ofList_singleton]

private theorem decJobKind_jJobKind (k : JobKind) : decJobKind (jJobKind k) = Except.ok k := by
  cases k <;> rfl

private theorem decJobPhase_jJobPhase (p : JobPhase) : decJobPhase (jJobPhase p) = Except.ok p := by
  cases p <;> rfl

private theorem decDiffKind_jDiffKind (k : DiffKind) : decDiffKind (jDiffKind k) = Except.ok k := by
  cases k <;> rfl

private theorem decPathSeg_jPathSeg (p : PathSeg) : decPathSeg (jPathSeg p) = Except.ok p := by
  cases p with
  | field f => simp only [jPathSeg, Json.mkObj, decPathSeg, toList_ofList_singleton]
  | index i =>
      simp only [jPathSeg, Json.mkObj, JsonNumber.fromNat, decPathSeg,
        toList_ofList_singleton]
      have h1 : (↑i : Int).toNat = i := by omega
      rw [dif_pos (by omega), h1]

private theorem decPathArr_enc (ps : List PathSeg) :
    decPathArr (Json.arr ((ps.map jPathSeg).toArray)) = Except.ok ps := by
  induction ps with
  | nil => rfl
  | cons p rest ih =>
      have harr : ((p :: rest).map jPathSeg).toArray.toList
          = jPathSeg p :: ((rest.map jPathSeg).toArray).toList := by
        simp only [List.map_cons, List.toList_toArray]
      show List.mapM decPathSeg (((p :: rest).map jPathSeg).toArray).toList = _
      rw [harr, List.mapM_cons, decPathSeg_jPathSeg p]
      have ih2 : List.mapM decPathSeg ((rest.map jPathSeg).toArray).toList = Except.ok rest := ih
      rw [ih2]
      rfl

private theorem decValues_encValues (vs : List Value) (hb : ∀ v ∈ vs, valBounded v) :
    ∃ ws, decValues (Json.arr ((vs.map encValue).toArray)) = Except.ok ws
      ∧ listEq vs ws = true := by
  induction vs with
  | nil => exact ⟨[], rfl, by simp [listEq]⟩
  | cons v t ih =>
      obtain ⟨w, hw, hval⟩ := decodeValue_bounded v (hb v (by simp))
      obtain ⟨ws, hws, hlist⟩ := ih (fun x hx => hb x (by simp [hx]))
      have harr : ((v :: t).map encValue).toArray.toList
          = encValue v :: ((t.map encValue).toArray).toList := by
        simp only [List.map_cons, List.toList_toArray]
      refine ⟨w :: ws, ?_, ?_⟩
      · show List.mapM decodeValue (((v :: t).map encValue).toArray).toList = _
        rw [harr, List.mapM_cons]
        have hw2 : decodeValue (encValue v) = Except.ok w := hw
        have hws2 : List.mapM decodeValue ((t.map encValue).toArray).toList = Except.ok ws := hws
        rw [hw2, hws2]
        rfl
      · show listEq (v :: t) (w :: ws) = true
        rw [listEq, hval, hlist]
        rfl

private theorem decOptValueField_enc {l : List (String × Json)} {k : String} {v : Value}
    (hkeys : (l.map Prod.fst).Pairwise (fun a b => a ≠ b)) (hm : (k, encValue v) ∈ l)
    (hb : valBounded v) :
    ∃ w, decOptValueField (Json.mkObj l) k = Except.ok (some w) ∧ valEq v w = true := by
  obtain ⟨w, hw, hval⟩ := decodeValue_bounded v hb
  refine ⟨w, ?_, hval⟩
  simp only [decOptValueField, getObjVal?_mkObj hkeys hm, hw]
  rfl

private theorem decOptValueField_absent {l : List (String × Json)} {k : String}
    (hkeys : (l.map Prod.fst).Pairwise (fun a b => a ≠ b))
    (hnm : ∀ v, (k, v) ∉ l) :
    decOptValueField (Json.mkObj l) k = Except.ok none := by
  obtain ⟨e, he⟩ := getObjVal?_mkObj_error hkeys hnm
  simp only [decOptValueField, he]
/-! ### Mirror equivalences -/

def hintEquiv (h h' : DiffHint) : Prop :=
  h.kind = h'.kind ∧ h.path = h'.path ∧ optValEq h.actual h'.actual
    ∧ optValEq h.expected h'.expected

def tracesEquiv (r r' : TraceGenResult) : Prop :=
  r.itfTracePaths = r'.itfTracePaths ∧ listEq r.itfTraces r'.itfTraces = true

def jobOutcomeOk : JobOutcome → Prop
  | .genTraces r => tracesOk r
  | _ => True

def JobOutcomeEquiv : JobOutcome → JobOutcome → Prop
  | .validate r, .validate r' => r = r'
  | .genTraces r, .genTraces r' => tracesEquiv r r'
  | .infraError m, .infraError m' => m = m'
  | _, _ => False

private theorem jDiffKind_ne_null (k : DiffKind) : jDiffKind k ≠ Json.null := by
  intro h
  cases k <;> simp only [jDiffKind] at h <;> exact Json.noConfusion h

private theorem decDiffHint_jDiffHint :
    ∀ h : DiffHint, hintOk h → ∃ h', decDiffHint (jDiffHint h) = Except.ok h'
      ∧ hintEquiv h h' := by
  intro h hh
  cases has : h.actual with
  | none =>
      cases hes : h.expected with
      | none =>
          have henc : jDiffHint h = Json.mkObj [
              ("kind", jDiffKind h.kind),
              ("path", Json.arr (h.path.map jPathSeg |>.toArray))] := by
            simp [jDiffHint, has, hes]
          have hkeys : (([
              ("kind", jDiffKind h.kind),
              ("path", Json.arr (h.path.map jPathSeg |>.toArray))] :
              List (String × Json)).map Prod.fst).Pairwise
              (fun a b => a ≠ b) := by simp
          have mk : ("kind", jDiffKind h.kind) ∈ ([
              ("kind", jDiffKind h.kind),
              ("path", Json.arr (h.path.map jPathSeg |>.toArray))] :
              List (String × Json)) := by simp
          have mp : ("path", Json.arr (h.path.map jPathSeg |>.toArray)) ∈ ([
              ("kind", jDiffKind h.kind),
              ("path", Json.arr (h.path.map jPathSeg |>.toArray))] :
              List (String × Json)) := by simp
          have hnoa : ∀ v, ("actual", v) ∉ ([
              ("kind", jDiffKind h.kind),
              ("path", Json.arr (h.path.map jPathSeg |>.toArray))] :
              List (String × Json)) := by
            intro v hv
            have : "actual" ∈ ([
              ("kind", jDiffKind h.kind),
              ("path", Json.arr (h.path.map jPathSeg |>.toArray))] :
              List (String × Json)).map Prod.fst := List.mem_map_of_mem hv
            simp at this
          have hnoe : ∀ v, ("expected", v) ∉ ([
              ("kind", jDiffKind h.kind),
              ("path", Json.arr (h.path.map jPathSeg |>.toArray))] :
              List (String × Json)) := by
            intro v hv
            have : "expected" ∈ ([
              ("kind", jDiffKind h.kind),
              ("path", Json.arr (h.path.map jPathSeg |>.toArray))] :
              List (String × Json)).map Prod.fst := List.mem_map_of_mem hv
            simp at this
          refine ⟨{ kind := h.kind, path := h.path, actual := none, expected := none },
            ?_, rfl, rfl, by rw [has]; trivial, by rw [hes]; trivial⟩
          simp only [henc, decDiffHint, reqStr, reqNat]
          rw [reqField_of_field hkeys mk (jDiffKind_ne_null h.kind)
              (decDiffKind_jDiffKind h.kind),
            reqField_of_field hkeys mp (arr_ne_null _) (decPathArr_enc h.path),
            decOptValueField_absent hkeys hnoa, decOptValueField_absent hkeys hnoe]
          rfl
      | some ve =>
          have henc : jDiffHint h = Json.mkObj ([
              ("kind", jDiffKind h.kind),
              ("path", Json.arr (h.path.map jPathSeg |>.toArray))] ++
              [("expected", encValue ve)]) := by
            simp [jDiffHint, has, hes]
          have hkeys : ((([
              ("kind", jDiffKind h.kind),
              ("path", Json.arr (h.path.map jPathSeg |>.toArray))] ++
              [("expected", encValue ve)]) : List (String × Json)).map Prod.fst).Pairwise
              (fun a b => a ≠ b) := by simp
          have mk : ("kind", jDiffKind h.kind) ∈ ([
              ("kind", jDiffKind h.kind),
              ("path", Json.arr (h.path.map jPathSeg |>.toArray))] ++
              [("expected", encValue ve)] : List (String × Json)) := by simp
          have mp : ("path", Json.arr (h.path.map jPathSeg |>.toArray)) ∈ ([
              ("kind", jDiffKind h.kind),
              ("path", Json.arr (h.path.map jPathSeg |>.toArray))] ++
              [("expected", encValue ve)] : List (String × Json)) := by simp
          have me : ("expected", encValue ve) ∈ ([
              ("kind", jDiffKind h.kind),
              ("path", Json.arr (h.path.map jPathSeg |>.toArray))] ++
              [("expected", encValue ve)] : List (String × Json)) := by simp
          have hnoa : ∀ v, ("actual", v) ∉ ([
              ("kind", jDiffKind h.kind),
              ("path", Json.arr (h.path.map jPathSeg |>.toArray))] ++
              [("expected", encValue ve)] : List (String × Json)) := by
            intro v hv
            have : "actual" ∈ ([
              ("kind", jDiffKind h.kind),
              ("path", Json.arr (h.path.map jPathSeg |>.toArray))] ++
              [("expected", encValue ve)] : List (String × Json)).map Prod.fst :=
              List.mem_map_of_mem hv
            simp at this
          obtain ⟨we, hwe, hvale⟩ := decOptValueField_enc hkeys me (hh.2 ve (by simp [hes]))
          refine ⟨{ kind := h.kind, path := h.path, actual := none, expected := some we },
            ?_, rfl, rfl, by rw [has]; trivial, by rw [hes]; exact hvale⟩
          simp only [henc, decDiffHint, reqStr, reqNat]
          rw [reqField_of_field hkeys mk (jDiffKind_ne_null h.kind)
              (decDiffKind_jDiffKind h.kind),
            reqField_of_field hkeys mp (arr_ne_null _) (decPathArr_enc h.path),
            decOptValueField_absent hkeys hnoa, hwe]
          rfl
  | some va =>
      cases hes : h.expected with
      | none =>
          have henc : jDiffHint h = Json.mkObj ([
              ("kind", jDiffKind h.kind),
              ("path", Json.arr (h.path.map jPathSeg |>.toArray))] ++
              [("actual", encValue va)]) := by
            simp [jDiffHint, has, hes]
          have hkeys : ((([
              ("kind", jDiffKind h.kind),
              ("path", Json.arr (h.path.map jPathSeg |>.toArray))] ++
              [("actual", encValue va)]) : List (String × Json)).map Prod.fst).Pairwise
              (fun a b => a ≠ b) := by simp
          have mk : ("kind", jDiffKind h.kind) ∈ ([
              ("kind", jDiffKind h.kind),
              ("path", Json.arr (h.path.map jPathSeg |>.toArray))] ++
              [("actual", encValue va)] : List (String × Json)) := by simp
          have mp : ("path", Json.arr (h.path.map jPathSeg |>.toArray)) ∈ ([
              ("kind", jDiffKind h.kind),
              ("path", Json.arr (h.path.map jPathSeg |>.toArray))] ++
              [("actual", encValue va)] : List (String × Json)) := by simp
          have ma : ("actual", encValue va) ∈ ([
              ("kind", jDiffKind h.kind),
              ("path", Json.arr (h.path.map jPathSeg |>.toArray))] ++
              [("actual", encValue va)] : List (String × Json)) := by simp
          have hnoe : ∀ v, ("expected", v) ∉ ([
              ("kind", jDiffKind h.kind),
              ("path", Json.arr (h.path.map jPathSeg |>.toArray))] ++
              [("actual", encValue va)] : List (String × Json)) := by
            intro v hv
            have : "expected" ∈ ([
              ("kind", jDiffKind h.kind),
              ("path", Json.arr (h.path.map jPathSeg |>.toArray))] ++
              [("actual", encValue va)] : List (String × Json)).map Prod.fst :=
              List.mem_map_of_mem hv
            simp at this
          obtain ⟨wa, hwa, hvala⟩ := decOptValueField_enc hkeys ma (hh.1 va (by simp [has]))
          refine ⟨{ kind := h.kind, path := h.path, actual := some wa, expected := none },
            ?_, rfl, rfl, by rw [has]; exact hvala, by rw [hes]; trivial⟩
          simp only [henc, decDiffHint, reqStr, reqNat]
          rw [reqField_of_field hkeys mk (jDiffKind_ne_null h.kind)
              (decDiffKind_jDiffKind h.kind),
            reqField_of_field hkeys mp (arr_ne_null _) (decPathArr_enc h.path),
            hwa, decOptValueField_absent hkeys hnoe]
          rfl
      | some ve =>
          have henc : jDiffHint h = Json.mkObj ([
              ("kind", jDiffKind h.kind),
              ("path", Json.arr (h.path.map jPathSeg |>.toArray))] ++
              [("actual", encValue va), ("expected", encValue ve)]) := by
            simp [jDiffHint, has, hes]
          have hkeys : ((([
              ("kind", jDiffKind h.kind),
              ("path", Json.arr (h.path.map jPathSeg |>.toArray))] ++
              [("actual", encValue va), ("expected", encValue ve)]) :
              List (String × Json)).map Prod.fst).Pairwise
              (fun a b => a ≠ b) := by simp
          have mk : ("kind", jDiffKind h.kind) ∈ ([
              ("kind", jDiffKind h.kind),
              ("path", Json.arr (h.path.map jPathSeg |>.toArray))] ++
              [("actual", encValue va), ("expected", encValue ve)] :
              List (String × Json)) := by simp
          have mp : ("path", Json.arr (h.path.map jPathSeg |>.toArray)) ∈ ([
              ("kind", jDiffKind h.kind),
              ("path", Json.arr (h.path.map jPathSeg |>.toArray))] ++
              [("actual", encValue va), ("expected", encValue ve)] :
              List (String × Json)) := by simp
          have ma : ("actual", encValue va) ∈ ([
              ("kind", jDiffKind h.kind),
              ("path", Json.arr (h.path.map jPathSeg |>.toArray))] ++
              [("actual", encValue va), ("expected", encValue ve)] :
              List (String × Json)) := by simp
          have me : ("expected", encValue ve) ∈ ([
              ("kind", jDiffKind h.kind),
              ("path", Json.arr (h.path.map jPathSeg |>.toArray))] ++
              [("actual", encValue va), ("expected", encValue ve)] :
              List (String × Json)) := by simp
          obtain ⟨wa, hwa, hvala⟩ := decOptValueField_enc hkeys ma (hh.1 va (by simp [has]))
          obtain ⟨we, hwe, hvale⟩ := decOptValueField_enc hkeys me (hh.2 ve (by simp [hes]))
          refine ⟨{ kind := h.kind, path := h.path, actual := some wa, expected := some we },
            ?_, rfl, rfl, by rw [has]; exact hvala, by rw [hes]; exact hvale⟩
          simp only [henc, decDiffHint, reqStr, reqNat]
          rw [reqField_of_field hkeys mk (jDiffKind_ne_null h.kind)
              (decDiffKind_jDiffKind h.kind),
            reqField_of_field hkeys mp (arr_ne_null _) (decPathArr_enc h.path),
            hwa, hwe]
          rfl

private theorem decHintArr_enc :
    ∀ hs : List DiffHint, (∀ h ∈ hs, hintOk h) →
      ∃ us, decHintArr (Json.arr ((hs.map jDiffHint).toArray)) = Except.ok us
        ∧ ∀ h, h ∈ hs → ∃ u, u ∈ us ∧ hintEquiv h u := by
  intro hs hok
  induction hs with
  | nil => exact ⟨[], rfl, by intro h hh; exact absurd hh (by simp)⟩
  | cons h t ih =>
      obtain ⟨h', hh', hhe⟩ := decDiffHint_jDiffHint h (hok h (by simp))
      obtain ⟨us, hus, hmem⟩ := ih (fun x hx => hok x (by simp [hx]))
      refine ⟨h' :: us, ?_, ?_⟩
      · show List.mapM decDiffHint (((h :: t).map jDiffHint).toArray).toList = _
        have harr : ((h :: t).map jDiffHint).toArray.toList
            = jDiffHint h :: ((t.map jDiffHint).toArray).toList := by
          simp only [List.map_cons, List.toList_toArray]
        rw [harr, List.mapM_cons, hh']
        have hus2 : List.mapM decDiffHint ((t.map jDiffHint).toArray).toList = Except.ok us := hus
        rw [hus2]
        rfl
      · intro x hx
        rcases List.mem_cons.mp hx with hx | hx
        · exact ⟨h', List.mem_cons_self, by rw [hx]; exact hhe⟩
        · obtain ⟨u, hu, hqu⟩ := hmem x hx
          exact ⟨u, by simp [hu], hqu⟩

private theorem decTraceGenResult_fields {l : List (String × Json)} {r : TraceGenResult}
    (hkeys : (l.map Prod.fst).Pairwise (fun a b => a ≠ b))
    (hp : ("itfTracePaths", Json.arr (strsJson r.itfTracePaths |>.toArray)) ∈ l)
    (ht : ("itfTraces", Json.arr ((r.itfTraces.map encValue).toArray)) ∈ l)
    (hb : tracesOk r) :
    ∃ r', decTraceGenResult (Json.mkObj l) = Except.ok r' ∧ tracesEquiv r r' := by
  obtain ⟨ws, hws, hlist⟩ := decValues_encValues r.itfTraces hb
  refine ⟨{ itfTracePaths := r.itfTracePaths, itfTraces := ws }, ?_, rfl, hlist⟩
  simp only [decTraceGenResult, reqStr]
  rw [strs_of_mkObj hkeys hp,
    reqField_of_field hkeys ht (arr_ne_null _) hws]
  rfl

private theorem decJobOutcome_jJobOutcome :
    ∀ o : JobOutcome, jobOutcomeOk o →
      ∃ o', decJobOutcome (jJobOutcome o) = Except.ok o' ∧ JobOutcomeEquiv o o' := by
  intro o hok
  cases o with
  | validate r =>
      refine ⟨.validate r, ?_, rfl⟩
      simp only [jJobOutcome, Json.mkObj, decJobOutcome, toList_ofList_singleton]
      rw [decValidateResult_jValidateResult]
      rfl
  | genTraces r =>
      have hkeys : (([
          ("itfTracePaths", Json.arr (strsJson r.itfTracePaths |>.toArray)),
          ("itfTraces", Json.arr ((r.itfTraces.map encValue).toArray))] :
          List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have hp : ("itfTracePaths", Json.arr (strsJson r.itfTracePaths |>.toArray)) ∈ ([
          ("itfTracePaths", Json.arr (strsJson r.itfTracePaths |>.toArray)),
          ("itfTraces", Json.arr ((r.itfTraces.map encValue).toArray))] :
          List (String × Json)) := by simp
      have ht : ("itfTraces", Json.arr ((r.itfTraces.map encValue).toArray)) ∈ ([
          ("itfTracePaths", Json.arr (strsJson r.itfTracePaths |>.toArray)),
          ("itfTraces", Json.arr ((r.itfTraces.map encValue).toArray))] :
          List (String × Json)) := by simp
      obtain ⟨r', hr', hte⟩ := decTraceGenResult_fields hkeys hp ht hok
      refine ⟨.genTraces r', ?_, hte⟩
      have hsingle : decJobOutcome (Json.mkObj [("genTraces", jTraceGenResult r)])
          = .genTraces <$> decTraceGenResult (jTraceGenResult r) := by
        simp only [jJobOutcome, Json.mkObj, decJobOutcome, toList_ofList_singleton]
      rw [show jJobOutcome (JobOutcome.genTraces r)
            = Json.mkObj [("genTraces", jTraceGenResult r)] from rfl, hsingle,
          show jTraceGenResult r =
            Json.mkObj [
              ("itfTracePaths", Json.arr (strsJson r.itfTracePaths |>.toArray)),
              ("itfTraces", Json.arr (r.itfTraces.map encValue |>.toArray))] from rfl,
          hr']
      rfl
  | infraError msg =>
      refine ⟨.infraError msg, ?_, rfl⟩
      simp only [jJobOutcome, Json.mkObj, decJobOutcome, toList_ofList_singleton]
private theorem jJobKind_ne_null (k : JobKind) : jJobKind k ≠ Json.null := by
  cases k <;> intro h <;> simp only [jJobKind] at h <;> exact Json.noConfusion h

private theorem jJobPhase_ne_null (p : JobPhase) : jJobPhase p ≠ Json.null := by
  cases p <;> intro h <;> simp only [jJobPhase] at h <;> exact Json.noConfusion h

private theorem jJobOutcome_ne_null (o : JobOutcome) : jJobOutcome o ≠ Json.null := by
  cases o with
  | validate r =>
      intro h
      simp only [jJobOutcome, Json.mkObj] at h
      exact Json.noConfusion h
  | genTraces r =>
      intro h
      simp only [jJobOutcome, Json.mkObj] at h
      exact Json.noConfusion h
  | infraError msg =>
      intro h
      simp only [jJobOutcome, Json.mkObj] at h
      exact Json.noConfusion h

private theorem jValidateResult_ne_null (r : ValidateResult) :
    jValidateResult r ≠ Json.null := by
  cases r with
  | valid => exact str_ne_null "valid"
  | invalid msg =>
      intro h
      simp only [jValidateResult, Json.mkObj] at h
      exact Json.noConfusion h

/-- Wire well-formedness for mirror messages. -/
def MirrorOk : MirrorMessage → Prop
  | .initialState _ st => mapOkBounded st
  | .nextStep _ ps => mapOkBounded ps
  | .stepMismatch e a hs => mapOkBounded e ∧ mapOkBounded a ∧ ∀ h ∈ hs, hintOk h
  | .exploreState st => mapOkBounded st
  | .genTracesDone r => tracesOk r
  | .jobResult _ o => jobOutcomeOk o
  | _ => True

/-- Mirror message equality up to `valEq` at value positions. -/
def MirrorEquiv : MirrorMessage → MirrorMessage → Prop
  | .initialState a st, .initialState a' st' => a = a' ∧ mapEqV st st'
  | .nextStep a ps, .nextStep a' ps' => a = a' ∧ mapEqV ps ps'
  | .stepMismatch e a hs, .stepMismatch e' a' hs' =>
      mapEqV e e' ∧ mapEqV a a' ∧ ∀ h, h ∈ hs → ∃ u, u ∈ hs' ∧ hintEquiv h u
  | .exploreState st, .exploreState st' => mapEqV st st'
  | .genTracesDone r, .genTracesDone r' => tracesEquiv r r'
  | .jobResult j o, .jobResult j' o' => j = j' ∧ JobOutcomeEquiv o o'
  | a, b => a = b

/-- **§6.6 mirror round-trip**: decoding an encoded mirror message yields an
equivalent message; exact for constructors without value positions. -/
theorem decodeMirror_encodeMirror :
    ∀ m : MirrorMessage, MirrorOk m →
      ∃ m', decodeMirror (encodeMirror m) = Except.ok m' ∧ MirrorEquiv m m' := by
  intro m hm
  cases m with
  | specValidated result =>
      refine ⟨.specValidated result, ?_, rfl⟩
      have hkeys : (([("proto_step", Json.str "spec_validated"),
          ("result", jValidateResult result)] :
          List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have mt : ("proto_step", Json.str "spec_validated") ∈ ([("proto_step", Json.str "spec_validated"),
          ("result", jValidateResult result)] : List (String × Json)) := by simp
      have mr : ("result", jValidateResult result) ∈ ([("proto_step", Json.str "spec_validated"),
          ("result", jValidateResult result)] : List (String × Json)) := by simp
      simp only [encodeMirror, decodeMirror, reqStr]
      rw [str_of_mkObj hkeys mt,
          reqField_of_field hkeys mr (jValidateResult_ne_null result)
            (decValidateResult_jValidateResult result)]
      rfl
  | initialState action st =>
      obtain ⟨ws, hws, hmeq⟩ := decStateMap_jStateMap st hm
      refine ⟨.initialState action ws, ?_, rfl, hmeq⟩
      have hkeys : (([("action", Json.str action), ("proto_step", Json.str "initial_state"),
          ("state", jStateMap st)] :
          List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have mt : ("proto_step", Json.str "initial_state") ∈ ([("action", Json.str action),
          ("proto_step", Json.str "initial_state"), ("state", jStateMap st)] :
          List (String × Json)) := by simp
      have mac : ("action", Json.str action) ∈ ([("action", Json.str action),
          ("proto_step", Json.str "initial_state"), ("state", jStateMap st)] :
          List (String × Json)) := by simp
      have ms : ("state", Json.mkObj (encMap st)) ∈ ([("action", Json.str action),
          ("proto_step", Json.str "initial_state"), ("state", jStateMap st)] :
          List (String × Json)) := by simp [jStateMap]
      simp only [jStateMap] at hws
      simp only [encodeMirror, decodeMirror, reqStr]
      rw [str_of_mkObj hkeys mt, str_of_mkObj hkeys mac,
          decOptStateMap_of_field hkeys ms, hws]
      rfl
  | nextStep action params =>
      obtain ⟨ws, hws, hmeq⟩ := decStateMap_jStateMap params hm
      refine ⟨.nextStep action ws, ?_, rfl, hmeq⟩
      have hkeys : (([("action", Json.str action), ("parameters", jStateMap params),
          ("proto_step", Json.str "next_step")] :
          List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have mt : ("proto_step", Json.str "next_step") ∈ ([("action", Json.str action),
          ("parameters", jStateMap params), ("proto_step", Json.str "next_step")] :
          List (String × Json)) := by simp
      have mac : ("action", Json.str action) ∈ ([("action", Json.str action),
          ("parameters", jStateMap params), ("proto_step", Json.str "next_step")] :
          List (String × Json)) := by simp
      have ms : ("parameters", Json.mkObj (encMap params)) ∈ ([("action", Json.str action),
          ("parameters", jStateMap params), ("proto_step", Json.str "next_step")] :
          List (String × Json)) := by simp [jStateMap]
      simp only [jStateMap] at hws
      simp only [encodeMirror, decodeMirror, reqStr]
      rw [str_of_mkObj hkeys mt, str_of_mkObj hkeys mac,
          decOptStateMap_of_field hkeys ms, hws]
      rfl
  | stepOk =>
      refine ⟨.stepOk, ?_, rfl⟩
      have hkeys : (([("proto_step", Json.str "step_ok")] :
          List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have mt : ("proto_step", Json.str "step_ok") ∈ ([("proto_step", Json.str "step_ok")] :
          List (String × Json)) := by simp
      simp only [encodeMirror, decodeMirror]
      rw [str_of_mkObj hkeys mt]
      rfl
  | stepMismatch expected actual hints =>
      obtain ⟨he, ha, hh⟩ := hm
      obtain ⟨ews, hews, heeq⟩ := decStateMap_jStateMap expected he
      obtain ⟨aws, haws, haeq⟩ := decStateMap_jStateMap actual ha
      obtain ⟨us, hus, hmem⟩ := decHintArr_enc hints hh
      refine ⟨.stepMismatch ews aws us, ?_, heeq, haeq, hmem⟩
      have hkeys : (([("actual", jStateMap actual), ("expected", jStateMap expected),
          ("hints", Json.arr (hints.map jDiffHint |>.toArray)),
          ("proto_step", Json.str "step_mismatch")] :
          List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have mt : ("proto_step", Json.str "step_mismatch") ∈ ([("actual", jStateMap actual),
          ("expected", jStateMap expected),
          ("hints", Json.arr (hints.map jDiffHint |>.toArray)),
          ("proto_step", Json.str "step_mismatch")] :
          List (String × Json)) := by simp
      have me : ("expected", Json.mkObj (encMap expected)) ∈ ([("actual", jStateMap actual),
          ("expected", jStateMap expected),
          ("hints", Json.arr (hints.map jDiffHint |>.toArray)),
          ("proto_step", Json.str "step_mismatch")] :
          List (String × Json)) := by simp [jStateMap]
      have ma : ("actual", Json.mkObj (encMap actual)) ∈ ([("actual", jStateMap actual),
          ("expected", jStateMap expected),
          ("hints", Json.arr (hints.map jDiffHint |>.toArray)),
          ("proto_step", Json.str "step_mismatch")] :
          List (String × Json)) := by simp [jStateMap]
      have mh : ("hints", Json.arr (hints.map jDiffHint |>.toArray)) ∈ ([
          ("actual", jStateMap actual), ("expected", jStateMap expected),
          ("hints", Json.arr (hints.map jDiffHint |>.toArray)),
          ("proto_step", Json.str "step_mismatch")] :
          List (String × Json)) := by simp
      simp only [jStateMap] at hews haws
      simp only [encodeMirror, decodeMirror, reqStr]
      rw [str_of_mkObj hkeys mt, decOptStateMap_of_field hkeys me, hews,
          decOptStateMap_of_field hkeys ma, haws,
          reqField_of_field hkeys mh (arr_ne_null _) hus]
      rfl
  | allStepsDone =>
      refine ⟨.allStepsDone, ?_, rfl⟩
      have hkeys : (([("proto_step", Json.str "all_steps_done")] :
          List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have mt : ("proto_step", Json.str "all_steps_done") ∈ ([
          ("proto_step", Json.str "all_steps_done")] : List (String × Json)) := by simp
      simp only [encodeMirror, decodeMirror]
      rw [str_of_mkObj hkeys mt]
      rfl
  | genTracesDone r =>
      have hkeys : (([
          ("itfTracePaths", Json.arr (strsJson r.itfTracePaths |>.toArray)),
          ("itfTraces", Json.arr (r.itfTraces.map encValue |>.toArray)),
          ("proto_step", Json.str "gen_traces_done")] :
          List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have mt : ("proto_step", Json.str "gen_traces_done") ∈ ([
          ("itfTracePaths", Json.arr (strsJson r.itfTracePaths |>.toArray)),
          ("itfTraces", Json.arr (r.itfTraces.map encValue |>.toArray)),
          ("proto_step", Json.str "gen_traces_done")] : List (String × Json)) := by simp
      have hp : ("itfTracePaths", Json.arr (strsJson r.itfTracePaths |>.toArray)) ∈ ([
          ("itfTracePaths", Json.arr (strsJson r.itfTracePaths |>.toArray)),
          ("itfTraces", Json.arr (r.itfTraces.map encValue |>.toArray)),
          ("proto_step", Json.str "gen_traces_done")] : List (String × Json)) := by simp
      have ht : ("itfTraces", Json.arr (r.itfTraces.map encValue |>.toArray)) ∈ ([
          ("itfTracePaths", Json.arr (strsJson r.itfTracePaths |>.toArray)),
          ("itfTraces", Json.arr (r.itfTraces.map encValue |>.toArray)),
          ("proto_step", Json.str "gen_traces_done")] : List (String × Json)) := by simp
      obtain ⟨r', hr', hte⟩ := decTraceGenResult_fields hkeys hp ht hm
      refine ⟨.genTracesDone r', ?_, hte⟩
      simp only [encodeMirror, decodeMirror, reqStr]
      rw [str_of_mkObj hkeys mt, hr']
      rfl
  | registerError err =>
      refine ⟨.registerError err, ?_, rfl⟩
      have hkeys : (([("error", Json.str err), ("proto_step", Json.str "register_error")] :
          List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have mt : ("proto_step", Json.str "register_error") ∈ ([("error", Json.str err),
          ("proto_step", Json.str "register_error")] : List (String × Json)) := by simp
      have me : ("error", Json.str err) ∈ ([("error", Json.str err),
          ("proto_step", Json.str "register_error")] : List (String × Json)) := by simp
      simp only [encodeMirror, decodeMirror, reqStr]
      rw [str_of_mkObj hkeys mt, str_of_mkObj hkeys me]
      rfl
  | protocolError err =>
      refine ⟨.protocolError err, ?_, rfl⟩
      have hkeys : (([("error", Json.str err), ("proto_step", Json.str "protocol_error")] :
          List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have mt : ("proto_step", Json.str "protocol_error") ∈ ([("error", Json.str err),
          ("proto_step", Json.str "protocol_error")] : List (String × Json)) := by simp
      have me : ("error", Json.str err) ∈ ([("error", Json.str err),
          ("proto_step", Json.str "protocol_error")] : List (String × Json)) := by simp
      simp only [encodeMirror, decodeMirror, reqStr]
      rw [str_of_mkObj hkeys mt, str_of_mkObj hkeys me]
      rfl
  | explorerReady i n s =>
      refine ⟨.explorerReady i n s, ?_, rfl⟩
      have hkeys : (([("initTransitions", Json.num i), ("nextTransitions", Json.num n),
          ("proto_step", Json.str "explorer_ready"),
          ("stateInvariants", Json.num s)] :
          List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have mt : ("proto_step", Json.str "explorer_ready") ∈ ([
          ("initTransitions", Json.num i), ("nextTransitions", Json.num n),
          ("proto_step", Json.str "explorer_ready"),
          ("stateInvariants", Json.num s)] : List (String × Json)) := by simp
      have mi : ("initTransitions", Json.num (JsonNumber.fromNat i)) ∈ ([
          ("initTransitions", Json.num i), ("nextTransitions", Json.num n),
          ("proto_step", Json.str "explorer_ready"),
          ("stateInvariants", Json.num s)] : List (String × Json)) := by simp
      have mn : ("nextTransitions", Json.num (JsonNumber.fromNat n)) ∈ ([
          ("initTransitions", Json.num i), ("nextTransitions", Json.num n),
          ("proto_step", Json.str "explorer_ready"),
          ("stateInvariants", Json.num s)] : List (String × Json)) := by simp
      have ms : ("stateInvariants", Json.num (JsonNumber.fromNat s)) ∈ ([
          ("initTransitions", Json.num i), ("nextTransitions", Json.num n),
          ("proto_step", Json.str "explorer_ready"),
          ("stateInvariants", Json.num s)] : List (String × Json)) := by simp
      simp only [encodeMirror, decodeMirror, reqStr, reqNat]
      rw [str_of_mkObj hkeys mt, nat_of_mkObj hkeys mi, nat_of_mkObj hkeys mn,
          nat_of_mkObj hkeys ms]
      rfl
  | exploreTransitionStatus status =>
      refine ⟨.exploreTransitionStatus status, ?_, rfl⟩
      have hkeys : (([("proto_step", Json.str "explore_transition_status"),
          ("status", Json.str status)] :
          List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have mt : ("proto_step", Json.str "explore_transition_status") ∈ ([
          ("proto_step", Json.str "explore_transition_status"),
          ("status", Json.str status)] : List (String × Json)) := by simp
      have mst : ("status", Json.str status) ∈ ([
          ("proto_step", Json.str "explore_transition_status"),
          ("status", Json.str status)] : List (String × Json)) := by simp
      simp only [encodeMirror, decodeMirror, reqStr]
      rw [str_of_mkObj hkeys mt, str_of_mkObj hkeys mst]
      rfl
  | exploreStepDone stepNo =>
      refine ⟨.exploreStepDone stepNo, ?_, rfl⟩
      have hkeys : (([("proto_step", Json.str "explore_step_done"),
          ("stepNo", Json.num stepNo)] :
          List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have mt : ("proto_step", Json.str "explore_step_done") ∈ ([
          ("proto_step", Json.str "explore_step_done"),
          ("stepNo", Json.num stepNo)] : List (String × Json)) := by simp
      have mn : ("stepNo", Json.num (JsonNumber.fromNat stepNo)) ∈ ([
          ("proto_step", Json.str "explore_step_done"),
          ("stepNo", Json.num stepNo)] : List (String × Json)) := by simp
      simp only [encodeMirror, decodeMirror, reqStr, reqNat]
      rw [str_of_mkObj hkeys mt, nat_of_mkObj hkeys mn]
      rfl
  | exploreState st =>
      obtain ⟨ws, hws, hmeq⟩ := decStateMap_jStateMap st hm
      refine ⟨.exploreState ws, ?_, hmeq⟩
      have hkeys : (([("proto_step", Json.str "explore_state"), ("state", jStateMap st)] :
          List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have mt : ("proto_step", Json.str "explore_state") ∈ ([
          ("proto_step", Json.str "explore_state"), ("state", jStateMap st)] :
          List (String × Json)) := by simp
      have ms : ("state", Json.mkObj (encMap st)) ∈ ([
          ("proto_step", Json.str "explore_state"), ("state", jStateMap st)] :
          List (String × Json)) := by simp [jStateMap]
      simp only [jStateMap] at hws
      simp only [encodeMirror, decodeMirror, reqStr]
      rw [str_of_mkObj hkeys mt, decOptStateMap_of_field hkeys ms, hws]
      rfl
  | exploreInvariantStatus status =>
      refine ⟨.exploreInvariantStatus status, ?_, rfl⟩
      have hkeys : (([("proto_step", Json.str "explore_invariant_status"),
          ("status", Json.str status)] :
          List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have mt : ("proto_step", Json.str "explore_invariant_status") ∈ ([
          ("proto_step", Json.str "explore_invariant_status"),
          ("status", Json.str status)] : List (String × Json)) := by simp
      have mst : ("status", Json.str status) ∈ ([
          ("proto_step", Json.str "explore_invariant_status"),
          ("status", Json.str status)] : List (String × Json)) := by simp
      simp only [encodeMirror, decodeMirror, reqStr]
      rw [str_of_mkObj hkeys mt, str_of_mkObj hkeys mst]
      rfl
  | exploreAssumeStatus status =>
      refine ⟨.exploreAssumeStatus status, ?_, rfl⟩
      have hkeys : (([("proto_step", Json.str "explore_assume_status"),
          ("status", Json.str status)] :
          List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have mt : ("proto_step", Json.str "explore_assume_status") ∈ ([
          ("proto_step", Json.str "explore_assume_status"),
          ("status", Json.str status)] : List (String × Json)) := by simp
      have mst : ("status", Json.str status) ∈ ([
          ("proto_step", Json.str "explore_assume_status"),
          ("status", Json.str status)] : List (String × Json)) := by simp
      simp only [encodeMirror, decodeMirror, reqStr]
      rw [str_of_mkObj hkeys mt, str_of_mkObj hkeys mst]
      rfl
  | exploreRollbackDone sid =>
      refine ⟨.exploreRollbackDone sid, ?_, rfl⟩
      have hkeys : (([("proto_step", Json.str "explore_rollback_done"),
          ("snapshotId", Json.num sid)] :
          List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have mt : ("proto_step", Json.str "explore_rollback_done") ∈ ([
          ("proto_step", Json.str "explore_rollback_done"),
          ("snapshotId", Json.num sid)] : List (String × Json)) := by simp
      have mn : ("snapshotId", Json.num (JsonNumber.fromNat sid)) ∈ ([
          ("proto_step", Json.str "explore_rollback_done"),
          ("snapshotId", Json.num sid)] : List (String × Json)) := by simp
      simp only [encodeMirror, decodeMirror, reqStr, reqNat]
      rw [str_of_mkObj hkeys mt, nat_of_mkObj hkeys mn]
      rfl
  | exploreSessionDone =>
      refine ⟨.exploreSessionDone, ?_, rfl⟩
      have hkeys : (([("proto_step", Json.str "explore_session_done")] :
          List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have mt : ("proto_step", Json.str "explore_session_done") ∈ ([
          ("proto_step", Json.str "explore_session_done")] : List (String × Json)) := by simp
      simp only [encodeMirror, decodeMirror]
      rw [str_of_mkObj hkeys mt]
      rfl
  | jobAccepted jobId kind =>
      refine ⟨.jobAccepted jobId kind, ?_, rfl⟩
      have hkeys : (([("jobId", Json.str jobId), ("kind", jJobKind kind),
          ("proto_step", Json.str "job_accepted")] :
          List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have mt : ("proto_step", Json.str "job_accepted") ∈ ([("jobId", Json.str jobId),
          ("kind", jJobKind kind), ("proto_step", Json.str "job_accepted")] :
          List (String × Json)) := by simp
      have mj : ("jobId", Json.str jobId) ∈ ([("jobId", Json.str jobId),
          ("kind", jJobKind kind), ("proto_step", Json.str "job_accepted")] :
          List (String × Json)) := by simp
      have mk : ("kind", jJobKind kind) ∈ ([("jobId", Json.str jobId),
          ("kind", jJobKind kind), ("proto_step", Json.str "job_accepted")] :
          List (String × Json)) := by simp
      simp only [encodeMirror, decodeMirror, reqStr]
      rw [str_of_mkObj hkeys mt, str_of_mkObj hkeys mj,
          reqField_of_field hkeys mk (jJobKind_ne_null kind) (decJobKind_jJobKind kind)]
      rfl
  | jobStatus jobId phase =>
      refine ⟨.jobStatus jobId phase, ?_, rfl⟩
      have hkeys : (([("jobId", Json.str jobId), ("phase", jJobPhase phase),
          ("proto_step", Json.str "job_status")] :
          List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have mt : ("proto_step", Json.str "job_status") ∈ ([("jobId", Json.str jobId),
          ("phase", jJobPhase phase), ("proto_step", Json.str "job_status")] :
          List (String × Json)) := by simp
      have mj : ("jobId", Json.str jobId) ∈ ([("jobId", Json.str jobId),
          ("phase", jJobPhase phase), ("proto_step", Json.str "job_status")] :
          List (String × Json)) := by simp
      have mp : ("phase", jJobPhase phase) ∈ ([("jobId", Json.str jobId),
          ("phase", jJobPhase phase), ("proto_step", Json.str "job_status")] :
          List (String × Json)) := by simp
      simp only [encodeMirror, decodeMirror, reqStr]
      rw [str_of_mkObj hkeys mt, str_of_mkObj hkeys mj,
          reqField_of_field hkeys mp (jJobPhase_ne_null phase) (decJobPhase_jJobPhase phase)]
      rfl
  | jobResult jobId outcome =>
      obtain ⟨o', ho', hoe⟩ := decJobOutcome_jJobOutcome outcome hm
      refine ⟨.jobResult jobId o', ?_, rfl, hoe⟩
      have hkeys : (([("jobId", Json.str jobId), ("outcome", jJobOutcome outcome),
          ("proto_step", Json.str "job_result")] :
          List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
      have mt : ("proto_step", Json.str "job_result") ∈ ([("jobId", Json.str jobId),
          ("outcome", jJobOutcome outcome), ("proto_step", Json.str "job_result")] :
          List (String × Json)) := by simp
      have mj : ("jobId", Json.str jobId) ∈ ([("jobId", Json.str jobId),
          ("outcome", jJobOutcome outcome), ("proto_step", Json.str "job_result")] :
          List (String × Json)) := by simp
      have mo : ("outcome", jJobOutcome outcome) ∈ ([("jobId", Json.str jobId),
          ("outcome", jJobOutcome outcome), ("proto_step", Json.str "job_result")] :
          List (String × Json)) := by simp
      simp only [encodeMirror, decodeMirror, reqStr]
      rw [str_of_mkObj hkeys mt, str_of_mkObj hkeys mj,
          reqField_of_field hkeys mo (jJobOutcome_ne_null outcome) ho']
      rfl

end Codec
