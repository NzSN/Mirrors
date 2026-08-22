import Codec.Json

/-!
# Consul registry wire codec (feeds t16)

Typed payload layer for the Consul agent HTTP API surface used by the
Haskell registry client (ModelMirros@3496251, src/Protocol/Registry.hs
and src/Protocol/Discover.hs):

* `PUT /v1/agent/service/register` — body `{ID, Name ("modelmirros"),
  Address, Port, Meta, Check:{TTL:"30s"}}`; `Meta` is `{}` when no
  certificate fingerprint is advertised and `{"cert-sha256": fp}` when
  one is.
* `PUT /v1/agent/check/pass/service:{sid}` — no body (TTL heartbeat).
* `PUT /v1/agent/service/deregister/{sid}` — no body.
* `GET /v1/health/service/modelmirros?passing=true` — response is a
  JSON array of health entries; only each entry's `Service` object is
  read (`ID`, `Address`, `Port`, optional `Meta.cert-sha256`).
  Entries with an empty `Address` are dropped; other entry fields
  (`Node`, `Checks`, ...) are ignored, and a malformed entry yields
  no services for that entry (Haskell's `toServiceInfo` fails closed
  per entry).

One deliberate divergence: `Port` must be an integral JSON number (the
Haskell code `fromIntegral (round port)` also accepts fractional ports
by rounding — Consul itself always emits integers). -/

open Lean

namespace Consul

/-! ## Types -/

/-- A mirror service as registered/discovered via Consul. `port` is
the `PortNumber` (Word16) of the Haskell client. -/
structure ServiceInfo where
  serviceId : String
  host : String
  port : Nat
  certFingerprint : Option String
  deriving Repr, DecidableEq

/-- Wire predicate: nonempty host (discovery drops empty addresses) and
a port representable as a Haskell `PortNumber`. -/
def ServiceOk (s : ServiceInfo) : Prop := s.host ≠ "" ∧ s.port ≤ 65535

/-! ## HTTP surface -/

inductive ConsulRequest where
  | register (info : ServiceInfo)
  | passCheck (sid : String)
  | deregister (sid : String)
  | discover
  deriving Repr, DecidableEq

def serviceName : String := "modelmirros"

def requestMethod : ConsulRequest → String
  | .register _ | .passCheck _ | .deregister _ => "PUT"
  | .discover => "GET"

def requestPath : ConsulRequest → String
  | .register _ => "/v1/agent/service/register"
  | .passCheck sid => "/v1/agent/check/pass/service:" ++ sid
  | .deregister sid => "/v1/agent/service/deregister/" ++ sid
  | .discover => "/v1/health/service/" ++ serviceName ++ "?passing=true"

/-! ## Payload encoding -/

/-- `Meta` field: `{}` without a fingerprint, otherwise the singleton
`cert-sha256` map (Haskell: `maybe Map.empty (Map.singleton
"cert-sha256")`). -/
def jMeta (fp : Option String) : Json :=
  match fp with
  | some f => Json.mkObj [("cert-sha256", Json.str f)]
  | none => Json.mkObj []

/-- Registration body (Haskell `registerService`). -/
def encodeRegisterBody (i : ServiceInfo) : Json :=
  Json.mkObj [
    ("ID", Json.str i.serviceId),
    ("Name", Json.str serviceName),
    ("Address", Json.str i.host),
    ("Port", Json.num i.port),
    ("Meta", jMeta i.certFingerprint),
    ("Check", Json.mkObj [("TTL", Json.str "30s")])
  ]

/-- The `Service` sub-object of a health entry. -/
def encService (s : ServiceInfo) : Json :=
  Json.mkObj [
    ("ID", Json.str s.serviceId),
    ("Address", Json.str s.host),
    ("Port", Json.num s.port),
    ("Meta", jMeta s.certFingerprint)
  ]

def requestBody : ConsulRequest → Option Json
  | .register info => some (encodeRegisterBody info)
  | .passCheck _ | .deregister _ | .discover => none

/-- One canonical health entry. -/
def encEntry (s : ServiceInfo) : Json :=
  Json.mkObj [("Service", encService s)]

/-- Canonical health-response array for a list of services. -/
def encodeServices (l : List ServiceInfo) : Json :=
  Json.arr ((l.map encEntry).toArray)

/-! ## Payload decoding -/

open Codec (derr Dec)

/-- Fingerprint from a `Meta` value: a non-object `Meta`, or a missing
/ non-string `cert-sha256` entry, yields `none` (Haskell's fingerprint
extraction). -/
def decMetaFp (m : Json) : Dec (Option String) :=
  match m with
  | .obj _ =>
      match Codec.jOptStr m "cert-sha256" with
      | Except.ok fp => Except.ok fp
      | Except.error _ => Except.ok none
  | _ => Except.ok none

/-- Optional `Meta` lookup on a service object. -/
def decFingerprint (j : Json) : Dec (Option String) :=
  match Codec.jOptField j "Meta" with
  | Except.ok (some m) => decMetaFp m
  | Except.ok none => Except.ok none
  | Except.error _ => Except.ok none

/-- Decode a registration body. -/
def decodeRegisterBody (j : Json) : Dec ServiceInfo := do
  let id ← Codec.jStr j "ID"
  let name ← Codec.jStr j "Name"
  if name != serviceName then
    derr s!"register: unexpected service name: {name}"
  let host ← Codec.jStr j "Address"
  let port ← Codec.jNat j "Port"
  let fp ← decFingerprint j
  return { serviceId := id, host := host, port := port, certFingerprint := fp }

/-- Decode a `Service` object. -/
def decService (j : Json) : Dec ServiceInfo := do
  let id ← Codec.jStr j "ID"
  let host ← Codec.jStr j "Address"
  let port ← Codec.jNat j "Port"
  let fp ← decFingerprint j
  return { serviceId := id, host := host, port := port, certFingerprint := fp }

/-- Decode one health entry; entries with an empty `Address` are
dropped (Haskell's `toServiceInfo`). Malformed entries yield no
services (fail closed per entry). -/
def decEntry (j : Json) : Dec (List ServiceInfo) :=
  match Codec.jOptField j "Service" with
  | Except.ok (some m) =>
      match decService m with
      | Except.ok s => if s.host == "" then Except.ok [] else Except.ok [s]
      | Except.error _ => Except.ok []
  | _ => Except.ok []

/-- Structural decode of the entry list. -/
def decodeServicesL : List Json → Dec (List ServiceInfo)
  | [] => Except.ok []
  | j :: js => do
      let es ← decEntry j
      let rest ← decodeServicesL js
      return es ++ rest

/-- Decode a health response: array of entries. -/
def decodeServices (j : Json) : Dec (List ServiceInfo) :=
  match j with
  | .arr as => decodeServicesL as.toList
  | _ => derr "health: expected array of entries"

/-! ## §6.6-style round trips -/

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

theorem decodeServicesL_encEntries (l : List ServiceInfo) (h : ∀ s ∈ l, s.host ≠ "") :
    decodeServicesL (l.map encEntry) = Except.ok l := by
  induction l with
  | nil => rfl
  | cons s ss ih =>
      have hs : s.host ≠ "" := h s (by simp)
      have hss : ∀ x ∈ ss, x.host ≠ "" := fun x hx => h x (by simp [hx])
      show ((decEntry (encEntry s)) >>= fun es =>
             decodeServicesL (ss.map encEntry) >>= fun rest => Except.ok (es ++ rest))
        = Except.ok (s :: ss)
      rw [decEntry_encEntry s hs, ih hss]
      rfl

theorem decodeServices_encodeServices (l : List ServiceInfo)
    (h : ∀ s ∈ l, s.host ≠ "") :
    decodeServices (encodeServices l) = Except.ok l := by
  have hm := decodeServicesL_encEntries l h
  simp only [decodeServices, encodeServices]
  exact hm

end Consul
