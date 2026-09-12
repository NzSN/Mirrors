import Codec.Json
import Core.Value
import Core.ModelInterface.Types
import Shell.Tla.Frontend
import Lean

/-!
# Shell.Apalache.SpecSource — spec materialization (Layer 3, design 5.4)

Port of the Haskell @Apalache.SpecSource@: inline spec sources are
materialized as @.tla@ files in a mirror-owned temp directory (released
by deleting the dir); a @Borrowed@ spec uses the config's own
@specPath@ as-is and is never deleted. Negotiated trace generation can
instead take a mirror-owned snapshot of a borrowed source closure so
provenance and execution share one capture. Also provides the per-session temp
dir (apalache's run dir / cwd).

Divergence from Haskell, documented: there is no @Resource@ registry in
the Lean shell; ownership is carried by @SpecRes.provenance@ plus the
total @releaseSpec@ action, and callers that need cancellation
wiring register it themselves (e.g. via @Shell.Jobs.CancelToken.onCancel@).

Source interpretation is not duplicated here. This module captures borrowed
and inline sources through `Shell.Tla.SourceProvider`, discovers the declared
module name and the `EXTENDS`/`INSTANCE` dependency declarations with
`Core.Tla.parseSource`, and hashes the captured normalized text. The local
token scanner this module used to carry is retired; only closure policy
(budgets, cycle termination, snapshot materialization) stays here, because
this module owns the temporary-directory lifecycle.
-/

namespace Shell.Apalache.SpecSource

/-! ## Frontend capture seam -/

/-- Parse one captured unit with the shared frontend parser. The declared module
name and the dependency declarations used below both come from this one parse;
no second lexical scanner interprets TLA+ source. A source the parser cannot
turn into a module is refused; the parser's first diagnostic is carried along so
a capture failure stays diagnosable. -/
private def parseCaptured (unit : Core.Tla.SourceUnit) :
    Except String Core.Tla.ParsedModule :=
  let outcome := Core.Tla.parseSource Core.Tla.LanguageProfile.default
    Core.Tla.ParserProfile.default {} {} unit
  if outcome.hasErrors then
    .error (match outcome.diagnostics.toList.head? with
      | some diagnostic =>
          s!"no MODULE header found in spec source: {diagnostic.message}"
      | none => "no MODULE header found in spec source")
  else
    match outcome.module? with
    | some parsed => .ok parsed
    | none => .error "no MODULE header found in spec source"

/-- The declared module name of a source, with the logical path used only for
the capture identity. The module-name spelling is revalidated here because the
name also becomes a logical file name in a mirror-owned directory. -/
private def declaredModuleName (logicalPath source : String) :
    Except String Core.Tla.ModuleName := do
  let unit := Core.Tla.SourceUnit.create .inlineSourceMap logicalPath source
  let parsed ← parseCaptured unit
  if !Core.Tla.ModuleName.valid parsed.name.name then
    throw s!"malformed MODULE header: '{parsed.name.name}' is not a module name"
  return parsed.name

/-- Parse the module name from a spec source: the declared @MODULE@ header name,
read through the frontend's parser. A source without a usable module reports the
historical message this entry point always used. -/
def moduleName (src : String) : Except String String :=
  match declaredModuleName "spec.tla" src with
  | .ok name => .ok name.name
  | .error _ => .error "no MODULE header found in spec source"

private def sourceDigest (moduleName logicalPath source : String) :
    Core.ModelInterface.SourceDigest :=
  let unit := Core.Tla.SourceUnit.create .inlineSourceMap logicalPath source
  { moduleName
    logicalPath
    contentSha256 := unit.contentSha256 }

/-- Content manifest for an inline source closure. Logical paths are stable
module-relative names and never expose the temporary materialization path. -/
def inlineSourceDigests (spec : Codec.SpecConfig) :
    Except String (List Core.ModelInterface.SourceDigest) := do
  let named ← spec.sources.mapM fun source => do
    let name ← declaredModuleName "source.tla" source
    return (name.name, source)
  let names := named.map Prod.fst
  if names.eraseDups.length != names.length then
    throw "duplicate module names in spec sources"
  return named.map fun (name, source) =>
    sourceDigest name (name ++ ".tla") source

/-- Best-effort manifest for a borrowed root source. The logical path is only
the filename; an absolute server path never enters compiler provenance. The
root is captured by the same provider the frontend uses, so the digest is
computed over exactly the bytes an analysis would read. -/
def borrowedRootSourceDigest (path : String) : IO (Except String Core.ModelInterface.SourceDigest) := do
  let rootPath : System.FilePath := path
  match rootPath.fileName with
  | none => return .error "unable to read registered model source"
  | some logicalPath =>
      let rootDir := rootPath.parent.getD ("." : System.FilePath)
      match ← Shell.Tla.SourceProvider.readRootFile rootDir logicalPath with
      | .error _ => return .error "unable to read registered model source"
      | .ok unit =>
          match declaredModuleName logicalPath unit.normalizedText with
          | .error error => return .error error
          | .ok name =>
              return .ok { moduleName := name.name
                           logicalPath
                           contentSha256 := unit.contentSha256 }

/-! ## Resource limits for one captured closure -/

/-- Resource limits for resolving a borrowed source closure. -/
structure BorrowedSourceLimits where
  /-- Maximum number of distinct local modules in one closure. -/
  maxModules : Nat := 128
  /-- Maximum raw UTF-8 bytes in one local module. -/
  maxFileBytes : Nat := 4 * 1024 * 1024
  /-- Maximum raw UTF-8 bytes across all local modules. -/
  maxTotalBytes : Nat := 16 * 1024 * 1024
  /-- Maximum dependency edges from the root to a local module. -/
  maxDepth : Nat := 64
  deriving Repr, BEq

/-- Default bounded profile for borrowed TLA+ source closures. -/
def defaultBorrowedSourceLimits : BorrowedSourceLimits := {}

private structure BorrowedSourceFile where
  logicalPath : String
  /-- The exact UTF-8 text written to a negotiated trace snapshot. This is the
  captured normalized text every digest above is computed over. -/
  normalizedSource : String

private structure BorrowedClosureState where
  visited : List String := []
  digests : List Core.ModelInterface.SourceDigest := []
  files : List BorrowedSourceFile := []
  totalBytes : Nat := 0

/-- Legacy error text for one rejected borrowed read. Messages keep naming the
logical path only, and keep the phrases existing callers and gates match. -/
private def borrowedReadError : Shell.Tla.SourceReadError → String
  | .symbolicLink path => s!"borrowed source '{path}' is a symbolic link"
  | .notRegularFile path => s!"borrowed source '{path}' is not a regular file"
  | .tooLarge path limit _ =>
      s!"borrowed source '{path}' exceeds file byte limit {limit}"
  | .invalidUtf8 path => s!"borrowed source '{path}' is not valid UTF-8"
  | .invalidReference path reason => s!"invalid source reference '{path}': {reason}"
  | .identityChanged path =>
      s!"borrowed source '{path}' changed identity while it was being read"
  | .notFound name => s!"unable to read borrowed source '{name.name}.tla'"
  | .unreadable path reason =>
      s!"unable to read borrowed source '{path}': {reason}"
  | .standardModuleUnavailable name =>
      s!"standard module '{name.name}' is not in the pinned catalog"

/-- `true` when the frontend's pinned catalog treats the name as external. -/
private def isPinnedStandardModule (name : String) : Bool :=
  (Shell.Tla.StandardModuleCatalog.find? Shell.Tla.StandardModuleCatalog.default
    { name := name }).isSome

/-- Capture one borrowed module through the frontend's borrowed-directory
provider (regular file only, byte-bounded read, identity recheck, UTF-8
validation), then follow the dependency declarations of its one parse. The walk
keeps the closure policy this module always had: cycles terminate, closure-wide
budgets fail closed, and unpublished logical paths never expose a physical
location. -/
private partial def captureBorrowedSource
    (rootDir : System.FilePath) (provider : Shell.Tla.SourceProvider)
    (logicalPath : String) (expectedName : Option String) (depth : Nat)
    (limits : BorrowedSourceLimits) (state : BorrowedClosureState) :
    IO (Except String BorrowedClosureState) := do
  if expectedName.any state.visited.contains then return .ok state
  if depth > limits.maxDepth then
    return .error s!"borrowed source closure exceeds depth limit {limits.maxDepth}"
  let read : IO (Except Shell.Tla.SourceReadError Core.Tla.SourceUnit) :=
    match expectedName with
    | none =>
        Shell.Tla.SourceProvider.readRootFile rootDir logicalPath
          { maxFileBytes := limits.maxFileBytes }
    | some name =>
        provider.readDependency { name := name }
  match ← read with
  | .error error => return .error (borrowedReadError error)
  | .ok unit =>
      let parsed ← match parseCaptured unit with
        | .ok parsed => pure parsed
        | .error error => return .error s!"borrowed source '{logicalPath}': {error}"
      let actualName := parsed.name.name
      if !Core.Tla.ModuleName.valid actualName then
        return .error s!"borrowed source '{logicalPath}' declares invalid module name '{actualName}'"
      match expectedName with
      | some expected =>
          if actualName != expected then
            return .error s!"borrowed source '{logicalPath}' declares module '{actualName}', expected '{expected}'"
      | none => pure ()
      if state.visited.contains actualName then return .ok state
      if state.digests.length >= limits.maxModules then
        return .error s!"borrowed source closure exceeds module limit {limits.maxModules}"
      let capturedBytes := unit.normalizedUtf8.size
      if state.totalBytes + capturedBytes > limits.maxTotalBytes then
        return .error s!"borrowed source closure exceeds total byte limit {limits.maxTotalBytes}"
      let mut current : BorrowedClosureState := {
        visited := actualName :: state.visited
        digests := {
          moduleName := actualName
          logicalPath
          contentSha256 := unit.contentSha256
        } :: state.digests
        files := {
          logicalPath
          normalizedSource := unit.normalizedText
        } :: state.files
        totalBytes := state.totalBytes + capturedBytes
      }
      for declaration in Core.Tla.ParsedModule.dependencies parsed do
        let dependency := declaration.moduleName.name
        if !current.visited.contains dependency then
          let dependencyPath := rootDir / (dependency ++ ".tla")
          if ← dependencyPath.pathExists then
            match ← captureBorrowedSource rootDir provider
                (dependency ++ ".tla") (some dependency) (depth + 1) limits
                current with
            | .error error => return .error error
            | .ok updated => current := updated
          else if !isPinnedStandardModule dependency then
            return .error s!"borrowed source references missing sibling module '{dependency}'"
      return .ok current
private def sortSourceDigests
    (sources : List Core.ModelInterface.SourceDigest) :
    List Core.ModelInterface.SourceDigest :=
  sources.mergeSort fun left right =>
    if left.moduleName == right.moduleName then
      left.logicalPath ≤ right.logicalPath
    else
      left.moduleName ≤ right.moduleName

private def resolveBorrowedSourceClosure (path : String)
    (limits : BorrowedSourceLimits) :
    IO (Except String (String × BorrowedClosureState)) := do
  let rootPath : System.FilePath := path
  let logicalPath ← match rootPath.fileName with
    | some name => pure name
    | none => return .error "borrowed source path has no filename"
  if !logicalPath.endsWith ".tla" || logicalPath.contains "\\" then
    return .error "borrowed source must be a relative logical .tla filename"
  let rootDir := rootPath.parent.getD ("." : System.FilePath)
  let provider := Shell.Tla.SourceProvider.borrowedDirectory rootDir
    { maxFileBytes := limits.maxFileBytes } Shell.Tla.StandardModuleCatalog.default
  match ← captureBorrowedSource rootDir provider logicalPath none 0 limits {} with
  | .error error => return .error error
  | .ok state => return .ok (logicalPath, state)

/-- Resolve and hash a borrowed root's sibling `EXTENDS`/`INSTANCE` closure.
The manifest is sorted and contains logical filenames only; filesystem paths
remain confined to this effectful resolver. -/
def borrowedSourceDigests (path : String)
    (limits : BorrowedSourceLimits := defaultBorrowedSourceLimits) :
    IO (Except String (List Core.ModelInterface.SourceDigest)) := do
  match ← resolveBorrowedSourceClosure path limits with
  | .error error => return .error error
  | .ok (_, state) => return .ok (sortSourceDigests state.digests)

/-! ## Spec materialization -/

private initialize dirCounter : IO.Ref Nat ← IO.mkRef 0

private def tempBase : IO String := do
  -- t30: on Windows prefer TEMP/TMP (MSYS converts those to native
  -- paths when spawning native binaries; TMPDIR stays POSIX-style and
  -- would resolve against the wrong drive root). The windows-dev box
  -- has a broken global TEMP pointing at a nonexistent D:\.local\TMP,
  -- so only an EXISTING dir is accepted; otherwise fall back to the
  -- platform default, and finally the cwd.
  let envCands : Array (Option String) ←
    if System.Platform.isWindows then
      pure #[← IO.getEnv "TEMP", ← IO.getEnv "TMP", ← IO.getEnv "TMPDIR"]
    else
      pure #[← IO.getEnv "TMPDIR"]
  let cands := envCands.filterMap id ++
    (if System.Platform.isWindows then ["C:/Windows/Temp", "."] else ["/tmp", "."])
  for c in cands do
    if ← (c : System.FilePath).pathExists then return c
  return "."

/-- A fresh spec temp dir (Haskell @freshSpecDir@): retry with a new
counter on collision. -/
private def pathSep : String := if System.Platform.isWindows then "\\" else "/"

private partial def freshSpecDir : IO String := do
  let tmp ← tempBase
  let n ← dirCounter.modifyGet (fun m => (m, m + 1))
  let dir := tmp ++ pathSep ++ "modelmirrors-spec-" ++ toString n
  try
    IO.FS.createDir dir
    return dir
  catch _ =>
    freshSpecDir

/-- Materialize an inline spec into a fresh temp dir: one @.tla@ file
per source named by its module header; errors on missing headers or
duplicate module names (Haskell @materializeSpec@). Returns the dir and
the root module's path. -/
def materializeSpec (spec : Codec.SpecConfig) : IO (Except String (String × String)) := do
  match spec.sources with
  | [] => return .error "spec has no sources"
  | sources =>
      let mut named : List (String × String) := []
      for s in sources do
        match declaredModuleName "source.tla" s with
        | .error e => return .error e
        | .ok n => named := named ++ [(n.name, s)]
      let names := named.map Prod.fst
      if names.eraseDups.length != names.length then
        return .error "duplicate module names in spec sources"
      else
        match named.head? with
        | none => return .error "spec has no sources"
        | some (rootName, _) =>
            let dir ← freshSpecDir
            -- Publish the captured normalized bytes, so the file Apalache opens
            -- is the same text the manifest hashes.
            for (n, s) in named do
              let unit := Core.Tla.SourceUnit.create .inlineSourceMap
                (n ++ ".tla") s
              IO.FS.writeFile (dir ++ "/" ++ n ++ ".tla") unit.normalizedText
            return .ok (dir, dir ++ "/" ++ rootName ++ ".tla")

/-- Recursively delete a directory (Haskell @removeDirectoryRecursive@;
total: ignores errors for already-gone paths). -/
private def ignoring (act : IO Unit) : IO Unit := do
  try act catch _ => pure ()

partial def removeDirRecursive (path : String) : IO Unit := do
  let isD ← (path : System.FilePath).isDir
  if isD then
    let entries ← (path : System.FilePath).readDir
    for e in entries.toList do
      removeDirRecursive e.path.toString
    ignoring (IO.FS.removeDir path)
  else
    ignoring (IO.FS.removeFile path)

/-- Spec provenance (Haskell @Resource.Provenance@). -/
inductive Provenance
  /-- Materialized from inline sources into a mirror-owned temp dir. -/
  | Owned | Borrowed
deriving BEq, Repr

/-- An acquired spec resource (Haskell @SpecRes@). -/
structure SpecRes where
  /-- Temp dir to remove on release when owned. -/
  dir : Option String
  /-- Root @.tla@ path to hand to apalache. -/
  rootPath : String
  provenance : Provenance
deriving Repr

/-- Release an acquired spec: owned dirs are deleted, borrowed specs are
left untouched (total). -/
def releaseSpec (res : SpecRes) : IO Unit :=
  match res.dir with
  | some d => removeDirRecursive d
  | none => pure ()

/-- Acquire a spec resource (Haskell @acquireSpec@): inline sources are
materialized (owned; the returned config's @specPath@ is overridden to
the root path); @none@ borrows the config's own @specPath@. -/
def acquireSpec (mSpec : Option Codec.SpecConfig) (cfg : Codec.ApalacheConfig) :
    IO (Except String (SpecRes × Codec.ApalacheConfig)) := do
  match mSpec with
  | none => return .ok (⟨none, cfg.specPath, .Borrowed⟩, cfg)
  | some spec =>
      match ← materializeSpec spec with
      | .error e => return .error e
      | .ok (dir, rootPath) =>
          return .ok (⟨some dir, rootPath, .Owned⟩,
                       { cfg with specPath := rootPath })

/-- Capture a borrowed root and its local `EXTENDS`/`INSTANCE` closure once,
then materialize those captured, LF-normalized bytes into a mirror-owned
directory. The returned digest manifest and the files at the returned config's
`specPath` are two views of the same in-memory capture, so a later change to the
borrowed files cannot change what Apalache reads.

This is used only when negotiated model-interface provenance is requested;
legacy borrowed acquisition remains zero-copy through `acquireSpec`. -/
def acquireBorrowedSpecSnapshot (cfg : Codec.ApalacheConfig)
    (limits : BorrowedSourceLimits := defaultBorrowedSourceLimits) :
    IO (Except String
      (SpecRes × Codec.ApalacheConfig ×
        List Core.ModelInterface.SourceDigest)) := do
  match ← resolveBorrowedSourceClosure cfg.specPath limits with
  | .error error => return .error error
  | .ok (rootLogicalPath, state) =>
      let dir ← freshSpecDir
      try
        for file in state.files do
          IO.FS.writeFile
            (((dir : System.FilePath) / file.logicalPath).toString)
            file.normalizedSource
        let rootPath := ((dir : System.FilePath) / rootLogicalPath).toString
        let resource : SpecRes := ⟨some dir, rootPath, .Owned⟩
        return .ok (resource, { cfg with specPath := rootPath },
          sortSourceDigests state.digests)
      catch _ =>
        removeDirRecursive dir
        return .error "unable to materialize borrowed source snapshot"

/-! ## Session dirs -/

/-- Create a fresh per-session temp directory (Haskell
@freshSessionDir@): the dir apalache uses as its run dir / cwd. -/
def freshSessionDir : IO String := do
  let tmp ← tempBase
  let n ← dirCounter.modifyGet (fun m => (m, m + 1))
  let ms ← IO.monoMsNow
  let dir := tmp ++ pathSep ++ "modelmirrors-session-" ++ toString n ++ "-" ++ toString ms
  try IO.FS.createDir dir
  catch _ => IO.FS.createDir (dir ++ "-x")
  return dir

/-- Remove a session dir (total, recursive). -/
def removeSessionDir (path : String) : IO Unit := removeDirRecursive path

end Shell.Apalache.SpecSource
