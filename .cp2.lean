import Codec.Consul
open Lean
open Consul
open Codec (Dec derr)

theorem decEntry_encEntry (s : ServiceInfo) (h : s.host ≠ "") :
    decEntry (encEntry s) = Except.ok [s] := by
  have hkeys : (([("Service", encService s)] : List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
  have hm : ("Service", encService s) ∈ ([("Service", encService s)] : List (String × Json)) := by simp
  have hn : encService s ≠ Json.null := by simp [encService, Json.mkObj]
  simp only [decEntry, encEntry, Codec.jOptField_mkObj hkeys hn hm, decService_encService]
  by_cases hb : (s.host == "") = true
  · exact absurd (of_decide_eq_true hb) h
  · simp [hb]

theorem mapM_encEntry (l : List ServiceInfo) (h : ∀ s ∈ l, s.host ≠ "") :
    List.mapM decEntry (l.map encEntry) = Except.ok l := by
  induction l with
  | nil => rfl
  | cons s ss ih =>
      have hs : s.host ≠ "" := h s (by simp)
      have hss : ∀ x ∈ ss, x.host ≠ "" := fun x hx => h x (by simp [hx])
      show ((decEntry (encEntry s)) >>= fun a =>
             (List.mapM decEntry (ss.map encEntry)) >>= fun b => Except.ok (a :: b)) = Except.ok (s :: ss)
      rw [decEntry_encEntry s hs, ih hss]
      rfl
