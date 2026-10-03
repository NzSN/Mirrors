import Core.ModelInterface.ScaffoldReview
import Core.ModelInterface.Corpus
import Codec.ModelInterfaceScaffoldJson
import Core.ModelInterface.Sha256

namespace Codec.ModelInterfaceScaffoldWorkflowJson
open Lean Core.ModelInterface

abbrev Result := Except String
abbrev Fields := List (String × Json)
def artifactLimits : StrictJson.Limits := { maxBytes := 16 * 1024 * 1024, maxDepth := 128 }

private def obj (context : String) (names required : List String) (json : Json) : Result Fields := do
  let .obj fields := json | throw s!"{context}: object expected"
  let fields := fields.toList
  if let some bad := fields.find? fun f => !names.contains f.1 then
    throw s!"{context}: unknown field {bad.1}"
  if let some missing := required.find? fun name => (List.lookup name fields).isNone then
    throw s!"{context}: missing required field {missing}"
  return fields

private def get (fields : Fields) (key : String) : Result Json :=
  match List.lookup key fields with
  | some value => .ok value
  | none => .error s!"missing {key}"
private def str : Json → Result String
  | .str s => .ok s
  | _ => .error "string expected"
private def bool : Json → Result Bool
  | .bool b => .ok b
  | _ => .error "boolean expected"
private def arr (decode : Json → Result α) : Json → Result (List α)
  | .arr values => values.toList.mapM decode
  | _ => .error "array expected"
private def strings (values : List String) : Json := .arr (values.map Json.str).toArray
private def array (values : List Json) : Json := .arr values.toArray
private def digestOK (s : String) : Bool :=
  s.length == 64 && s.toList.all fun c => c.isDigit || ('a' ≤ c && c ≤ 'f')

private def sourceJson (s : SourceDigest) : Json := Json.mkObj [
  ("module", .str s.moduleName), ("path", .str s.logicalPath), ("sha256", .str s.contentSha256)]
private def sourceDecode (json : Json) : Result SourceDigest := do
  let f ← obj "source" ["module", "path", "sha256"] ["module", "path", "sha256"] json
  let s : SourceDigest := {
    moduleName := ← str (← get f "module")
    logicalPath := ← str (← get f "path")
    contentSha256 := ← str (← get f "sha256") }
  if !validModuleName s.moduleName || !validLogicalPath s.logicalPath || !digestOK s.contentSha256 then
    throw "invalid source identity"
  return s

def encodeProposal (p : ReviewableScaffold) : Json :=
  Json.mkObj ([
    ("schema", .str p.schema),
    ("scaffold", ModelInterfaceScaffoldJson.encodeProposal p.scaffold),
    ("sources", array ((p.sources.mergeSort fun a b => a.logicalPath ≤ b.logicalPath).map sourceJson)),
    ("members", array ((p.members.mergeSort fun a b => a.rawFileSha256 ≤ b.rawFileSha256).map
      ModelInterfaceJson.encodeWorkflowEvidenceMember)),
    ("observed", Json.mkObj [("initializers", strings (sortStrings p.observedInitializers)),
      ("transitions", strings (sortStrings p.observedTransitions))]) ] ++
    p.projectionPlanSha256.toList.map fun s => ("projectionPlanSha256", .str s))

def decodeProposal (json : Json) : Result ReviewableScaffold := do
  if (json.getObjValAs? String "schema").toOption == some scaffoldSchemaV1 then
    throw "legacy v1 proposal lacks exact raw/source closure identities; regenerate with scaffold --reviewable"
  let f ← obj "proposal" ["schema", "scaffold", "sources", "members", "observed", "projectionPlanSha256"]
    ["schema", "scaffold", "sources", "members", "observed"] json
  let schema ← str (← get f "schema")
  if schema != reviewableScaffoldSchemaV1 then throw "unsupported reviewable proposal schema"
  let observed ← obj "observed" ["initializers", "transitions"] ["initializers", "transitions"]
    (← get f "observed")
  let p : ReviewableScaffold := {
    schema
    scaffold := ← ModelInterfaceScaffoldJson.decodeProposal (← get f "scaffold"),
    sources := ← arr sourceDecode (← get f "sources"),
    members := ← arr ModelInterfaceJson.decodeWorkflowEvidenceMember (← get f "members"),
    projectionPlanSha256 := ← match List.lookup "projectionPlanSha256" f with
      | none => pure none
      | some j => pure (some (← str j)),
    observedInitializers := ← arr str (← get observed "initializers"),
    observedTransitions := ← arr str (← get observed "transitions") }
  if p.sources.isEmpty || p.sources.length > maxCorpusSourcesV1 ||
      !(duplicateStrings (p.sources.map (·.logicalPath))).isEmpty ||
      !(duplicateStrings (p.sources.map (·.moduleName))).isEmpty ||
      !p.sources.contains p.scaffold.source then
    throw "proposal requires a unique complete source manifest containing the root"
  if p.scaffold.projection.isSome then throw "reviewable projections belong to individual members"
  if sortStrings p.observedInitializers != sortStrings (p.scaffold.contract.initializers.map (·.wireAction)) ||
      sortStrings p.observedTransitions != sortStrings (p.scaffold.contract.actions.map (·.wireAction)) then
    throw "proposal observed labels differ from inferred scaffold"
  ModelInterfaceJson.validateWorkflowProvenance {
    proposalSha256 := String.ofList (List.replicate 64 '0'),
    reviewSha256 := String.ofList (List.replicate 64 '0'),
    projectionPlanSha256 := p.projectionPlanSha256, members := p.members }
  return p

private def replacementJson (r : ScaffoldReplacement) : Json :=
  Json.mkObj [("kind", .str r.kind), ("from", .str r.fromId), ("to", .str r.toId)]
private def replacementDecode (json : Json) : Result ScaffoldReplacement := do
  let f ← obj "replacement" ["kind", "from", "to"] ["kind", "from", "to"] json
  return { kind := ← str (← get f "kind"), fromId := ← str (← get f "from"), toId := ← str (← get f "to") }
private def obligationJson (r : ScaffoldObligationDisposition) : Json :=
  Json.mkObj [("stableId", .str r.stableId), ("disposition", .str r.disposition),
    ("target", .str r.target), ("reason", .str r.reason)]
private def obligationDecode (json : Json) : Result ScaffoldObligationDisposition := do
  let f ← obj "obligation" ["stableId", "disposition", "target", "reason"]
    ["stableId", "disposition", "target", "reason"] json
  return {
    stableId := ← str (← get f "stableId")
    disposition := ← str (← get f "disposition")
    target := ← str (← get f "target")
    reason := ← str (← get f "reason") }

def encodeReview (r : ScaffoldReview) : Json := Json.mkObj [
  ("schema", .str r.schema), ("approved", .bool r.approved), ("proposalSha256", .str r.proposalSha256),
  ("universes", Json.mkObj [("complete", .bool r.complete),
    ("initializers", strings (sortStrings r.initializers)), ("transitions", strings (sortStrings r.transitions))]),
  ("contract", ModelInterfaceJson.encodeContract (normalizeContractV1 r.contract)),
  ("replacements", array ((r.replacements.mergeSort fun a b =>
    a.kind ++ "/" ++ a.fromId ≤ b.kind ++ "/" ++ b.fromId).map replacementJson)),
  ("obligations", array ((r.obligations.mergeSort fun a b => a.stableId ≤ b.stableId).map obligationJson))]

def decodeReview (json : Json) : Result ScaffoldReview := do
  let names := ["schema", "approved", "proposalSha256", "universes", "contract", "replacements", "obligations"]
  let f ← obj "review" names names json
  let universes ← obj "universes" ["complete", "initializers", "transitions"]
    ["complete", "initializers", "transitions"] (← get f "universes")
  let r : ScaffoldReview := {
    schema := ← str (← get f "schema"), approved := ← bool (← get f "approved"),
    proposalSha256 := ← str (← get f "proposalSha256"), complete := ← bool (← get universes "complete"),
    initializers := ← arr str (← get universes "initializers"), transitions := ← arr str (← get universes "transitions"),
    contract := ← ModelInterfaceJson.decodeContract (← get f "contract"),
    replacements := ← arr replacementDecode (← get f "replacements"),
    obligations := ← arr obligationDecode (← get f "obligations") }
  if r.schema != scaffoldReviewSchemaV1 || !r.approved || !r.complete || !digestOK r.proposalSha256 then
    throw "review requires supported schema, literal approved:true, complete:true, and valid proposal digest"
  return r

def encodeReceipt (r : ScaffoldReviewReceipt) : Json := Json.mkObj [
  ("schema", .str r.schema), ("proposalSha256", .str r.proposalSha256),
  ("reviewSha256", .str r.reviewSha256), ("contractSha256", .str r.contractSha256)]
def decodeReceipt (json : Json) : Result ScaffoldReviewReceipt := do
  let names := ["schema", "proposalSha256", "reviewSha256", "contractSha256"]
  let f ← obj "receipt" names names json
  let r : ScaffoldReviewReceipt := {
    schema := ← str (← get f "schema"),
    proposalSha256 := ← str (← get f "proposalSha256"), reviewSha256 := ← str (← get f "reviewSha256"),
    contractSha256 := ← str (← get f "contractSha256") }
  if r.schema != scaffoldReviewReceiptSchemaV1 ||
      ![r.proposalSha256, r.reviewSha256, r.contractSha256].all digestOK then throw "invalid review receipt"
  return r

def proposalDigest (p : ReviewableScaffold) : String :=
  Sha256.digestDomainHex reviewableScaffoldSchemaV1 (ModelInterfaceJson.canonicalBytes (encodeProposal p))
def reviewDigest (r : ScaffoldReview) : String :=
  Sha256.digestDomainHex scaffoldReviewSchemaV1 (ModelInterfaceJson.canonicalBytes (encodeReview r))
def proposalFileBytes (p : ReviewableScaffold) := ModelInterfaceJson.canonicalFileBytes (encodeProposal p)
def reviewFileBytes (r : ScaffoldReview) := ModelInterfaceJson.canonicalFileBytes (encodeReview r)
def receiptFileBytes (r : ScaffoldReviewReceipt) := ModelInterfaceJson.canonicalFileBytes (encodeReceipt r)
def parseProposalBytes (bytes : ByteArray) : Result ReviewableScaffold := do
  decodeProposal (← (StrictJson.parseBytes bytes artifactLimits).mapError toString)
def parseReviewBytes (bytes : ByteArray) : Result ScaffoldReview := do
  decodeReview (← (StrictJson.parseBytes bytes artifactLimits).mapError toString)
def parseReceiptBytes (bytes : ByteArray) : Result ScaffoldReviewReceipt := do
  decodeReceipt (← (StrictJson.parseBytes bytes artifactLimits).mapError toString)

end Codec.ModelInterfaceScaffoldWorkflowJson
