import Codec.Json
import Core.Value
import Core.ModelInterface.Types
import Core.ModelInterface.Sha256
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
-/

namespace Shell.Apalache.SpecSource

/-! ## MODULE header parsing -/

private def isModuleLine (l : String) : Bool :=
  l.contains "MODULE" && (String.ofList (l.toList.dropWhile (· == ' '))).startsWith "-"

private def allDashes (s : String) : Bool :=
  !s.isEmpty && s.all (· == '-')

private def validModuleReference (name : String) : Bool :=
  match name.toList with
  | [] => false
  | first :: rest =>
      (first.isAlpha || first == '_') &&
        rest.all (fun character => character.isAlphanum || character == '_')

/-- Parse the module name from a spec source: the first
@----- MODULE Name -----@ header line (Haskell @moduleName@). -/
def moduleName (src : String) : Except String String :=
  match (src.splitOn "\n").filter isModuleLine with
  | [] => .error "no MODULE header found in spec source"
  | l :: _ =>
      match l.splitOn " " |>.filter (· != "") with
      | dashes :: kw :: name :: rest =>
          if allDashes dashes && kw == "MODULE" && !allDashes name
              && rest.all allDashes && validModuleReference name then
            .ok name
          else
            .error s!"malformed MODULE header: {l}"
      | _ => .error s!"malformed MODULE header: {l}"

private def normalizeModelSource (source : String) : String :=
  (source.replace "\r\n" "\n").replace "\r" "\n"

private def sourceDigest (moduleName logicalPath source : String) :
    Core.ModelInterface.SourceDigest :=
  { moduleName
    logicalPath
    contentSha256 := Core.ModelInterface.Sha256.digestHex
      (normalizeModelSource source).toUTF8 }

/-- Content manifest for an inline source closure. Logical paths are stable
module-relative names and never expose the temporary materialization path. -/
def inlineSourceDigests (spec : Codec.SpecConfig) :
    Except String (List Core.ModelInterface.SourceDigest) := do
  let named ← spec.sources.mapM fun source => do
    let name ← moduleName source
    return (name, source)
  let names := named.map Prod.fst
  if names.eraseDups.length != names.length then
    throw "duplicate module names in spec sources"
  return named.map fun (name, source) =>
    sourceDigest name (name ++ ".tla") source

/-- Best-effort manifest for a borrowed root source. The logical path is only
the filename; an absolute server path never enters compiler provenance. -/
def borrowedRootSourceDigest (path : String) : IO (Except String Core.ModelInterface.SourceDigest) := do
  try
    let source ← IO.FS.readFile path
    let name ← match moduleName source with
      | .ok name => pure name
      | .error error => return .error error
    let logicalPath := (path : System.FilePath).fileName.getD (name ++ ".tla")
    return .ok (sourceDigest name logicalPath source)
  catch _ =>
    return .error "unable to read registered model source"

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

private inductive SourceScanMode where
  | code
  | lineComment
  | blockComment (depth : Nat)
  | stringLiteral

private partial def codeOnlyChars (remaining : List Char)
    (mode : SourceScanMode) (reversed : List Char) : Except String (List Char) :=
  match mode, remaining with
  | .code, [] | .lineComment, [] => .ok reversed.reverse
  | .blockComment _, [] => .error "unterminated block comment"
  | .stringLiteral, [] => .error "unterminated string literal"
  | .code, '\\' :: '*' :: rest =>
      codeOnlyChars rest .lineComment (' ' :: reversed)
  | .code, '(' :: '*' :: rest =>
      codeOnlyChars rest (.blockComment 1) (' ' :: reversed)
  | .code, '"' :: rest =>
      codeOnlyChars rest .stringLiteral (' ' :: reversed)
  | .code, character :: rest =>
      codeOnlyChars rest .code (character :: reversed)
  | .lineComment, '\n' :: rest =>
      codeOnlyChars rest .code ('\n' :: reversed)
  | .lineComment, _ :: rest =>
      codeOnlyChars rest .lineComment reversed
  | .blockComment depth, '(' :: '*' :: rest =>
      codeOnlyChars rest (.blockComment (depth + 1)) reversed
  | .blockComment depth, '*' :: ')' :: rest =>
      if depth == 1 then codeOnlyChars rest .code (' ' :: reversed)
      else codeOnlyChars rest (.blockComment (depth - 1)) reversed
  | .blockComment depth, '\n' :: rest =>
      codeOnlyChars rest (.blockComment depth) ('\n' :: reversed)
  | .blockComment depth, _ :: rest =>
      codeOnlyChars rest (.blockComment depth) reversed
  | .stringLiteral, '\\' :: _ :: rest =>
      codeOnlyChars rest .stringLiteral reversed
  | .stringLiteral, '"' :: rest =>
      codeOnlyChars rest .code (' ' :: reversed)
  | .stringLiteral, '\n' :: _ =>
      .error "newline in string literal"
  | .stringLiteral, _ :: rest =>
      codeOnlyChars rest .stringLiteral reversed

private def codeOnlySource (source : String) : Except String String :=
  (codeOnlyChars source.toList .code []).map String.ofList

private inductive SourceToken where
  | ident (value : String)
  | comma
  | newline
  | boundary
  deriving Repr

private def pushSourceIdent (current : List Char)
    (reversed : List SourceToken) : List SourceToken :=
  if current.isEmpty then reversed
  else .ident (String.ofList current.reverse) :: reversed

private def pushSourceBoundary (reversed : List SourceToken) : List SourceToken :=
  match reversed with
  | .boundary :: _ => reversed
  | _ => .boundary :: reversed

private def isHorizontalSpace (character : Char) : Bool :=
  character == ' ' || character == '\t'

private def sourceTokensAux : List Char → List Char →
    List SourceToken → List SourceToken
  | [], current, reversed => (pushSourceIdent current reversed).reverse
  | character :: rest, current, reversed =>
      if character.isAlphanum || character == '_' then
        sourceTokensAux rest (character :: current) reversed
      else
        let reversed := pushSourceIdent current reversed
        let reversed :=
          if character == ',' then .comma :: reversed
          else if character == '\n' then .newline :: reversed
          else if isHorizontalSpace character then reversed
          else pushSourceBoundary reversed
        sourceTokensAux rest [] reversed

private def sourceTokens (source : String) : List SourceToken :=
  sourceTokensAux source.toList [] []

private inductive DependencyScanMode where
  | normal
  | extendsName
  | extendsSeparator
  | instanceName

private def appendUnique (values : List String) (value : String) : List String :=
  if values.contains value then values else values ++ [value]

private partial def collectDependencies (owner : String) :
    List SourceToken → DependencyScanMode → List String →
      Except String (List String)
  | [], .normal, dependencies
  | [], .extendsSeparator, dependencies => .ok dependencies
  | [], .extendsName, _ =>
      .error s!"module '{owner}': EXTENDS requires a module name"
  | [], .instanceName, _ =>
      .error s!"module '{owner}': INSTANCE requires a module name"
  | .ident "EXTENDS" :: rest, .normal, dependencies =>
      collectDependencies owner rest .extendsName dependencies
  | .ident "INSTANCE" :: rest, .normal, dependencies =>
      collectDependencies owner rest .instanceName dependencies
  | _ :: rest, .normal, dependencies =>
      collectDependencies owner rest .normal dependencies
  | .newline :: rest, .extendsName, dependencies =>
      collectDependencies owner rest .extendsName dependencies
  | .ident name :: rest, .extendsName, dependencies =>
      if validModuleReference name then
        collectDependencies owner rest .extendsSeparator
          (appendUnique dependencies name)
      else
        .error s!"module '{owner}': invalid EXTENDS module name '{name}'"
  | _ :: _, .extendsName, _ =>
      .error s!"module '{owner}': EXTENDS requires a module name"
  | .comma :: rest, .extendsSeparator, dependencies =>
      collectDependencies owner rest .extendsName dependencies
  | .newline :: rest, .extendsSeparator, dependencies
  | .boundary :: rest, .extendsSeparator, dependencies =>
      collectDependencies owner rest .normal dependencies
  | .ident name :: _, .extendsSeparator, _ =>
      .error s!"module '{owner}': expected ',' before EXTENDS module '{name}'"
  | .newline :: rest, .instanceName, dependencies =>
      collectDependencies owner rest .instanceName dependencies
  | .ident name :: rest, .instanceName, dependencies =>
      if validModuleReference name then
        collectDependencies owner rest .normal (appendUnique dependencies name)
      else
        .error s!"module '{owner}': invalid INSTANCE module name '{name}'"
  | _ :: _, .instanceName, _ =>
      .error s!"module '{owner}': INSTANCE requires a module name"

private def sourceDependencies (owner code : String) : Except String (List String) :=
  collectDependencies owner (sourceTokens code) .normal []

private def knownStandardModules : List String :=
  ["Naturals", "Integers", "Reals", "Sequences", "FiniteSets", "Bags",
    "TLC", "TLCExt", "Toolbox", "Randomization", "RealTime", "Json",
    "CSV", "IOUtils", "Option", "Variants", "Apalache"]

private structure BorrowedSourceFile where
  logicalPath : String
  /-- The exact UTF-8 text written to a negotiated trace snapshot. Source
  digests are computed over these normalized bytes. -/
  normalizedSource : String

private structure BorrowedClosureState where
  visited : List String := []
  digests : List Core.ModelInterface.SourceDigest := []
  files : List BorrowedSourceFile := []
  totalBytes : Nat := 0

private partial def readBorrowedBytesAux (handle : IO.FS.Handle) (limit : Nat)
    (accumulator : ByteArray) : IO (Except String ByteArray) := do
  if accumulator.size > limit then return .error "source exceeds byte limit"
  let remainingProbe := limit + 1 - accumulator.size
  let requestSize := min 65536 remainingProbe
  let chunk ← handle.read requestSize.toUSize
  if chunk.isEmpty then return .ok accumulator
  readBorrowedBytesAux handle limit (accumulator.append chunk)

private def readBorrowedSource (path : System.FilePath) (logicalPath : String)
    (limits : BorrowedSourceLimits) : IO (Except String (String × Nat)) := do
  try
    let metadata ← path.symlinkMetadata
    if metadata.type == .symlink then
      return .error s!"borrowed source '{logicalPath}' is a symbolic link"
    if metadata.type != .file then
      return .error s!"borrowed source '{logicalPath}' is not a regular file"
    if metadata.byteSize.toNat > limits.maxFileBytes then
      return .error s!"borrowed source '{logicalPath}' exceeds file byte limit {limits.maxFileBytes}"
    let handle ← IO.FS.Handle.mk path .read
    match ← readBorrowedBytesAux handle limits.maxFileBytes ByteArray.empty with
    | .error _ =>
        return .error s!"borrowed source '{logicalPath}' exceeds file byte limit {limits.maxFileBytes}"
    | .ok bytes =>
        match String.fromUTF8? bytes with
        | none => return .error s!"borrowed source '{logicalPath}' is not valid UTF-8"
        | some source => return .ok (source, bytes.size)
  catch _ =>
    return .error s!"unable to read borrowed source '{logicalPath}'"

private partial def visitBorrowedSource
    (rootDir : System.FilePath) (path : System.FilePath)
    (logicalPath : String) (expectedName : Option String) (depth : Nat)
    (limits : BorrowedSourceLimits) (state : BorrowedClosureState) :
    IO (Except String BorrowedClosureState) := do
  if expectedName.any state.visited.contains then return .ok state
  if depth > limits.maxDepth then
    return .error s!"borrowed source closure exceeds depth limit {limits.maxDepth}"
  match ← readBorrowedSource path logicalPath limits with
  | .error error => return .error error
  | .ok (source, bytes) =>
      let normalized := normalizeModelSource source
      let code ← match codeOnlySource normalized with
        | .ok code => pure code
        | .error error =>
            return .error s!"borrowed source '{logicalPath}': {error}"
      let actualName ← match moduleName code with
        | .ok name => pure name
        | .error error =>
            return .error s!"borrowed source '{logicalPath}': {error}"
      if !validModuleReference actualName then
        return .error s!"borrowed source '{logicalPath}' declares invalid module name '{actualName}'"
      match expectedName with
      | some expected =>
          if actualName != expected then
            return .error s!"borrowed source '{logicalPath}' declares module '{actualName}', expected '{expected}'"
      | none => pure ()
      if state.visited.contains actualName then return .ok state
      if state.digests.length >= limits.maxModules then
        return .error s!"borrowed source closure exceeds module limit {limits.maxModules}"
      if state.totalBytes + bytes > limits.maxTotalBytes then
        return .error s!"borrowed source closure exceeds total byte limit {limits.maxTotalBytes}"
      let dependencies ← match sourceDependencies actualName code with
        | .ok dependencies => pure dependencies
        | .error error => return .error error
      let mut current : BorrowedClosureState := {
        visited := actualName :: state.visited
        digests := sourceDigest actualName logicalPath normalized :: state.digests
        files := {
          logicalPath
          normalizedSource := normalized
        } :: state.files
        totalBytes := state.totalBytes + bytes
      }
      for dependency in dependencies do
        if !current.visited.contains dependency then
          let dependencyPath := rootDir / (dependency ++ ".tla")
          if ← dependencyPath.pathExists then
            match ← visitBorrowedSource rootDir dependencyPath
                (dependency ++ ".tla") (some dependency) (depth + 1)
                limits current with
            | .error error => return .error error
            | .ok updated => current := updated
          else if !knownStandardModules.contains dependency then
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
  match ← visitBorrowedSource rootDir rootPath logicalPath none 0 limits {} with
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
        match moduleName s with
        | .error e => return .error e
        | .ok n => named := named ++ [(n, s)]
      let names := named.map Prod.fst
      if names.eraseDups.length != names.length then
        return .error "duplicate module names in spec sources"
      else
        match named.head? with
        | none => return .error "spec has no sources"
        | some (rootName, _) =>
            let dir ← freshSpecDir
            for (n, s) in named do
              IO.FS.writeFile (dir ++ "/" ++ n ++ ".tla") s
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
