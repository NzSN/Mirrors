/-!
# Bounded domain-reduction contracts

The first domain profile permits only integer input shrinking for the checked
LeaseService trace.  This pure layer validates a requested transform; it does
not execute Apalache, construct an application, or treat application output as
a model-validity oracle.
-/

namespace Core.ModelInterface

def leaseServiceInputShrinkSchema : String :=
  "mirrors.reduction-candidate/lease-service-input-shrink/v1"

def leaseServiceInputShrinkProfile : String :=
  "lease-service-input-shrink/v1"

def leaseServiceInputShrinkDomainVersion : String :=
  "LeaseService.Next/v1"

structure LeaseInputEdit where
  stateIndex : Nat
  actionId : String
  inputId : String
  before : Int
  after : Int
  deriving Repr, DecidableEq

structure LeaseReductionCandidate where
  schema : String
  modelSha256 : String
  interfaceDigest : String
  orderedCorpusSha256 : String
  originalBundleSha256 : String
  selectedTraceSha256 : String
  traceIndex : Nat
  traceOccurrences : List Nat
  edits : List LeaseInputEdit
  deriving Repr, DecidableEq

inductive ReductionRefusalCode where
  | schemaUnsupported
  | identityMalformed
  | traceUnsupported
  | editsEmpty
  | editsExceeded
  | editDuplicate
  | actionUnsupported
  | inputUnsupported
  | transformUnsupported
  deriving Repr, DecidableEq

structure ReductionRefusal where
  code : ReductionRefusalCode
  detail : String
  deriving Repr, DecidableEq

structure ValidatedLeaseReduction where
  candidate : LeaseReductionCandidate
  profile : String := leaseServiceInputShrinkProfile
  domainVersion : String := leaseServiceInputShrinkDomainVersion
  deriving Repr, DecidableEq

private def lowerHex (char : Char) : Bool :=
  ('0'.toNat ≤ char.toNat && char.toNat ≤ '9'.toNat) ||
  ('a'.toNat ≤ char.toNat && char.toNat ≤ 'f'.toNat)

def validSha256 (value : String) : Bool :=
  value.length == 64 && value.toList.all lowerHex

private def supportedInput (edit : LeaseInputEdit) : Bool :=
  match edit.actionId, edit.inputId with
  | "Acquire", "Client" => true
  | "Renew", "Client" | "Renew", "Token" => true
  | "Release", "Client" | "Release", "Token" => true
  | "Write", "Client" | "Write", "Token" => true
  | _, _ => false

private def supportedAction (actionId : String) : Bool :=
  ["Acquire", "Renew", "Release", "Write"].contains actionId

private def editKey (edit : LeaseInputEdit) : String :=
  s!"{edit.stateIndex}:{edit.actionId}:{edit.inputId}"

private def duplicateStrings : List String → List String
  | [] => []
  | value :: rest =>
      let duplicates := duplicateStrings rest
      if rest.contains value && !duplicates.contains value then value :: duplicates
      else duplicates

def validateLeaseReduction
    (candidate : LeaseReductionCandidate) :
    Except ReductionRefusal ValidatedLeaseReduction := do
  if candidate.schema != leaseServiceInputShrinkSchema then
    throw { code := .schemaUnsupported, detail := "unsupported reduction schema" }
  if !validSha256 candidate.modelSha256 ||
      !validSha256 candidate.interfaceDigest ||
      !validSha256 candidate.orderedCorpusSha256 ||
      !validSha256 candidate.originalBundleSha256 ||
      !validSha256 candidate.selectedTraceSha256 then
    throw { code := .identityMalformed, detail := "identity must be lowercase SHA-256" }
  if candidate.traceIndex != 0 then
    throw { code := .traceUnsupported, detail := "version 1 supports selected trace zero only" }
  if candidate.traceOccurrences != [0, 1] then
    throw {
      code := .traceUnsupported
      detail := "version 1 requires the selected trace at ordered occurrences zero and one"
    }
  if candidate.edits.isEmpty then
    throw { code := .editsEmpty, detail := "at least one input edit is required" }
  if candidate.edits.length > 16 then
    throw { code := .editsExceeded, detail := "input edit limit exceeded" }
  if !(duplicateStrings (candidate.edits.map editKey)).isEmpty then
    throw { code := .editDuplicate, detail := "duplicate input edit" }
  for edit in candidate.edits do
    if edit.stateIndex == 0 then
      throw { code := .transformUnsupported, detail := "initializer input cannot be reduced" }
    if !supportedAction edit.actionId then
      throw { code := .actionUnsupported, detail := s!"unsupported action {edit.actionId}" }
    if !supportedInput edit then
      throw {
        code := .inputUnsupported
        detail := s!"unsupported input {edit.actionId}.{edit.inputId}"
      }
    if edit.before != 2 || edit.after != 1 then
      throw {
        code := .transformUnsupported
        detail := "version 1 permits only the finite-domain shrink 2 to 1"
      }
  return { candidate := candidate }

end Core.ModelInterface
