import Shell.ModelInterface.Compiler
import Codec.ModelInterfaceScheduleKitJson

namespace Shell.ModelInterface.Emit.ScheduleKit
open Core.ModelInterface Core.ModelInterface.ScheduleKit _root_.Lean
open TypeScript

private def q (value : String) : String := Json.compress (.str value)
private def lines (values : List String) : String := String.intercalate "\n" values ++ "\n"

def profile (target : String) : Except String String :=
  if ["mirrorcpp-v1", "mirrorcpp-v2"].contains target then .ok "mirrorcpp.cooperative-checkpoints/v1"
  else if ["mirrorrust-v1", "mirrorrust-v2"].contains target then .ok "mirrorrust.cooperative-checkpoints/v1"
  else if ["mirrorecma-async-v1", "mirrorecma-async-v2"].contains target then .ok "mirrorecma.worker-checkpoints/v1"
  else .error "DPM kit requires an accepted C++, async-ECMA or Rust execution profile"

private def selectedActor (mapping : ActionMapping) (language : String) : String :=
  match mapping.actorSource with
  | .fixed actor => q actor
  | .input _ => if language == "rust" then "actor.ok_or(\"actor argument required\")?"
    else if language == "cpp" then "actorArgument" else "actor"

private def renderCpp (plan : Plan) (digest suffix : String) : String :=
  let membership := String.intercalate " && " (plan.actors.map fun a => s!"selected != {q a.actor}")
  let cases := plan.actions.flatMap fun a =>
    ["  if (actionId == " ++ q a.actionId ++ ") {",
      s!"    std::string_view selected = {selectedActor a "cpp"};"] ++
      (match a.actorSource with
        | .fixed _ => ["    if (!actorArgument.empty() && actorArgument != selected) throw std::invalid_argument(\"fixed actor disagreement\");"]
        | .input _ => []) ++
      [s!"    if ({membership}) throw std::invalid_argument(\"undeclared kit actor\");",
       "    return {std::string(selected), " ++ q a.checkpoint ++ "};", "  }"]
  lines (["// Generated DPM wiring only. Application behavior stays handwritten.",
    "#pragma once", "#include <mirrorcpp/schedule.hpp>", "#include <stdexcept>",
    "namespace mirrors_generated::" ++ suffix ++ " {",
    s!"inline constexpr std::string_view model_semantic_digest = {q plan.semanticDigest};",
    s!"inline constexpr std::string_view mapping_sha256 = {q digest};",
    "inline std::vector<mirrorcpp::schedule::ActorDeclaration> actors() { return {" ++
      String.intercalate "," (plan.actors.map fun a => "{" ++ q a.actor ++ "," ++ q a.operation ++ "}") ++ "}; }",
    "inline std::vector<std::string> checkpoints() { return {" ++
      String.intercalate "," ((plan.actions.map (·.checkpoint)).filter (· != "$done") |>.eraseDups |>.map q) ++ "}; }",
    "inline mirrorcpp::schedule::Step step_for(std::string_view actionId, std::string_view actorArgument = {}) {"] ++
    cases ++ ["  throw std::invalid_argument(\"unmapped kit action\");", "}", "}"])

private def renderTs (plan : Plan) (digest : String) : String :=
  let cases := plan.actions.flatMap fun a =>
    ["    case " ++ q a.actionId ++ ": {", s!"      const selected = {selectedActor a "ts"};"] ++
    (match a.actorSource with
      | .fixed _ => ["      if (actor !== undefined && actor !== selected) throw new Error('fixed actor disagreement');"]
      | .input _ => []) ++
    ["      if (typeof selected !== 'string' || !actorIds.includes(selected)) throw new Error('undeclared kit actor');",
     "      return {actor: selected, checkpoint: " ++ q a.checkpoint ++ "};", "    }"]
  lines (["// Generated DPM wiring only. Application behavior stays handwritten.",
    "import type { ScheduleStep, ScheduleActor } from 'mirrorecma';",
    s!"export const modelSemanticDigest = {q plan.semanticDigest};",
    s!"export const mappingSha256 = {q digest};",
    "const actorIds: readonly string[] = Object.freeze([" ++ String.intercalate "," (plan.actors.map (q ∘ (·.actor))) ++ "]);",
    "export const actors: readonly ScheduleActor[] = Object.freeze([" ++
      String.intercalate "," (plan.actors.map fun a => "Object.freeze({actor:" ++ q a.actor ++ ",operation:" ++ q a.operation ++ "})") ++ "]);",
    "export const checkpoints: readonly string[] = Object.freeze([" ++
      String.intercalate "," ((plan.actions.map (·.checkpoint)).filter (· != "$done") |>.eraseDups |>.map q) ++ "]);",
    "export function stepFor(actionId: string, actor?: string): ScheduleStep {", "  switch (actionId) {"] ++
    cases ++ ["    default: throw new Error('unmapped kit action');", "  }", "}"])

private def renderRust (plan : Plan) (digest : String) : String :=
  let cases := plan.actions.flatMap fun a =>
    ["        " ++ q a.actionId ++ " => {", s!"            let selected = {selectedActor a "rust"};"] ++
    (match a.actorSource with
      | .fixed _ => ["            if actor.is_some_and(|v| v != selected) { return Err(\"fixed actor disagreement\".into()); }"]
      | .input _ => []) ++
    ["            if !ACTORS.iter().any(|(name, _)| *name == selected) { return Err(\"undeclared kit actor\".into()); }",
     s!"            Ok(mirrorrust::schedule::Step::new(selected, {q a.checkpoint}))", "        }"]
  lines (["// Generated DPM wiring only. Application behavior stays handwritten.",
    s!"pub const MODEL_SEMANTIC_DIGEST: &str = {q plan.semanticDigest};",
    s!"pub const MAPPING_SHA256: &str = {q digest};",
    "pub const ACTORS: &[(&str, &str)] = &[" ++ String.intercalate "," (plan.actors.map fun a => "(" ++ q a.actor ++ "," ++ q a.operation ++ ")") ++ "];",
    "pub const CHECKPOINTS: &[&str] = &[" ++
      String.intercalate "," ((plan.actions.map (·.checkpoint)).filter (· != "$done") |>.eraseDups |>.map q) ++ "];",
    "pub fn step_for(action_id: &str, actor: Option<&str>) -> Result<mirrorrust::schedule::Step, String> {",
    "    match action_id {"] ++ cases ++ ["        _ => Err(\"unmapped kit action\".into()),", "    }", "}"])

def emit (lock : LockedModelInterface) (plan : Plan) (target : String) :
    Except Compiler.CompilerError GeneratedTree := do
  let fail := fun message => ({ kind := .finding, message } : Compiler.CompilerError)
  let schedulingProfile ← (profile target).mapError fail
  (validate lock plan).mapError fail
  let plan := { plan with
    actors := plan.actors.mergeSort (fun a b => a.actor ≤ b.actor)
    actions := plan.actions.mergeSort (fun a b => a.actionId ≤ b.actionId) }
  let base ← Compiler.emitTarget target lock
  let planBytes := Codec.ModelInterfaceScheduleKitJson.canonicalBytes plan
  let digest := Core.ModelInterface.Sha256.digestHex planBytes
  let suffix := "dpm_" ++ String.ofList (lock.semanticDigest.toList.take 16)
  let (helperPath, source) := if target.startsWith "mirrorcpp" then
      ("DpmKit.generated.hpp", renderCpp plan digest suffix)
    else if target.startsWith "mirrorrust" then
      ("DpmKit.generated.rs", renderRust plan digest)
    else ("DpmKit.generated.ts", renderTs plan digest)
  let relations := plan.actions.map fun mapping =>
    let action := lock.actions.find? (·.id == mapping.actionId)
    Json.mkObj [("actionId", .str mapping.actionId),
      ("wireAction", .str (action.map (·.wireAction) |>.getD "")),
      ("checkpoint", .str mapping.checkpoint)]
  let metadata := Json.mkObj [
    ("schema", .str "mirrors.dpm-kit-metadata/v1"), ("modelSemanticDigest", .str lock.semanticDigest),
    ("mappingSha256", .str digest), ("targetProfile", .str target),
    ("schedulingProfile", .str schedulingProfile), ("cppNamespace", .str s!"mirrors_generated::{suffix}"),
    ("relations", .arr relations.toArray), ("applicationInstrumentationRequired", .bool true)]
  let integrationDoc := lines ["# Generated DPM integration checklist", "",
    "Copy application behavior into your own module outside this generated tree.",
    "1. Admit the modelSemanticDigest/mappingSha256 constants and your actual implementation hash.",
    "2. Use generated actors/checkpoints in the SDK adapter; implement its deferred factory.",
    "3. Insert actual arrive(checkpoint) calls at safe points inside owned workers.",
    "4. initialize -> session.initialize(); transition -> session.advance(step_for/stepFor(actionId, actor)).",
    "5. Observe actual application state through the ordinary generated typed port.",
    "6. Dispose once and retain primary comparison plus cleanup independently.",
    "", "Actor input arguments refer to explicit generated input IDs in DpmKit.plan.json.",
    "Fixed actors need no actor argument; disagreement is rejected.",
    "The kit does not infer behavior, inject hooks or initialize from expected model state."]
  let (examplePath, applicationExample) := if target.startsWith "mirrorcpp" then
      ("DpmKit.application.example.hpp", lines [
        "// Copy to your application; this generated seed is not your SUT implementation.",
        "#pragma once", "#include \"DpmKit.generated.hpp\"", "#include <mirrorcpp/schedule_binding.hpp>",
        "namespace mirrors_generated::" ++ suffix ++ "_example {",
        "inline void initialize(mirrorcpp::schedule::BindingSession& session) { session.initialize(); }",
        "inline void transition(mirrorcpp::schedule::BindingSession& session, std::string_view action, std::string_view actor = {}) {",
        "  session.advance(mirrors_generated::" ++ suffix ++ "::step_for(action, actor));", "}",
        "// A handwritten typed port calls these after binding admission.",
        "// Supply a deferred factory, actual checkpoint workers and native typed observation.",
        "}"])
    else if target.startsWith "mirrorrust" then
      ("DpmKit.application.example.rs", lines [
        "// Copy to your application; implement actual behavior outside generated files.",
        "// Include DpmKit.generated.rs as a module named dpm_kit.",
        "use mirrorrust::schedule_binding::BindingSession;",
        "pub fn initialize(session: &mut BindingSession) -> Result<(), String> { session.initialize().map_err(|e| e.to_string()) }",
        "pub fn transition(session: &mut BindingSession, action: &str, actor: Option<&str>) -> Result<(), String> {",
        "    session.advance(&crate::dpm_kit::step_for(action, actor)?).map_err(|e| e.to_string())", "}",
        "// Handwritten typed port: convert session observation to its actual native observation type.",
        "// Own deferred workers/checkpoint hooks and disposal; never seed expected model state."])
    else ("DpmKit.application.example.ts", lines [
      "// Copy to your application; implement actual behavior outside generated files.",
      "import type { ScheduleBindingSession } from 'mirrorecma';",
      "import { stepFor } from './DpmKit.generated.js';",
      "export function callbacks(session: ScheduleBindingSession) {",
      "  return {initialize: () => session.initialize(),",
      "    transition: (action: string, actor?: string) => session.advance(stepFor(action, actor)),",
      "    observation: () => session.observation(), dispose: () => session.dispose()};", "}",
      "// Handwritten generated public port forwards its typed actor input to transition.",
      "// Provide actual Node-worker hooks and convert real observations to the model-native shape."])
  let extra : List GeneratedFile := [
    { relativePath := helperPath, bytes := source.toUTF8 },
    { relativePath := examplePath, bytes := applicationExample.toUTF8 },
    { relativePath := "DpmKit.plan.json", bytes := planBytes },
    { relativePath := "DpmKit.metadata.json", bytes := Codec.ModelInterfaceJson.canonicalFileBytes metadata },
    { relativePath := "DpmKit.integration.md", bytes := integrationDoc.toUTF8 }]
  let payload := base.files.filter (·.relativePath != ".model-interface-generated.json") ++ extra
  let paths := (payload.map (·.relativePath) ++ [".model-interface-generated.json"]).mergeSort (· ≤ ·)
  let some originalManifest := base.files.find? (·.relativePath == ".model-interface-generated.json")
    | throw (fail "target ownership manifest missing")
  let originalJson ← (Codec.StrictJson.parseBytes originalManifest.bytes).mapError (fun e => fail (toString e))
  let version ← (originalJson.getObjVal? "profileVersion").mapError fail
  let manifest := Json.mkObj [("files", .arr (paths.map Json.str).toArray),
    ("profileVersion", version),
    ("schema", .str "mirrors.model-interface-generated/v1"),
    ("semanticDigest", .str lock.semanticDigest), ("targetProfile", .str target)]
  let ownership : GeneratedFile := {
    relativePath := ".model-interface-generated.json"
    bytes := Codec.ModelInterfaceJson.canonicalFileBytes manifest }
  return { files := (payload ++ [ownership]).mergeSort (fun a b => a.relativePath ≤ b.relativePath) }

end Shell.ModelInterface.Emit.ScheduleKit
