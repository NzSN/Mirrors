import Shell.ModelInterface.Emit.TypeScript

/-!
# Async TypeScript model-interface emitter

This profile reuses the reviewed TypeScript type, name, projection, and codec
lowering.  Only the native effect interpretation is different: port calls are
awaited with a replay context, the single-flight guard spans every await, and
an error, cancellation, deadline, or reentrant call poisons the binding.
-/

namespace Shell.ModelInterface.Emit.TypeScriptAsync

open Core.ModelInterface
open Shell.ModelInterface.Emit.TypeScript

def targetProfile : String := "mirrorecma-async-v1"
def stateComputerContractVersion : String := "mirrors.async-state-computer/v1"

private def manifestPath : String := ".model-interface-generated.json"

private def renderPortMethod (action : ResolvedAction) : String :=
  if action.inputs.isEmpty then
    s!"  {Shared.nativeName action.id}(context: ReplayContext): Promise<void>;"
  else
    s!"  {Shared.nativeName action.id}(input: {action.id}Input, context: ReplayContext): Promise<void>;"

private def renderActionCases (action : ResolvedAction) : String :=
  let labels := action.wireAction :: Shared.sortStrings action.wireAliases
  let cases := labels.map (fun label => s!"      case {Shared.quote label}:")
  let precondition := match action.phase with
    | .initialize => []
    | .transition =>
        ["        if (lifecycle === \"fresh\") throw bindingError(\"transition_before_initialization\", \"transition before initialization\");"]
  let callLines :=
    if action.inputs.isEmpty then
      ["        stage = \"adapter\";",
       "        ensureContextActive(context);",
       s!"        await awaitPortOperation(port.{Shared.nativeName action.id}(context), context);",
       "        ensureContextActive(context);",
       "        ensureBindingActive();"]
    else
      ["        stage = \"input\";",
       s!"        const input = decode{action.id}Input(payload);",
       "        stage = \"adapter\";",
       "        ensureContextActive(context);",
       s!"        await awaitPortOperation(port.{Shared.nativeName action.id}(input, context), context);",
       "        ensureContextActive(context);",
       "        ensureBindingActive();"]
  Shared.joinLines <| cases ++ ["      {"] ++ precondition ++ callLines ++
    ["        lifecycle = \"initialized\";",
     s!"        actionId = {Shared.quote action.id};",
     "        break;",
     "      }"]

private def renderPublicOperation (action : ResolvedAction) : Lean.Json :=
  let inputs := Shared.sortByKey (fun input => input.id) action.inputs |>.map fun input =>
    Lean.Json.mkObj [
      ("id", .str input.id),
      ("type", Codec.ModelInterfaceJson.encodeModelType input.projection.type)
    ]
  Lean.Json.mkObj [
    ("id", .str action.id),
    ("inputs", .arr inputs.toArray)
  ]

private def renderPublicManifest (lock : LockedModelInterface) : String :=
  let initializers := Shared.sortByKey (fun action => action.id) lock.initializers
  let actions := Shared.sortByKey (fun action => action.id) lock.actions
  let observations := Shared.sortByKey (fun observation => observation.id)
    lock.observations |>.map fun observation => Lean.Json.mkObj [
      ("id", .str observation.id),
      ("type", Codec.ModelInterfaceJson.encodeModelType observation.type)
    ]
  Lean.Json.compress <| Lean.Json.mkObj [
    ("actions", .arr (actions.map renderPublicOperation).toArray),
    ("initializers", .arr (initializers.map renderPublicOperation).toArray),
    ("interfaceDigest", .str lock.semanticDigest),
    ("observations", .arr observations.toArray),
    ("schema", .str "mirrorgate.port/v1")
  ]

private def asyncRuntimeSupport (modelName : String) : String := Shared.joinLines [
  s!"function contextError(context: ReplayContext): {modelName}BindingError | undefined " ++ "{",
  "  if (typeof context.deadline !== \"number\" || !Number.isFinite(context.deadline)) {",
  "    return bindingError(\"context_mismatch\", \"replay deadline must be a finite monotonic instant\");",
  "  }",
  "  if (context.signal.aborted) {",
  "    return bindingError(\"operation_cancelled\", \"replay operation was cancelled\", context.signal.reason);",
  "  }",
  "  if (performance.now() >= context.deadline) {",
  "    return bindingError(\"deadline_exceeded\", \"replay deadline expired\");",
  "  }",
  "  return undefined;",
  "}",
  "",
  "function ensureContextActive(context: ReplayContext): void {",
  "  const error = contextError(context);",
  "  if (error !== undefined) throw error;",
  "}",
  "",
  "function awaitPortOperation<T>(operation: PromiseLike<T>, context: ReplayContext): Promise<T> {",
  "  const before = contextError(context);",
  "  if (before !== undefined) {",
  "    void Promise.resolve(operation).catch(() => undefined);",
  "    return Promise.reject(before);",
  "  }",
  "  return new Promise<T>((resolve, reject) => {",
  "    let settled = false;",
  "    let deadlineTimer: ReturnType<typeof setTimeout> | undefined;",
  "    const finish = (callback: () => void): void => {",
  "      if (settled) return;",
  "      settled = true;",
  "      context.signal.removeEventListener(\"abort\", onAbort);",
  "      if (deadlineTimer !== undefined) clearTimeout(deadlineTimer);",
  "      callback();",
  "    };",
  "    const onAbort = (): void => finish(() => reject(",
  "      bindingError(\"operation_cancelled\", \"replay operation was cancelled\", context.signal.reason),",
  "    ));",
  "    context.signal.addEventListener(\"abort\", onAbort, { once: true });",
  "    const armDeadline = (): void => {",
  "      const remaining = context.deadline - performance.now();",
  "      if (remaining <= 0) {",
  "        finish(() => reject(bindingError(\"deadline_exceeded\", \"replay deadline expired\")));",
  "      } else {",
  "        deadlineTimer = setTimeout(armDeadline, Math.min(Math.max(1, Math.ceil(remaining)), 2_147_483_647));",
  "      }",
  "    };",
  "    armDeadline();",
  "    void Promise.resolve(operation).then(",
  "      (value) => finish(() => {",
  "        const after = contextError(context);",
  "        if (after === undefined) resolve(value); else reject(after);",
  "      }),",
  "      (error: unknown) => finish(() => reject(error)),",
  "    );",
  "  });",
  "}"
]

private def renderBinding (lock : LockedModelInterface)
    (lowered : Shared.LoweredModule) : String :=
  let modelName := lowered.modelName
  let actions := Shared.sortByKey (fun action => action.id) lowered.actions
  let actionIds := actions.map (fun action => Shared.quote action.id)
  let actionUnion := String.intercalate " | " actionIds
  let coverageFields := actions.map (fun action => s!"    {Shared.quote action.id}: 0,")
  let switchCases := actions.map renderActionCases
  let expectedParamVar := lowered.configuredParamVar.getD ""
  let publicManifest := renderPublicManifest lock
  Shared.joinLines <|
    [s!"export const {modelName}SemanticDigest = {Shared.quote lock.semanticDigest} as const;",
     s!"export const {modelName}AsyncTargetProfile = {Shared.quote targetProfile} as const;",
     s!"export const {modelName}AsyncStateComputerContractVersion = {Shared.quote stateComputerContractVersion} as const;",
     s!"export const {modelName}ModelInterface = " ++ "{",
     s!"  semanticDigest: {modelName}SemanticDigest,",
     s!"  contract: {lowered.contractJson},",
     "} as const;",
     s!"export const {modelName}PublicManifest = {publicManifest} as const;",
     "",
     s!"export type {modelName}BindingErrorCode =",
     "  | \"configuration_mismatch\"",
     "  | \"unknown_action\"",
     "  | \"transition_before_initialization\"",
     "  | \"input_shape_mismatch\"",
     "  | \"adapter_failure\"",
     "  | \"observation_shape_mismatch\"",
     "  | \"context_mismatch\"",
     "  | \"operation_cancelled\"",
     "  | \"deadline_exceeded\"",
     "  | \"reentrant_call\"",
     "  | \"binding_poisoned\";",
     "",
     s!"export class {modelName}BindingError extends Error " ++ "{",
     s!"  constructor(readonly code: {modelName}BindingErrorCode, message: string, options?: ErrorOptions) " ++ "{",
     "    super(message, options);",
     s!"    this.name = {Shared.quote (modelName ++ "BindingError")};",
     "  }",
     "}",
     "",
     s!"function bindingError(code: {modelName}BindingErrorCode, message: string, cause?: unknown): {modelName}BindingError " ++ "{",
     s!"  return new {modelName}BindingError(code, message, cause === undefined ? undefined : " ++ "{ cause });",
     "}",
     "",
     asyncRuntimeSupport modelName,
     "",
     s!"type {modelName}ActionId = {actionUnion};",
     "",
     s!"export function assert{modelName}CompatibleConfig(",
     "  config: Pick<ApalacheConfig, \"paramVars\">,",
     "): void {",
     s!"  const expectedParamVar = {Shared.quote expectedParamVar};",
     "  const actualParamVar = config.paramVars ?? \"\";",
     "  if (actualParamVar !== expectedParamVar) {",
     "    throw bindingError(",
     "      \"configuration_mismatch\",",
     "      \"expected paramVars=\" + expectedParamVar + \", got \" + actualParamVar,",
     "    );",
     "  }",
     "}",
     "",
     s!"export interface {modelName}AsyncBinding " ++ "{",
     "  readonly computer: AsyncStateComputer;",
     "  assertCompatibleConfig(config: Pick<ApalacheConfig, \"paramVars\">): void;",
     s!"  coverage(): Readonly<Record<{modelName}ActionId, number>>;",
     "  assertAllActionsCovered(): void;",
     "}",
     "",
     s!"export function bind{modelName}Async(",
     s!"  port: {modelName}AsyncPort,",
     "  config: Pick<ApalacheConfig, \"paramVars\">,",
     s!"): {modelName}AsyncBinding " ++ "{",
     s!"  assert{modelName}CompatibleConfig(config);",
     "",
     "  let lifecycle: \"fresh\" | \"initialized\" | \"poisoned\" = \"fresh\";",
     "  let busy = false;",
     s!"  const counts: Record<{modelName}ActionId, number> = " ++ "{"] ++ coverageFields ++
    ["  };",
     "  const ensureBindingActive = (): void => {",
     "    if (lifecycle === \"poisoned\") {",
     "      throw bindingError(\"binding_poisoned\", \"binding is poisoned\");",
     "    }",
     "  };",
     "",
     "  const computer: AsyncStateComputer = async ({ action, payload, previous: _previous }, context) => {",
     "    ensureBindingActive();",
     "    if (busy) {",
     "      lifecycle = \"poisoned\";",
     "      throw bindingError(\"reentrant_call\", \"binding permits one callback at a time\");",
     "    }",
     "    busy = true;",
     s!"    let actionId: {modelName}ActionId;",
     "    let stage: \"dispatch\" | \"input\" | \"adapter\" | \"observation\" = \"dispatch\";",
     "    try {",
     "      ensureContextActive(context);",
     "      switch (action) {"] ++ switchCases ++
    ["        default: throw bindingError(\"unknown_action\", \"unknown action \" + action);",
     "      }",
     "      stage = \"observation\";",
     "      ensureContextActive(context);",
     "      const observation = await awaitPortOperation(port.observe(context), context);",
     "      ensureContextActive(context);",
     "      ensureBindingActive();",
     s!"      const state = encode{modelName}Observation(observation);",
     "      ensureContextActive(context);",
     "      ensureBindingActive();",
     "      counts[actionId] += 1;",
     "      return state;",
     "    } catch (error) {",
     "      lifecycle = \"poisoned\";",
     s!"      if (error instanceof {modelName}BindingError) throw error;",
     "      const code = stage === \"input\"",
     "        ? \"input_shape_mismatch\"",
     "        : stage === \"observation\"",
     "          ? \"observation_shape_mismatch\"",
     "          : \"adapter_failure\";",
     "      throw bindingError(code, \"binding failed for action \" + action, error);",
     "    } finally {",
     "      busy = false;",
     "    }",
     "  };",
     "",
     "  return {",
     "    computer,",
     s!"    assertCompatibleConfig: assert{modelName}CompatibleConfig,",
     "    coverage: () => Object.freeze({ ...counts }),",
     "    assertAllActionsCovered: () => {",
     "      const unseen = (Object.keys(counts) as Array<keyof typeof counts>)",
     "        .filter((id) => counts[id] === 0);",
     "      if (unseen.length > 0) throw new Error(\"uncovered actions: \" + unseen.join(\", \"));",
     "    },",
     "  };",
     "}"]

private def renderPublicPortAction (action : ResolvedAction) : String :=
  let methodName := Shared.nativeName action.id
  let parameters := if action.inputs.isEmpty then "context" else "input, context"
  let assignments := Shared.sortByKey (fun input => input.id) action.inputs |>.map fun input =>
    s!"      values[{Shared.quote input.id}] = input.{Shared.nativeName input.id};"
  Shared.joinLines <|
    [s!"    {methodName}: ({parameters}) => " ++ "{"] ++
    (if action.inputs.isEmpty then
      [s!"      return publicPort.invoke({Shared.quote action.id}, Object.freeze(Object.create(null) as Record<string, unknown>), context);"]
    else
      ["      const values = Object.create(null) as Record<string, unknown>;"] ++
      assignments ++
      [s!"      return publicPort.invoke({Shared.quote action.id}, Object.freeze(values), context);"]) ++
    ["    },"]

private def renderPublicPortAdapter (lowered : Shared.LoweredModule) : EmitResult String := do
  let actionMethods := lowered.actions.map renderPublicPortAction
  let observations ← (Shared.sortByKey (fun observation => observation.id)
    lowered.observations).mapM fun observation => do
      let type ← Shared.typeName targetProfile observation.type
      pure s!"        {Shared.nativeName observation.id}: values[{Shared.quote observation.id}] as {type},"
  let observationIds := Shared.sortByKey (fun observation => observation.id)
    lowered.observations |>.map (fun observation => Shared.quote observation.id)
  pure <| Shared.joinLines <|
    ["export interface AsyncPublicPort {",
     "  invoke(operationId: string, inputs: Readonly<Record<string, unknown>>, context: ReplayContext): Promise<void>;",
     "  observe(context: ReplayContext): Promise<Readonly<Record<string, unknown>>>;",
     "}",
     "",
     s!"export function bind{lowered.modelName}AsyncPublicPort(",
     "  publicPort: AsyncPublicPort,",
     "  config: Pick<ApalacheConfig, \"paramVars\">,",
     s!"): {lowered.modelName}AsyncBinding " ++ "{",
     s!"  const port: {lowered.modelName}AsyncPort = " ++ "{"] ++
    actionMethods ++
    ["    observe: async (context) => {",
     "      const values = ownRecord(await publicPort.observe(context));",
     "      if (values === null) throw new Error(\"public observation must be a record\");",
     s!"      exactKeys(values, [{String.intercalate ", " observationIds}], {Shared.quote (lowered.modelName ++ "PublicObservation")});",
     "      return {"] ++ observations ++
    ["      };",
     "    },",
     "  };",
     s!"  return bind{lowered.modelName}Async(port, config);",
     "}"]

/-- Emit the deterministic `mirrorecma-async-v1` source and ownership tree. -/
def emitTypeScriptAsync (lock : LockedModelInterface) : EmitResult GeneratedTree := do
  let lowered ← Shared.lowerModule targetProfile lock
  let portMethods := lowered.actions.map renderPortMethod
  let port := Shared.joinLines
    ([s!"export interface {lowered.modelName}AsyncPort " ++ "{"] ++ portMethods ++
      [s!"  observe(context: ReplayContext): Promise<{lowered.modelName}Observation>;", "}"])
  let header := Shared.joinLines [
    "// @generated by Mirrors model_interface_gen",
    s!"// target-profile: {targetProfile}",
    "// profile-version: 1",
    s!"// semantic-sha256: {lock.semanticDigest}",
    "// DO NOT EDIT"
  ]
  let imports :=
    "import type { ApalacheConfig, AsyncStateComputer, ReplayContext, State, Value } from \"mirrorecma\";"
  let sourcePath := s!"{lowered.modelName}Mirror.generated.ts"
  let publicPortAdapter ← renderPublicPortAdapter lowered
  let source := Shared.finalLf <| String.intercalate "\n\n" <|
    [header, imports, Shared.runtime] ++
    lowered.inputInterfaces.filter (· != "") ++
    [lowered.observationInterface, port] ++
    lowered.inputShapes ++ lowered.observationShapes ++
    lowered.inputDecoders.filter (· != "") ++
    [lowered.observationEncoder, renderBinding lock lowered, publicPortAdapter]
  let ownedPaths := Shared.sortStrings [manifestPath, sourcePath]
  let manifest := Shared.ownershipManifest targetProfile lock.semanticDigest ownedPaths
  let files := Shared.sortByKey (fun file : GeneratedFile => file.relativePath) [
    { relativePath := sourcePath, bytes := source.toUTF8 },
    { relativePath := manifestPath, bytes := manifest.toUTF8 }
  ]
  pure { files }

end Shell.ModelInterface.Emit.TypeScriptAsync
