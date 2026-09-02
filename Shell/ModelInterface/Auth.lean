import Shell.ModelInterface.Runtime

/-!
# Runtime model-interface authorization

This module turns transport-established trust and deployment-granted scopes
into the narrow Runtime.Access value consumed by the session driver. It does
not inspect model-interface descriptors, contracts, digests, or requests.
-/

namespace Shell.ModelInterface.Auth

/-- Trust established before a Mirrors session starts. -/
inductive TransportTrust where
  | localStdio
  | authenticatedTls
  | unauthenticatedTcp
  deriving Repr, DecidableEq

/-- Version-1 authorization scope names. -/
def verifyScope : String := "model-interface.verify"
def readDescriptorScope : String := "model-interface.read-descriptor"

/-- Operator-provided application authorization for mTLS peers. Transport
authentication alone grants no model-interface scope. Fingerprints are the
lowercase SHA-256 hex identities exposed by the verified TLS session. -/
structure TlsApplicationPolicy where
  allowedPeerFingerprints : List String := []
  descriptorRead : Bool := false
  deriving Repr, DecidableEq

/-- Authorization facts attached to one accepted session. -/
structure SessionAuthContext where
  trust : TransportTrust
  principalId : Option String
  tenantId : Option String := none
  securityRealm : String
  scopes : List String
  deriving Repr, DecidableEq

private def isLowerHex (character : Char) : Bool :=
  ('0'.toNat ≤ character.toNat && character.toNat ≤ '9'.toNat) ||
  ('a'.toNat ≤ character.toNat && character.toNat ≤ 'f'.toNat)

/-- Normalize an exact SHA-256 certificate fingerprint. -/
def normalizeFingerprint? (fingerprint : String) : Option String :=
  let normalized := fingerprint.toLower
  if normalized.length == 64 && normalized.toList.all isLowerHex then
    some normalized
  else
    none

/-- Validate and canonicalize an operator-provided peer allowlist. -/
def normalizeFingerprintAllowlist (fingerprints : List String) : Except String (List String) := do
  let normalized ← fingerprints.mapM fun fingerprint =>
    match normalizeFingerprint? fingerprint with
    | some value => pure value
    | none => throw s!"allowed client fingerprint is not a SHA-256 hex value: {fingerprint}"
  if normalized.eraseDups.length != normalized.length then
    throw "allowed client fingerprint list contains duplicates"
  return normalized

/-- Parse the comma-separated allowlist accepted by the server CLI. -/
def parseFingerprintAllowlist (raw : String) : Except String (List String) := do
  let fingerprints := (raw.splitOn ",").map (fun value => value.trimAscii.toString)
  if fingerprints.isEmpty || fingerprints.any (·.isEmpty) then
    throw "model-interface client fingerprint allowlist must not be empty"
  normalizeFingerprintAllowlist fingerprints

/-- Local stdio is an explicit trusted development principal. -/
def localStdio : SessionAuthContext where
  trust := .localStdio
  principalId := some "local-stdio"
  securityRealm := "local-stdio"
  scopes := [verifyScope, readDescriptorScope]

/-- Plain TCP establishes neither identity nor model-interface authority. -/
def unauthenticatedTcp : SessionAuthContext where
  trust := .unauthenticatedTcp
  principalId := none
  securityRealm := "unauthenticated-tcp"
  scopes := []

/--
Construct an mTLS authorization context from fingerprints obtained after
OpenSSL has verified the client certificate against the configured client CA.

The CA fingerprint scopes the security realm; the peer leaf fingerprint is the
principal. Invalid or unavailable fingerprints fail closed. A verified peer
receives no model-interface scope unless the operator policy allowlists that
exact principal.
-/
def authenticatedTls (clientCaFingerprint peerFingerprint : String)
    (policy : TlsApplicationPolicy := {}) :
    Except String SessionAuthContext := do
  let ca ← match normalizeFingerprint? clientCaFingerprint with
    | some fingerprint => pure fingerprint
    | none => throw "configured client CA fingerprint is not a SHA-256 hex value"
  let peer ← match normalizeFingerprint? peerFingerprint with
    | some fingerprint => pure fingerprint
    | none => throw "verified peer certificate fingerprint is not a SHA-256 hex value"
  let allowed ← normalizeFingerprintAllowlist policy.allowedPeerFingerprints
  let scopes :=
    if !allowed.contains peer then []
    else if policy.descriptorRead then [verifyScope, readDescriptorScope]
    else [verifyScope]
  return {
    trust := .authenticatedTls
    principalId := some ("tls-cert-sha256:" ++ peer)
    securityRealm := "mtls-ca-sha256:" ++ ca
    scopes := scopes
  }

/-- Scope membership is exact; prefixes and version ranges do not authorize. -/
def hasScope (context : SessionAuthContext) (scope : String) : Bool :=
  context.scopes.contains scope

/--
Derive the only authorization value currently threaded into session runtime.
Descriptor-read implies verify; verify alone never returns descriptor bytes.
-/
def runtimeAccess (context : SessionAuthContext) :
    Shell.ModelInterface.Runtime.Access :=
  match context.trust with
  | .unauthenticatedTcp => .disabled
  | .localStdio | .authenticatedTls =>
      if hasScope context readDescriptorScope then
        .descriptor
      else if hasScope context verifyScope then
        .verifyOnly
      else
        .disabled

/-- Cache/accounting scope derived from the same accepted session context. -/
def authorizationScope (context : SessionAuthContext) :
    Shell.ModelInterface.Runtime.AuthorizationScope where
  securityRealm := context.securityRealm
  principalId := context.principalId
  tenantId := context.tenantId

@[simp] theorem runtimeAccess_localStdio :
    runtimeAccess localStdio = .descriptor := by decide

@[simp] theorem runtimeAccess_unauthenticatedTcp :
    runtimeAccess unauthenticatedTcp = .disabled := by decide

end Shell.ModelInterface.Auth
