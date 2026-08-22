import Codec.Consul
open Lean
open Consul
open Codec (Dec derr)

theorem decMetaFp_jMeta (fp : Option String) : decMetaFp (jMeta fp) = Except.ok fp := by
  cases fp with
  | none => simp only [jMeta, decMetaFp, Codec.jOptStr]; rfl
  | some f => simp only [jMeta, decMetaFp, Codec.jOptStr]; rfl

theorem decFingerprint_jMeta {l : List (String × Json)} {fp : Option String}
    (hkeys : (l.map Prod.fst).Pairwise (fun a b => a ≠ b))
    (hm : ("Meta", jMeta fp) ∈ l) :
    decFingerprint (Json.mkObj l) = Except.ok fp := by
  have hn : jMeta fp ≠ Json.null := by cases fp <;> simp [jMeta, Json.mkObj]
  simp only [decFingerprint, Codec.jOptField_mkObj hkeys hn hm, decMetaFp_jMeta]

theorem decService_encService (s : ServiceInfo) :
    decService (encService s) = Except.ok s := by
  have hkeys : (([("ID", Json.str s.serviceId), ("Address", Json.str s.host), ("Port", Json.num s.port), ("Meta", jMeta s.certFingerprint)] : List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
  have m0 : ("ID", Json.str s.serviceId) ∈ ([("ID", Json.str s.serviceId), ("Address", Json.str s.host), ("Port", Json.num s.port), ("Meta", jMeta s.certFingerprint)] : List (String × Json)) := by simp
  have m1 : ("Address", Json.str s.host) ∈ ([("ID", Json.str s.serviceId), ("Address", Json.str s.host), ("Port", Json.num s.port), ("Meta", jMeta s.certFingerprint)] : List (String × Json)) := by simp
  have m2 : ("Port", Json.num s.port) ∈ ([("ID", Json.str s.serviceId), ("Address", Json.str s.host), ("Port", Json.num s.port), ("Meta", jMeta s.certFingerprint)] : List (String × Json)) := by simp
  have m3 : ("Meta", jMeta s.certFingerprint) ∈ ([("ID", Json.str s.serviceId), ("Address", Json.str s.host), ("Port", Json.num s.port), ("Meta", jMeta s.certFingerprint)] : List (String × Json)) := by simp
  simp only [decService, encService]
  rw [Codec.str_of_mkObj hkeys m0, Codec.str_of_mkObj hkeys m1, Codec.nat_of_mkObj hkeys m2, decFingerprint_jMeta hkeys m3]
  rfl

theorem decEntry_encEntry (s : ServiceInfo) (h : s.host ≠ "") :
    decEntry (encEntry s) = Except.ok [s] := by
  have hkeys : (([("Service", encService s)] : List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
  have hm : ("Service", encService s) ∈ ([("Service", encService s)] : List (String × Json)) := by simp
  have hn : encService s ≠ Json.null := by simp [encService, Json.mkObj]
  simp only [decEntry, encEntry, Codec.jOptField_mkObj hkeys hn hm, decService_encService]
  by_cases hb : (s.host == "") = true
  · exact absurd (of_decide_eq_true hb) h
  · simp [hb]

theorem decodeRegisterBody_encodeRegisterBody (i : ServiceInfo) :
    decodeRegisterBody (encodeRegisterBody i) = Except.ok i := by

theorem decEntry_encEntry (s : ServiceInfo) (h : s.host ≠ ) :
    decEntry (encEntry s) = Except.ok [s] := by
  have hkeys : (([("Service", encService s)] : List (String × Json)).map Prod.fst).Pairwise (fun a b => a ≠ b) := by simp
  have hm : ("Service", encService s) ∈ ([("Service", encService s)] : List (String × Json)) := by simp
  have hn : encService s ≠ Json.null := by simp [encService, Json.mkObj]
  simp only [decEntry, encEntry, Codec.jOptField_mkObj hkeys hn hm, decService_encService]
  by_cases hb : (s.host == "") = true
  · exact absurd (of_decide_eq_true hb) h
  · simp [hb]
