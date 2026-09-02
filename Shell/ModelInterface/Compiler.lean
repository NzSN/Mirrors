import Core.ModelInterface
import Core.ModelInterface.Sha256
import Codec.ModelInterfaceJson
import Codec.StrictJson
import Codec.Json
import Shell.Apalache.SpecSource
import Shell.ModelInterface.Evidence
import Shell.ModelInterface.Emit.TypeScript
import Lean

/-!
# Effectful model-interface compiler shell

This module owns file loading, canonical hashing, lock verification, target
emission, and conservative generated-file replacement. The semantic compiler
remains in `Core.ModelInterface`; this shell never invokes Apalache or a target
language compiler.
-/

namespace Shell.ModelInterface.Compiler

open Core.ModelInterface

namespace MIJson
abbrev encodeContract := Codec.ModelInterfaceJson.encodeContract
abbrev encodeLock := Codec.ModelInterfaceJson.encodeLock
abbrev canonicalBytes := Codec.ModelInterfaceJson.canonicalBytes
abbrev canonicalFileBytes := Codec.ModelInterfaceJson.canonicalFileBytes
abbrev canonicalSemanticDescriptorBytes :=
  Codec.ModelInterfaceJson.canonicalSemanticDescriptorBytes
abbrev canonicalProvenanceBytes := Codec.ModelInterfaceJson.canonicalProvenanceBytes
def parseContractBytes (raw : ByteArray)
    (limits : Codec.StrictJson.Limits := Codec.StrictJson.defaultLimits) :=
  Codec.ModelInterfaceJson.parseContractBytes raw limits
def parseLockBytes (raw : ByteArray)
    (limits : Codec.StrictJson.Limits := Codec.StrictJson.defaultLimits) :=
  Codec.ModelInterfaceJson.parseLockBytes raw limits
end MIJson

def compilerVersion : String := "model-interface-gen/1"
def contractDigestDomain : String := "mirrors-model-interface-contract/v1"
def descriptorDigestDomain : String := descriptorDigestDomainV1
def provenanceDigestDomain : String := "mirrors-model-interface-provenance/v1"
def generatedManifestPath : String := ".model-interface-generated.json"
def generatedPublicationLockPath : String := ".model-interface-generation.lock"
def mirrorecmaTarget : String := "mirrorecma-v1"
def maxModelInterfaceItfArtifactBytes : Nat := 16 * 1024 * 1024
def maxCompilerArtifactBytes : Nat := 16 * 1024 * 1024

private def compilerArtifactJsonLimits : Codec.StrictJson.Limits :=
  { Codec.StrictJson.defaultLimits with maxBytes := maxCompilerArtifactBytes }

inductive ErrorKind where
  | finding
  | infrastructure
  deriving Repr, DecidableEq

structure CompilerError where
  kind : ErrorKind
  message : String
  diagnostics : List Diagnostic := []
  deriving Repr

structure InputPaths where
  spec : String
  contract : String
  evidence : String
  paramVar : Option String := none
  deriving Repr

structure Compilation where
  resolved : ResolvedModelInterface
  lock : LockedModelInterface
  descriptorBytes : ByteArray
  provenanceBytes : ByteArray
  lockBytes : ByteArray
  diagnostics : List Diagnostic

structure CheckReport where
  stalePaths : List String
  diagnostics : List Diagnostic
  deriving Repr

def CheckReport.clean (report : CheckReport) : Bool := report.stalePaths.isEmpty

private def finding (message : String) (diagnostics : List Diagnostic := []) :
    Except CompilerError α :=
  .error { kind := .finding, message, diagnostics }

private def infrastructure (message : String) : Except CompilerError α :=
  .error { kind := .infrastructure, message }

private partial def readBoundedArtifactAux (handle : IO.FS.Handle)
    (path : String) (limit : Nat) (accumulator : ByteArray) :
    IO (Except CompilerError ByteArray) := do
  if accumulator.size > limit then
    return finding s!"artifact {path} exceeds the {limit}-byte limit"
  let remainingProbe := limit + 1 - accumulator.size
  let requestSize := min 65536 remainingProbe
  let chunk ← handle.read requestSize.toUSize
  if chunk.isEmpty then return .ok accumulator
  readBoundedArtifactAux handle path limit (accumulator.append chunk)

private def readBytesWithLimit (path : String) (limit : Nat) :
    IO (Except CompilerError ByteArray) := do
  try
    let handle ← IO.FS.Handle.mk path .read
    readBoundedArtifactAux handle path limit ByteArray.empty
  catch error =>
    return infrastructure s!"cannot read {path}: {error}"

private def readBytes (path : String) : IO (Except CompilerError ByteArray) :=
  readBytesWithLimit path maxCompilerArtifactBytes

private def readText (path : String) : IO (Except CompilerError String) := do
  let bytes ← match ← readBytes path with
    | .ok bytes => pure bytes
    | .error error => return .error error
  match String.fromUTF8? bytes with
  | some text => return .ok text
  | none => return finding s!"artifact {path} is not valid UTF-8"

private def domainDigest (domain : String) (bytes : ByteArray) : String :=
  Core.ModelInterface.Sha256.digestDomainHex domain bytes

private def windowsDriveLike (source : String) : Bool :=
  match source.toList with
  | _ :: ':' :: _ => true
  | _ => false

private def diagnosticSourceName (source fallback : String) : String :=
  if validLogicalPath source && !windowsDriveLike source then source else
    let name := ((source.replace "\\" "/").splitOn "/").getLast?.getD fallback
    if name.isEmpty || name == "." || name == ".." || windowsDriveLike name then
      fallback
    else name

private def resolveLoaded (paths : InputPaths) (sources : List SourceDigest)
    (contract : ContractV1) (evidence : ModelEvidence) :
    Except CompilerError Compilation := do
  let contractBytes := MIJson.canonicalBytes (MIJson.encodeContract contract)
  let input : ResolveInput :=
    { contract :=
        { value := contract
          location := {
            source := diagnosticSourceName contract.model.source "<contract>" } }
      evidence := evidence
      runProfile := { configuredParamVar := paths.paramVar }
      sources := sources
      compilerVersion := compilerVersion
      contractSha256 := domainDigest contractDigestDomain contractBytes }
  let result := Core.ModelInterface.resolve input
  let some resolved := result.value
    | return ← finding "model-interface resolution failed" result.diagnostics
  let descriptorBytes := MIJson.canonicalSemanticDescriptorBytes
    resolved.semanticDescriptor
  let provenanceBytes := MIJson.canonicalProvenanceBytes resolved.provenance
  let semanticDigest := domainDigest descriptorDigestDomain descriptorBytes
  let provenanceDigest := domainDigest provenanceDigestDomain provenanceBytes
  let lock := resolved.withDigests semanticDigest provenanceDigest
  let lockBytes := MIJson.canonicalFileBytes (MIJson.encodeLock lock)
  return {
    resolved := resolved
    lock := lock
    descriptorBytes := descriptorBytes
    provenanceBytes := provenanceBytes
    lockBytes := lockBytes
    diagnostics := result.diagnostics
  }

/-- Read normalized inputs, resolve the pure interface, compute both
domain-separated digests, and build canonical lock bytes entirely in memory. -/
def compile (paths : InputPaths) : IO (Except CompilerError Compilation) := do
  let contractResult ← readBytes paths.contract
  let contractRaw ← match contractResult with
    | .ok value => pure value
    | .error error => return .error error
  let evidenceResult ← readText paths.evidence
  let evidenceRaw ← match evidenceResult with
    | .ok value => pure value
    | .error error => return .error error
  let contract ← match MIJson.parseContractBytes contractRaw
      compilerArtifactJsonLimits with
    | .ok contract => pure contract
    | .error error => return finding s!"invalid companion contract: {error}"
  let evidenceName := diagnosticSourceName
    ((paths.evidence : System.FilePath).fileName.getD "<evidence>") "<evidence>"
  let evidenceLimits : Codec.StrictJson.Limits := {
    Codec.StrictJson.defaultLimits with
      maxBytes := maxModelInterfaceItfArtifactBytes }
  let evidence ← match Evidence.fromString evidenceRaw evidenceName evidenceLimits with
    | .ok evidence => pure evidence
    | .error error => return finding s!"invalid structural evidence: {error}"
  let sourceClosure ← match ←
      Shell.Apalache.SpecSource.borrowedSourceDigests paths.spec with
    | .ok sources => pure sources
    | .error error =>
        if error.startsWith "unable to read borrowed source" then
          return infrastructure error
        else
          return finding s!"invalid model source closure: {error}"
  let rootLogicalName := (paths.spec : System.FilePath).fileName.getD ""
  let rootSource ← match sourceClosure.find? (fun source =>
      source.logicalPath == rootLogicalName) with
    | some source => pure source
    | none => return finding "model source closure does not identify its root module"
  if rootSource.moduleName != contract.model.moduleName then
    return finding s!"model source declares module {rootSource.moduleName}, but contract names {contract.model.moduleName}"
  let sourceClosure := sourceClosure.map fun source =>
    if source.logicalPath == rootLogicalName then
      { source with logicalPath := contract.model.source }
    else source
  return resolveLoaded paths sourceClosure contract evidence

/-- Recompute and verify both digests carried by a decoded lock. -/
def verifyLock (lock : LockedModelInterface) : Except CompilerError Unit := do
  if !semanticDescriptorWellFormedV1 lock.semanticDescriptor then
    return ← finding "lock descriptor violates version-1 semantic invariants"
  let semantic := domainDigest descriptorDigestDomain
    (MIJson.canonicalSemanticDescriptorBytes lock.semanticDescriptor)
  if semantic != lock.semanticDigest then
    return ← finding "lock semantic digest does not match its descriptor"
  let provenance := domainDigest provenanceDigestDomain
    (MIJson.canonicalProvenanceBytes lock.provenance)
  if provenance != lock.provenanceDigest then
    return ← finding "lock provenance digest does not match its provenance"
  return ()

/-- Strictly load a checked-in lock and verify its content digests. -/
def loadVerifiedLock (path : String) : IO (Except CompilerError LockedModelInterface) := do
  let rawResult ← readBytes path
  let raw ← match rawResult with
    | .ok value => pure value
    | .error error => return .error error
  let lock ← match MIJson.parseLockBytes raw compilerArtifactJsonLimits with
    | .ok lock => pure lock
    | .error error => return finding s!"invalid model-interface lock: {error}"
  match verifyLock lock with
  | .ok () => return .ok lock
  | .error error => return .error error

/-- Emit one allowlisted target from a verified in-memory lock. -/
def emitTarget (target : String) (lock : LockedModelInterface) :
    Except CompilerError Emit.TypeScript.GeneratedTree := do
  if target != mirrorecmaTarget then
    return ← infrastructure s!"unsupported target: {target}"
  let _ ← verifyLock lock
  match Emit.TypeScript.emitTypeScript lock with
  | .ok tree => return tree
  | .error diagnostics =>
      let message := String.intercalate "; "
        (diagnostics.map fun diagnostic => s!"{diagnostic.code}: {diagnostic.message}")
      return ← finding s!"target emission failed: {message}"

/-! ## Conservative filesystem ownership -/

private def joinPath (root relative : String) : String :=
  if root.endsWith "/" then root ++ relative else root ++ "/" ++ relative

private def safeRelativeComponent (segment : String) : Bool :=
  !segment.isEmpty && segment != "." && segment != ".." &&
    !segment.contains ':' &&
    !(segment.endsWith ".") && !(segment.endsWith " ")

def safeRelativePath (path : String) : Bool :=
  !path.isEmpty && !path.startsWith "/" && !path.startsWith "\\" &&
    !path.contains '\\' &&
    (path.splitOn "/").all safeRelativeComponent

private def trimWindowsAliasSuffix (segment : String) : String :=
  String.ofList <| (segment.toList.reverse.dropWhile fun character =>
    character == '.' || character == ' ').reverse

private def portablePathAliasKey (path : String) : String :=
  (String.intercalate "/" <|
    (path.splitOn "/").map trimWindowsAliasSuffix).toLower

private def publicationLockAlias (path : String) : Bool :=
  portablePathAliasKey path == portablePathAliasKey generatedPublicationLockPath

private def ordinaryPathComponent (segment : String) : Bool :=
  !segment.isEmpty && segment != "." && segment != ".."

private def windowsDriveComponent (segment : String) : Bool :=
  match segment.toList with
  | [letter, ':'] =>
      ('A'.toNat ≤ letter.toNat && letter.toNat ≤ 'Z'.toNat) ||
        ('a'.toNat ≤ letter.toNat && letter.toNat ≤ 'z'.toNat)
  | _ => false

private def safePathComponents (windows absolute : Bool)
    (components : List String) : Bool :=
  if components.isEmpty then false
  else if absolute then
    match components with
    | "" :: rest => !rest.isEmpty && rest.all ordinaryPathComponent
    | drive :: rest => windows && windowsDriveComponent drive &&
        !rest.isEmpty && rest.all ordinaryPathComponent
    | [] => false
  else
    components.all ordinaryPathComponent

private example : safePathComponents true true ["C:", "generated"] = true := by
  native_decide

private example : safePathComponents true true ["C:", "..", "generated"] = false := by
  native_decide

private example : safePathComponents true true ["C:generated"] = false := by
  native_decide

private example : safePathComponents true true ["C:", ""] = false := by
  native_decide

private example : safePathComponents false true [""] = false := by
  native_decide

private def safePathSpelling (path : String) : Bool :=
  if path.isEmpty || path.contains '\u0000' then false else
    let filePath : System.FilePath := path
    safePathComponents System.Platform.isWindows filePath.isAbsolute filePath.components

private def absoluteLexicalPath (path : String) : IO (Except CompilerError System.FilePath) := do
  if !safePathSpelling path then
    return finding s!"unsafe or non-canonical path spelling: {path}"
  let filePath : System.FilePath := path
  let absolute ← if filePath.isAbsolute then pure filePath else
    pure ((← IO.currentDir) / filePath)
  let absolute := absolute.normalize
  if absolute.parent.isNone then
    return finding s!"filesystem root is not an allowed target: {path}"
  return .ok absolute

private partial def pathChain (path : System.FilePath) : List System.FilePath :=
  match path.parent with
  | none => [path]
  | some parent => pathChain parent ++ [path]

private def lstat? (path : System.FilePath) :
    BaseIO (Except IO.Error (Option IO.FS.Metadata)) := do
  match ← path.symlinkMetadata.toBaseIO with
  | .ok metadata => return .ok (some metadata)
  | .error (.noFileOrDirectory ..) => return .ok none
  | .error error => return .error error

/-- Check every existing prefix with lstat before any realpath or content
operation. The first missing component ends the walk, so no descendant of an
attacker-controlled symlink is followed. -/
private def inspectNoSymlinks (path : System.FilePath)
    (finalType : Option IO.FS.FileType := none) :
    IO (Except CompilerError Bool) := do
  let chain := pathChain path
  let mut index := 0
  for component in chain do
    match ← lstat? component with
    | .error error =>
        return infrastructure s!"cannot inspect path {component}: {error}"
    | .ok none => return .ok false
    | .ok (some metadata) =>
        if metadata.type == .symlink then
          return finding s!"symbolic links are forbidden in generated paths: {component}"
        let isFinal := index + 1 == chain.length
        if !isFinal && metadata.type != .dir then
          return finding s!"non-directory path component: {component}"
        if isFinal then
          match finalType with
          | some expected =>
              if metadata.type != expected then
                return finding s!"unexpected filesystem object at {component}"
          | none => pure ()
    index := index + 1
  return .ok true

private def ensureDirectoryChain (directory : System.FilePath) :
    IO (Except CompilerError Unit) := do
  for component in pathChain directory do
    match ← lstat? component with
    | .error error =>
        return infrastructure s!"cannot inspect directory {component}: {error}"
    | .ok (some metadata) =>
        if metadata.type == .symlink then
          return finding s!"symbolic links are forbidden in output roots: {component}"
        if metadata.type != .dir then
          return finding s!"output path component is not a directory: {component}"
    | .ok none =>
        try IO.FS.createDir component
        catch error =>
          match ← lstat? component with
          | .ok (some metadata) =>
              if metadata.type == .symlink || metadata.type != .dir then
                return finding s!"unsafe concurrently-created output component: {component}"
          | _ => return infrastructure s!"cannot create output directory {component}: {error}"
  return .ok ()

private def canonicalOutputRoot (path : String) (create : Bool) :
    IO (Except CompilerError String) := do
  let absoluteResult ← absoluteLexicalPath path
  let absolute ← match absoluteResult with
    | .ok value => pure value
    | .error error => return .error error
  if create then
    match ← ensureDirectoryChain absolute with
    | .error error => return .error error
    | .ok () => pure ()
  let rootExists ← match ← inspectNoSymlinks absolute (some .dir) with
    | .error error => return .error error
    | .ok value => pure value
  if create && !rootExists then
    return infrastructure s!"output root disappeared during validation: {absolute}"
  -- Only call realPath after every existing component has passed lstat.
  if rootExists then
    let realResult : Except CompilerError System.FilePath ← try
      pure (.ok (← IO.FS.realPath absolute))
    catch error =>
      pure (infrastructure s!"cannot canonicalize output root {absolute}: {error}")
    let real ← match realResult with
      | .ok value => pure value
      | .error error => return .error error
    if real.normalize.toString != absolute.normalize.toString then
      return finding s!"output root is an alias or traverses a link: {path}"
    if real.parent.isNone then
      return finding s!"filesystem root is not an allowed output root: {path}"
  return .ok (absolute.toString)

private def containedTarget (root relative : String) : Except CompilerError String := do
  if !safeRelativePath relative then
    return ← finding s!"unsafe generated relative path: {relative}"
  let target := joinPath root relative
  let rootPrefix := if root.endsWith "/" then root else root ++ "/"
  if !target.startsWith rootPrefix then
    return ← finding s!"generated path escapes output root: {relative}"
  return target

private def prepareContainedTarget (root relative : String) (createParents : Bool) :
    IO (Except CompilerError (String × Bool)) := do
  let target ← match containedTarget root relative with
    | .ok value => pure value
    | .error error => return .error error
  let some parent := (target : System.FilePath).parent
    | return finding s!"generated target has no parent: {target}"
  if createParents then
    match ← ensureDirectoryChain parent with
    | .error error => return .error error
    | .ok () => pure ()
  else
    match ← inspectNoSymlinks parent (some .dir) with
    | .error error => return .error error
    | .ok _ => pure ()
  match ← inspectNoSymlinks target (some .file) with
  | .error error => return .error error
  | .ok targetExists => return .ok (target, targetExists)

private def prepareStandaloneTarget (path : String) (createParent : Bool) :
    IO (Except CompilerError (String × Bool)) := do
  let absoluteResult ← absoluteLexicalPath path
  let absolute ← match absoluteResult with
    | .ok value => pure value
    | .error error => return .error error
  let some parent := absolute.parent
    | return finding s!"target has no parent: {path}"
  if createParent then
    match ← ensureDirectoryChain parent with
    | .error error => return .error error
    | .ok () => pure ()
  else
    match ← inspectNoSymlinks parent (some .dir) with
    | .error error => return .error error
    | .ok _ => pure ()
  match ← inspectNoSymlinks absolute (some .file) with
  | .error error => return .error error
  | .ok targetExists => return .ok (absolute.toString, targetExists)

private def bestEffortRemove (path : String) : IO Unit := do
  try
    match ← lstat? path with
    | .ok (some metadata) =>
        if metadata.type != .dir then IO.FS.removeFile path
    | _ => pure ()
  catch _ => pure ()

private def removeIfExists (path : String) : IO Unit := do
  match ← lstat? path with
  | .ok none => pure ()
  | .ok (some metadata) =>
      if metadata.type == .file then IO.FS.removeFile path
      else throw (IO.userError s!"refusing to remove non-file target {path}")
  | .error error => throw error

private def tempSibling (path : String) (ordinal : Nat := 0) : IO String := do
  let nonce ← IO.monoNanosNow
  return s!"{path}.model-interface-tmp-{nonce}-{ordinal}"

private def writeNewBytes (path : String) (bytes : ByteArray) : IO Unit := do
  let handle ← IO.FS.Handle.mk path .writeNew
  handle.write bytes
  handle.flush

private def replaceStaged (temporary target : String) (mayRemoveTarget : Bool) : IO Unit := do
  if !mayRemoveTarget then
    -- A same-directory hard link atomically publishes the fully-flushed
    -- staged inode and fails with EEXIST instead of replacing a concurrent
    -- target. A crash can leave an extra temp link, never a partial final file.
    IO.FS.hardLink temporary target
    IO.FS.removeFile temporary
  else
    try
      IO.FS.rename temporary target
    catch firstError =>
      match ← lstat? target with
      | .ok (some metadata) =>
          if metadata.type != .file then throw firstError
          -- Windows cannot atomically replace an existing file with `rename`.
          -- Move the known regular target aside first, and restore it if the
          -- second rename fails; never discard the last good artifact.
          let backup ← tempSibling target 1000000
          IO.FS.rename target backup
          try
            IO.FS.rename temporary target
            bestEffortRemove backup
          catch publishError =>
            try
              IO.FS.rename backup target
            catch restoreError =>
              throw (IO.userError
                s!"publication failed ({publishError}); prior artifact remains at {backup} because restoration failed ({restoreError})")
            throw publishError
      | _ => throw firstError

private def atomicWrite (path : String) (bytes : ByteArray)
    (mayReplace : Bool) : IO (Except CompilerError Unit) := do
  let prepared ← prepareStandaloneTarget path true
  let (target, targetExists) ← match prepared with
    | .ok value => pure value
    | .error error => return .error error
  if targetExists && !mayReplace then
    return finding s!"refusing to replace concurrently-created target: {target}"
  let temporary ← tempSibling target
  try
    writeNewBytes temporary bytes
    replaceStaged temporary target mayReplace
    return .ok ()
  catch error =>
    bestEffortRemove temporary
    return infrastructure s!"cannot safely publish {target}: {error}"

/-- Write a resolved lock. Existing unequal content is replaceable only when
it is itself a strict, digest-valid model-interface lock. -/
def writeLock (path : String) (compilation : Compilation) :
    IO (Except CompilerError Unit) := do
  let prepared ← prepareStandaloneTarget path true
  let (target, targetExists) ← match prepared with
    | .ok value => pure value
    | .error error => return .error error
  if !targetExists then
    return ← atomicWrite target compilation.lockBytes false
  let existingResult ← readBytes target
  let existing ← match existingResult with
    | .ok value => pure value
    | .error error => return .error error
  if existing == compilation.lockBytes then return .ok ()
  let old ← match MIJson.parseLockBytes existing compilerArtifactJsonLimits with
    | .ok lock => pure lock
    | .error error =>
        return finding s!"refusing to replace non-lock artifact at {target}: {error}"
  match verifyLock old with
  | .error error => return .error error
  | .ok () => return ← atomicWrite target compilation.lockBytes true

private structure OwnershipManifest where
  files : List String
  semanticDigest : String
  deriving Repr

private def jsonFields : Lean.Json → Except String (List (String × Lean.Json))
  | .obj fields => .ok fields.toList
  | _ => .error "generated ownership manifest must be an object"

private def requiredJson (fields : List (String × Lean.Json)) (name : String) :
    Except String Lean.Json :=
  match List.lookup name fields with
  | some value => .ok value
  | none => .error s!"generated ownership manifest is missing {name}"

private def jsonString (context : String) : Lean.Json → Except String String
  | .str value => .ok value
  | _ => .error s!"{context}: expected string"

private def jsonNat (context : String) : Lean.Json → Except String Nat
  | .num ⟨mantissa, 0⟩ =>
      if 0 ≤ mantissa then .ok mantissa.toNat
      else .error s!"{context}: expected nonnegative integer"
  | _ => .error s!"{context}: expected nonnegative integer"

private def jsonStrings (context : String) : Lean.Json → Except String (List String)
  | .arr values => values.toList.mapM (jsonString (context ++ "[]"))
  | _ => .error s!"{context}: expected string array"

private def lowerHex (c : Char) : Bool :=
  ('0'.toNat ≤ c.toNat && c.toNat ≤ '9'.toNat) ||
    ('a'.toNat ≤ c.toNat && c.toNat ≤ 'f'.toNat)

private def parseOwnershipManifest (raw : ByteArray) : Except String OwnershipManifest := do
  let json ← (Codec.StrictJson.parseBytes raw).mapError toString
  let fields ← jsonFields json
  let allowed := ["files", "profileVersion", "schema", "semanticDigest", "targetProfile"]
  match fields.find? (fun field => !allowed.contains field.1) with
  | some field => throw s!"unknown generated manifest field: {field.1}"
  | none => pure ()
  if fields.length != allowed.length then
    throw "generated manifest must contain exactly the version-1 fields"
  let schema ← jsonString "manifest.schema" (← requiredJson fields "schema")
  if schema != "mirrors.model-interface-generated/v1" then
    throw "unsupported generated ownership manifest schema"
  let target ← jsonString "manifest.targetProfile" (← requiredJson fields "targetProfile")
  if target != mirrorecmaTarget then throw "ownership manifest target is not mirrorecma-v1"
  let version ← jsonNat "manifest.profileVersion" (← requiredJson fields "profileVersion")
  if version != 1 then throw "unsupported generated ownership profile version"
  let digest ← jsonString "manifest.semanticDigest" (← requiredJson fields "semanticDigest")
  if digest.length != 64 || !digest.toList.all lowerHex then
    throw "generated ownership manifest has a malformed semantic digest"
  let files ← jsonStrings "manifest.files" (← requiredJson fields "files")
  if !(duplicateStrings (files.map portablePathAliasKey)).isEmpty then
    throw "generated ownership manifest contains duplicate or aliased paths"
  if !files.all safeRelativePath then throw "generated ownership manifest contains an unsafe path"
  if files.any publicationLockAlias then
    throw "generated ownership manifest may not own the publication lock"
  if !files.contains generatedManifestPath then
    throw "generated ownership manifest does not own itself"
  return { files, semanticDigest := digest }

private def readOwnershipManifest (out : String) :
    IO (Except CompilerError (Option OwnershipManifest)) := do
  let prepared ← prepareContainedTarget out generatedManifestPath false
  let (path, targetExists) ← match prepared with
    | .ok value => pure value
    | .error error => return .error error
  if !targetExists then return .ok none
  let rawResult ← readBytes path
  let raw ← match rawResult with
    | .ok value => pure value
    | .error error => return .error error
  match parseOwnershipManifest raw with
  | .ok manifest => return .ok (some manifest)
  | .error error =>
      return finding s!"refusing generated output with invalid ownership manifest: {error}"

private structure StagedFile where
  relativePath : String
  targetPath : String
  temporaryPath : String
  mayReplace : Bool

private structure BackupFile where
  relativePath : String
  targetPath : String
  backupPath : String

private def validateTree (tree : Emit.TypeScript.GeneratedTree) : Except CompilerError Unit := do
  let paths := tree.files.map (·.relativePath)
  if !(duplicateStrings (paths.map portablePathAliasKey)).isEmpty then
    return ← finding "emitter returned duplicate or aliased generated paths"
  if !paths.all safeRelativePath then return ← finding "emitter returned an unsafe generated path"
  if tree.files.any (·.executable) then
    return ← finding "version 1 refuses executable generated files"
  if paths.any publicationLockAlias then
    return ← finding "emitter may not own the generated publication lock"
  if !paths.contains generatedManifestPath then
    return ← finding "emitter output does not include its ownership manifest"
  return ()

/-- Replace only files owned by a previous strict manifest, create genuinely
new paths only when absent, remove only stale manifest-owned files, and publish
the new manifest last. -/
private def writeGeneratedTreeUnlocked (out : String)
    (tree : Emit.TypeScript.GeneratedTree) :
    IO (Except CompilerError (List String)) := do
  match validateTree tree with
  | .error error => return .error error
  | .ok () => pure ()
  let rootResult ← canonicalOutputRoot out true
  let root ← match rootResult with
    | .ok value => pure value
    | .error error => return .error error
  let previousResult ← readOwnershipManifest root
  let previous ← match previousResult with
    | .ok value => pure value
    | .error error => return .error error
  let previouslyOwned := previous.map (·.files) |>.getD []
  let newPaths := tree.files.map (·.relativePath)
  match previouslyOwned.find? fun oldPath =>
      newPaths.any (fun newPath => oldPath != newPath &&
        portablePathAliasKey oldPath == portablePathAliasKey newPath) with
  | some path =>
      return finding s!"refusing cross-generation path alias rename: {path}"
  | none => pure ()
  for file in tree.files do
    let prepared ← prepareContainedTarget root file.relativePath true
    let (target, targetExists) ← match prepared with
      | .ok value => pure value
      | .error error => return .error error
    if targetExists && !previouslyOwned.contains file.relativePath then
      return finding s!"refusing to replace unowned generated path: {target}"
  let stagedPaths ← IO.mkRef ([] : List String)
  let backupFiles ← IO.mkRef ([] : List BackupFile)
  try
    let mut staged : List StagedFile := []
    let mut ordinal := 0
    for file in tree.files do
      let target ← match containedTarget root file.relativePath with
        | .ok value => pure value
        | .error error => throw (IO.userError error.message)
      let temporary ← tempSibling target ordinal
      writeNewBytes temporary file.bytes
      stagedPaths.modify (fun paths => temporary :: paths)
      let stagedFile : StagedFile := {
        relativePath := file.relativePath
        targetPath := target
        temporaryPath := temporary
        mayReplace := previouslyOwned.contains file.relativePath
      }
      staged := staged ++ [stagedFile]
      ordinal := ordinal + 1
    -- Retain same-directory hard-link backups for every previously owned
    -- regular file before changing any final pathname. This makes ordinary
    -- caught publication failures rollback-safe without copying file bytes.
    let mut backupOrdinal := 0
    for relative in previouslyOwned do
      let prepared ← prepareContainedTarget root relative false
      let (target, targetExists) ← match prepared with
        | .ok value => pure value
        | .error error => throw (IO.userError error.message)
      if targetExists then
        let backup ← tempSibling target (2000000 + backupOrdinal)
        IO.FS.hardLink target backup
        backupFiles.modify (fun files =>
          ({ relativePath := relative, targetPath := target,
             backupPath := backup } : BackupFile) :: files)
        backupOrdinal := backupOrdinal + 1
    let nonManifest := staged.filter (fun file => file.relativePath != generatedManifestPath)
    let manifest := staged.find? (fun file => file.relativePath == generatedManifestPath)
    for file in nonManifest do
      let prepared ← prepareContainedTarget root file.relativePath true
      let (_, targetExists) ← match prepared with
        | .ok value => pure value
        | .error error => throw (IO.userError error.message)
      if targetExists && !file.mayReplace then
        throw (IO.userError s!"concurrently-created unowned target: {file.targetPath}")
      replaceStaged file.temporaryPath file.targetPath file.mayReplace
    let stale := previouslyOwned.filter (fun path => !newPaths.contains path &&
      path != generatedManifestPath && !publicationLockAlias path)
    for relative in stale do
      let prepared ← prepareContainedTarget root relative false
      let (target, targetExists) ← match prepared with
        | .ok value => pure value
        | .error error => throw (IO.userError error.message)
      if targetExists then removeIfExists target
    match manifest with
    | some file =>
        let prepared ← prepareContainedTarget root file.relativePath true
        let (_, targetExists) ← match prepared with
          | .ok value => pure value
          | .error error => throw (IO.userError error.message)
        if targetExists && !file.mayReplace then
          throw (IO.userError s!"concurrently-created unowned target: {file.targetPath}")
        replaceStaged file.temporaryPath file.targetPath file.mayReplace
    | none => throw (IO.userError "staged tree lost its ownership manifest")
    for backup in (← backupFiles.get) do bestEffortRemove backup.backupPath
    return .ok newPaths
  catch error =>
    for path in (← stagedPaths.get) do bestEffortRemove path
    -- Remove only newly-created files whose bytes still equal this invocation's
    -- staged output. Cooperative generators are serialized by the wrapper
    -- below; the byte check avoids deleting a concurrently substituted file.
    for file in tree.files do
      if !previouslyOwned.contains file.relativePath then
        match ← prepareContainedTarget root file.relativePath false with
        | .ok (target, true) =>
            match ← readBytes target with
            | .ok actual => if actual == file.bytes then bestEffortRemove target
            | .error _ => pure ()
        | _ => pure ()
    -- Restore every previous owned path, including stale files removed before
    -- a later failure. A failed restoration deliberately retains its backup
    -- sibling for manual recovery instead of discarding the last good inode.
    for backup in (← backupFiles.get) do
      try
        match ← prepareContainedTarget root backup.relativePath true with
        | .ok (_, targetExists) =>
            replaceStaged backup.backupPath backup.targetPath targetExists
        | .error _ => pure ()
      catch _ => pure ()
    return infrastructure s!"cannot publish generated tree: {error}"

/-- Serialize cooperative generators for one output root, then publish with
rollback protection. The lock is created with `writeNew`, so a concurrent
process fails before reading ownership or changing any generated path. A
process crash may leave the lock behind; that fail-closed marker must be
removed only after an operator verifies that no generator is active. -/
def writeGeneratedTree (out : String) (tree : Emit.TypeScript.GeneratedTree) :
    IO (Except CompilerError (List String)) := do
  let rootResult ← canonicalOutputRoot out true
  let root ← match rootResult with
    | .ok value => pure value
    | .error error => return .error error
  let prepared ← prepareContainedTarget root generatedPublicationLockPath true
  let (lockPath, lockExists) ← match prepared with
    | .ok value => pure value
    | .error error => return .error error
  if lockExists then
    return finding s!"generated output is locked by another publication: {lockPath}"
  let acquired ← IO.mkRef false
  try
    writeNewBytes lockPath "mirrors-model-interface-generation/v1\n".toUTF8
    acquired.set true
    let result ← writeGeneratedTreeUnlocked root tree
    bestEffortRemove lockPath
    return result
  catch error =>
    if ← acquired.get then bestEffortRemove lockPath
    return infrastructure s!"cannot acquire generated publication lock: {error}"

/-- Load and verify a lock, emit the selected target, and safely publish the
owned generated tree. -/
def generate (lockPath target out : String) :
    IO (Except CompilerError (List String)) := do
  let lockResult ← loadVerifiedLock lockPath
  let lock ← match lockResult with
    | .ok value => pure value
    | .error error => return .error error
  let tree ← match emitTarget target lock with
    | .ok tree => pure tree
    | .error error => return .error error
  writeGeneratedTree out tree

private def compareFile (path : String) (expected : ByteArray) : IO (Except CompilerError Bool) := do
  let prepared ← prepareStandaloneTarget path false
  let (target, targetExists) ← match prepared with
    | .ok value => pure value
    | .error error => return .error error
  if !targetExists then return .ok false
  let actualResult ← readBytes target
  let actual ← match actualResult with
    | .ok value => pure value
    | .error error => return .error error
  return .ok (actual == expected)

private def compareContainedFile (root relative : String) (expected : ByteArray) :
    IO (Except CompilerError Bool) := do
  let prepared ← prepareContainedTarget root relative false
  let (target, targetExists) ← match prepared with
    | .ok value => pure value
    | .error error => return .error error
  if !targetExists then return .ok false
  let actualResult ← readBytes target
  let actual ← match actualResult with
    | .ok value => pure value
    | .error error => return .error error
  return .ok (actual == expected)

/-- Resolve and emit entirely in memory, then byte-compare the lock and every
owned target file. This function performs no filesystem writes or repairs. -/
def check (paths : InputPaths) (lockPath target out : String) :
    IO (Except CompilerError CheckReport) := do
  let compilationResult ← compile paths
  let compilation ← match compilationResult with
    | .ok value => pure value
    | .error error => return .error error
  let tree ← match emitTarget target compilation.lock with
    | .ok tree => pure tree
    | .error error => return .error error
  let mut stale : List String := []
  let lockMatches ← compareFile lockPath compilation.lockBytes
  match lockMatches with
  | .error error => return .error error
  | .ok false => stale := stale ++ [lockPath]
  | .ok true => pure ()
  let rootResult ← canonicalOutputRoot out false
  let root ← match rootResult with
    | .ok value => pure value
    | .error error => return .error error
  for file in tree.files do
    let path := joinPath root file.relativePath
    let same ← compareContainedFile root file.relativePath file.bytes
    match same with
    | .error error => return .error error
    | .ok false => stale := stale ++ [path]
    | .ok true => pure ()
  return .ok { stalePaths := stale, diagnostics := compilation.diagnostics }

/-! ## Read-only trace preflight -/

/-- Maximum accepted size of one preflight ITF artifact. The file handle reader
requests one additional byte so oversize input is rejected before an unbounded
string or JSON allocation. -/
def maxPreflightTraceArtifactBytes : Nat := maxModelInterfaceItfArtifactBytes

private def preflightTraceJsonLimits : Codec.StrictJson.Limits :=
  { Codec.StrictJson.defaultLimits with maxBytes := maxPreflightTraceArtifactBytes }

private partial def readBoundedTraceBytesAux (handle : IO.FS.Handle)
    (accumulator : ByteArray) : IO (Except CompilerError ByteArray) := do
  if accumulator.size > maxPreflightTraceArtifactBytes then
    return finding
      s!"artifact exceeds the {maxPreflightTraceArtifactBytes}-byte limit"
  let remainingProbe := maxPreflightTraceArtifactBytes + 1 - accumulator.size
  let requestSize := min 65536 remainingProbe
  let chunk ← handle.read (USize.ofNat requestSize)
  if chunk.isEmpty then return .ok accumulator
  readBoundedTraceBytesAux handle (accumulator.append chunk)

private def readBoundedTraceBytes (path : String) :
    IO (Except CompilerError ByteArray) := do
  try
    let handle ← IO.FS.Handle.mk path .read
    let result ← readBoundedTraceBytesAux handle ByteArray.empty
    match result with
    | .ok bytes => return .ok bytes
    | .error error =>
        return .error { error with message := s!"trace {path}: {error.message}" }
  catch error =>
    return infrastructure s!"cannot read {path}: {error}"

structure PreflightExecution where
  lock : LockedModelInterface
  result : PreflightResult
  coverageJson : String
  deriving Repr

private def traceStrings (context : String) : Lean.Json → Except String (List String)
  | .arr values => values.toList.mapM fun
      | .str value => pure value
      | _ => throw s!"{context}: expected string array"
  | _ => .error s!"{context}: expected string array"

private def optionalTraceStrings (json : Lean.Json) (name : String) :
    Except String (List String) :=
  match json.getObjVal? name with
  | .error _ => .ok []
  | .ok value => traceStrings name value

private def traceEntries (context : String) : Lean.Json →
    Except String (List (String × Lean.Json))
  | .obj fields => .ok fields.toList
  | _ => .error s!"{context}: expected object"

private def decodeTraceStateMap (entries : List (String × Lean.Json)) :
    Except String ValueMap :=
  entries.mapM fun (name, json) => do
    let value ← (Codec.decodeValue json).mapError (fun error => error.msg)
    return (name, value)

private def parseStrictTraceJson (json : Lean.Json) : Except String ItfTrace := do
  let vars ← traceStrings "vars" (← json.getObjVal? "vars")
  let paramVars ← optionalTraceStrings json "param_vars"
  let constants ← optionalTraceStrings json "params"
  let statesJson ← json.getObjVal? "states"
  let rawStates ← match statesJson with
    | .arr values => pure values.toList
    | _ => throw "states: expected array"
  let states ← rawStates.mapM fun stateJson => do
    let entries ← traceEntries "state" stateJson
    let names := entries.map Prod.fst
    let actionTaken ← match entries.lookup actionVariableV1 with
      | some (.str action) =>
          if action.isEmpty then throw "action_taken must not be empty" else pure action
      | _ => throw "action_taken must be a nonempty string"
    match names.find? (fun name =>
        !vars.contains name && !constants.contains name && !name.startsWith "#") with
    | some name => throw s!"undeclared state key: {name}"
    | none => pure ()
    let values ← decodeTraceStateMap entries
    let parameters := values.filter (fun (name, _) => paramVars.contains name)
    let stateVars := values.filter (fun (name, _) =>
      vars.contains name && name != actionVariableV1 && !paramVars.contains name)
    return ({ actionTaken, parameters, stateVars } : TraceState)
  let traceParams ← match rawStates with
    | first :: _ =>
        let entries ← traceEntries "state[0]" first
        let values ← decodeTraceStateMap entries
        pure (values.filter (fun (name, _) => constants.contains name))
    | [] => pure []
  return { traceVars := vars, paramVars, traceParams, traceStates := states }

private def expandTracePath (path : String) : IO (Except CompilerError (List String)) := do
  try
    if ← (path : System.FilePath).isDir then
      let entries ← (path : System.FilePath).readDir
      let paths := (entries.toList.map (fun entry => entry.path.toString) |>
        List.filter (·.endsWith ".itf.json")).mergeSort (· ≤ ·)
      return .ok paths
    else
      return .ok [path]
  catch error =>
    return infrastructure s!"cannot inspect trace path {path}: {error}"

private def readStrictTrace (path : String) :
    IO (Except CompilerError (ItfTrace × ModelEvidence)) := do
  let rawResult ← readBoundedTraceBytes path
  let raw ← match rawResult with
    | .ok value => pure value
    | .error error => return .error error
  let json ← match Codec.StrictJson.parseBytes raw preflightTraceJsonLimits with
    | .ok value => pure value
    | .error error => return finding s!"invalid trace {path}: {error}"
  let trace ← match parseStrictTraceJson json with
    | .ok trace => pure trace
    | .error error => return finding s!"invalid trace {path}: {error}"
  let evidence ← match Evidence.fromJson json path with
    | .ok evidence => pure evidence
    | .error error =>
        return finding s!"invalid structural metadata in trace {path}: {error}"
  return .ok (trace, evidence)

private def readStrictTraces (path : String) :
    IO (Except CompilerError (List (ItfTrace × ModelEvidence))) := do
  let pathsResult ← expandTracePath path
  let paths ← match pathsResult with
    | .ok value => pure value
    | .error error => return .error error
  let mut traces := []
  for tracePath in paths do
    match ← readStrictTrace tracePath with
    | .ok trace => traces := traces ++ [trace]
    | .error error => return .error error
  return .ok traces

def encodeCoverageReport (lock : LockedModelInterface) (coverage : CoverageReport) :
    Lean.Json :=
  let actions := coverage.actions.mergeSort fun left right => left.id ≤ right.id
  let unseen := coverage.unseenActions.mergeSort (· ≤ ·)
  Lean.Json.mkObj [
    ("actions", .arr (actions.map (fun action => Lean.Json.mkObj [
      ("count", .num action.count), ("id", .str action.id)])).toArray),
    ("schema", .str "mirrors.model-interface-coverage/v1"),
    ("semanticDigest", .str lock.semanticDigest),
    ("states", .num coverage.states),
    ("traces", .num coverage.traces),
    ("unseenActions", .arr (unseen.map Lean.Json.str).toArray)
  ]

/-- Strictly load and verify a lock and trace path, apply the lock's configured
parameter repartition exactly once, then run the pure preflight. No writes. -/
def runPreflight (lockPath tracePath : String) (requireAllActions : Bool := false) :
    IO (Except CompilerError PreflightExecution) := do
  let lockResult ← loadVerifiedLock lockPath
  let lock ← match lockResult with
    | .ok value => pure value
    | .error error => return .error error
  let tracesResult ← readStrictTraces tracePath
  let loaded ← match tracesResult with
    | .ok value => pure value
    | .error error => return .error error
  match loaded.find? (fun item =>
      item.2.evidenceSha256 != lock.provenance.evidenceSha256) with
  | some _ =>
      return finding "trace structural evidence does not match the verified lock"
  | none => pure ()
  let traces := loaded.map Prod.fst
  let configured := lock.runProfile.configuredParamVar.toList
  let traces := traces.map (applyParamVars configured)
  let result := Core.ModelInterface.preflight lock traces { requireAllActions }
  let coverageJson := Codec.ModelInterfaceJson.canonicalString
    (encodeCoverageReport lock result.coverage)
  return .ok { lock, result, coverageJson }

end Shell.ModelInterface.Compiler
