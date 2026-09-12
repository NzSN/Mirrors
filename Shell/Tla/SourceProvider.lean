import Core.Tla.Graph
import Core.Tla.Source

/-!
# TLA+ source providers (`Shell/Tla/SourceProvider.lean`)

Effectful source capture for the general TLA+ frontend
(`Docs/model-interface-compiler/tla-frontend-design.md`, §6 "Architecture",
§7.1 "Two source-provider adapters", §19 "Standard modules", and §21 "Resource
and security limits").

A provider answers exactly three questions:

* what are the captured bytes of the requested root reference;
* what are the captured bytes of a requested dependency; and
* which pinned standard-module facts describe a name?

Providers do not parse TLA+ and do not decide semantics. Every borrowed read is
bounded, rejects symbolic links and special files, rechecks identity after the
read, and resolves only canonical bare `.tla` file names inside one pinned
directory. Logical names and captured bytes are all that cross this module's
boundary: a `SourceUnit`, a `SourceIdentity`, or a `SourceReadError` never
carries a physical path.

Two adapters exist because two source forms already exist downstream:

* `SourceProvider.borrowedDirectory` — sibling files under one pinned root
  directory; and
* `SourceProvider.inline` — a caller-supplied closed source map with no
  filesystem access.

Standard-module identity is explicit (`StandardModuleCatalog`). A name in a list
is not enough to invent operator arities or variable facts, so the catalog
records pinned identity facts only; declaration facts remain the elaborator's
business.
-/

namespace Shell.Tla

open Core.Tla

/-! ## Root references -/

/-- A requested root source: the module name the root is expected to declare,
plus the logical `.tla` file name the provider resolves. Physical locations stay
in the caller's provider configuration and never enter this type. -/
structure ModuleRef where
  moduleName : Core.Tla.ModuleName
  logicalPath : String
  deriving Repr, BEq, DecidableEq

namespace ModuleRef

/-- The canonical reference for a module name: `<Name>.tla`. -/
def ofModuleName (moduleName : Core.Tla.ModuleName) : ModuleRef :=
  { moduleName, logicalPath := moduleName.name ++ ".tla" }

/-- `true` when `logicalPath` is a canonical bare `.tla` file name: a valid
module-name stem, no directory separators, and no `..` component. -/
def validLogicalPath (logicalPath : String) : Bool :=
  let stem := (logicalPath.take (logicalPath.length - 4)).toString
  logicalPath.endsWith ".tla" &&
    !logicalPath.contains '/' &&
    !logicalPath.contains '\\' &&
    logicalPath.length > 4 &&
    Core.Tla.ModuleName.valid stem

end ModuleRef

/-! ## Read errors -/

/-- A rejected or failed source read. Errors are logical: they name a logical
path or module name and never a physical location. -/
inductive SourceReadError where
  | invalidReference (logicalPath : String) (reason : String)
  | notFound (moduleName : Core.Tla.ModuleName)
  | notRegularFile (logicalPath : String)
  | symbolicLink (logicalPath : String)
  | tooLarge (logicalPath : String) (limit : Nat) (observed : Nat)
  | invalidUtf8 (logicalPath : String)
  | unreadable (logicalPath : String) (reason : String)
  | identityChanged (logicalPath : String)
  | standardModuleUnavailable (moduleName : Core.Tla.ModuleName)
  deriving Repr, BEq, DecidableEq

namespace SourceReadError

/-- Stable rendering for loaders that surface read failures. Diagnostic
construction and JSON rendering belong to the frontend; this text is not a
compatibility contract. -/
def message : SourceReadError → String
  | .invalidReference logicalPath reason =>
      s!"invalid source reference '{logicalPath}': {reason}"
  | .notFound moduleName =>
      s!"module '{moduleName.name}' was not found"
  | .notRegularFile logicalPath =>
      s!"borrowed source '{logicalPath}' is not a regular file"
  | .symbolicLink logicalPath =>
      s!"borrowed source '{logicalPath}' is a symbolic link"
  | .tooLarge logicalPath limit observed =>
      s!"borrowed source '{logicalPath}' is {observed} bytes, exceeding the {limit}-byte limit"
  | .invalidUtf8 logicalPath =>
      s!"borrowed source '{logicalPath}' is not valid UTF-8"
  | .unreadable logicalPath reason =>
      s!"unable to read borrowed source '{logicalPath}': {reason}"
  | .identityChanged logicalPath =>
      s!"borrowed source '{logicalPath}' changed identity while it was being read"
  | .standardModuleUnavailable moduleName =>
      s!"standard module '{moduleName.name}' is not in the pinned catalog"

end SourceReadError

/-! ## Standard-module catalog -/

/-- The pinned standard-module profile. `baseline` records the compatibility
baseline (for example a pinned Apalache version) once the profile owner pins it;
`none` means the profile pins only the module list and kinds. -/
structure StandardModuleProfile where
  profileId : String
  baseline : Option String
  deriving Repr, BEq, DecidableEq

/-- The standard modules the current production loader already treats as
external. The frontend makes that choice explicit here instead of inferring it
from a failed sibling-file lookup. -/
def defaultStandardModules : Array StandardModule :=
  let entry (name : String) (kind : StandardModuleKind) : StandardModule :=
    { name := ⟨name⟩, kind, contentIdentity := none }
  #[
    entry "Naturals" .languageDefined,
    entry "Integers" .languageDefined,
    entry "Reals" .languageDefined,
    entry "Sequences" .languageDefined,
    entry "FiniteSets" .languageDefined,
    entry "Bags" .languageDefined,
    entry "TLC" .languageDefined,
    entry "TLCExt" .languageDefined,
    entry "Toolbox" .languageDefined,
    entry "Randomization" .languageDefined,
    entry "RealTime" .languageDefined,
    entry "Json" .apalacheExtension,
    entry "CSV" .apalacheExtension,
    entry "IOUtils" .apalacheExtension,
    entry "Option" .apalacheExtension,
    entry "Variants" .apalacheExtension,
    entry "Apalache" .apalacheExtension
  ]

/-- The versioned standard-module catalog: a profile identity plus pinned module
entries. Changing either invalidates frontend caches and must be visible in
provenance. -/
structure StandardModuleCatalog where
  profile : StandardModuleProfile
  modules : Array StandardModule
  deriving Repr, BEq

namespace StandardModuleCatalog

/-- The first frontend profile. The module list mirrors the production loader's
known-standard list; the profile id changes when the list or a baseline changes. -/
def defaultProfile : StandardModuleProfile :=
  { profileId := "mirrors-standard-modules/v1", baseline := none }

/-- The default catalog used until the coordinator pins a SANY/Apalache baseline. -/
def default : StandardModuleCatalog :=
  { profile := defaultProfile, modules := defaultStandardModules }

/-- Look up a standard module by name. -/
def find? (catalog : StandardModuleCatalog) (moduleName : Core.Tla.ModuleName) :
    Option StandardModule :=
  catalog.modules.find? fun entry => entry.name == moduleName

/-- `true` when the catalog pins `moduleName`. -/
def contains (catalog : StandardModuleCatalog) (moduleName : Core.Tla.ModuleName) :
    Bool :=
  (catalog.find? moduleName).isSome

end StandardModuleCatalog

/-! ## Provider interface -/

/-- Bounds that a borrowed provider enforces on a single file. Closure-wide
budgets (module count, total bytes, depth, edges) belong to the module resolver,
which sees the whole graph. -/
structure SourceProviderLimits where
  /-- Maximum raw UTF-8 bytes accepted from one borrowed module file. -/
  maxFileBytes : Nat := 4 * 1024 * 1024
  deriving Repr, BEq

/-- The frontend's only source-I/O seam. A provider returns logical names and
captured bytes; it never parses source, decides TLA+ semantics, or reveals a
physical path. -/
structure SourceProvider where
  readRoot : ModuleRef → IO (Except SourceReadError Core.Tla.SourceUnit)
  readDependency :
    Core.Tla.ModuleName → IO (Except SourceReadError Core.Tla.SourceUnit)
  resolveStandard :
    Core.Tla.ModuleName → IO (Except SourceReadError StandardModule)

namespace SourceProvider

private def standardLookup (catalog : StandardModuleCatalog)
    (moduleName : Core.Tla.ModuleName) :
    IO (Except SourceReadError StandardModule) :=
  match catalog.find? moduleName with
  | some entry => pure (.ok entry)
  | none => pure (.error (.standardModuleUnavailable moduleName))

private def metadataOrNone (path : System.FilePath) : IO (Option IO.FS.Metadata) := do
  try
    return some (← path.symlinkMetadata)
  catch _ =>
    return none

private partial def readBoundedAux (handle : IO.FS.Handle) (limit : Nat)
    (accumulator : ByteArray) : IO (Except Unit ByteArray) := do
  if accumulator.size > limit then
    return .error ()
  let remaining := limit + 1 - accumulator.size
  let chunk ← handle.read (min 65536 remaining).toUSize
  if chunk.isEmpty then
    return .ok accumulator
  readBoundedAux handle limit (accumulator.append chunk)

private def readBounded (path : System.FilePath) (limit : Nat) :
    IO (Except Unit ByteArray) := do
  try
    let handle ← IO.FS.Handle.mk path .read
    readBoundedAux handle limit ByteArray.empty
  catch _ =>
    return .error ()

/-- `true` for a bare logical root `.tla` file name: no directory component,
no drive designator, and not the empty stem. The stem is a file name, not
necessarily a valid module-name spelling: a root file's module identity always
comes from its captured `MODULE` header, so `RBT-stale.tla` is a usable root
name while `../Root.tla` and `dir/Root.tla` are not. -/
def validRootFileName (logicalPath : String) : Bool :=
  logicalPath.endsWith ".tla" && logicalPath.length > 4 &&
    !logicalPath.contains '/' && !logicalPath.contains '\\' &&
    !logicalPath.contains ':' && logicalPath != "." && logicalPath != ".."

/-- Read one source file beneath a pinned directory: regular file only, bounded
bytes, identity rechecked after the read (kind, size, and modification time),
and UTF-8 validated before capture. `missing` is the error a caller wants when
the file is absent. -/
private def readSourceFile (path : System.FilePath) (limits : SourceProviderLimits)
    (logicalPath : String) (missing : SourceReadError) :
    IO (Except SourceReadError Core.Tla.SourceUnit) := do
  match ← metadataOrNone path with
  | none => return .error missing
  | some before =>
      if before.type == .symlink then
        return .error (.symbolicLink logicalPath)
      if before.type != .file then
        return .error (.notRegularFile logicalPath)
      if before.byteSize.toNat > limits.maxFileBytes then
        return .error (.tooLarge logicalPath limits.maxFileBytes before.byteSize.toNat)
      match ← readBounded path limits.maxFileBytes with
      | .error () =>
          return .error (.unreadable logicalPath "read failed or exceeded the byte limit")
      | .ok bytes =>
          match ← metadataOrNone path with
          | none => return .error (.identityChanged logicalPath)
          | some after =>
              if after.type != .file || after.byteSize.toNat != bytes.size ||
                  after.modified != before.modified then
                return .error (.identityChanged logicalPath)
              match String.fromUTF8? bytes with
              | none => return .error (.invalidUtf8 logicalPath)
              | some text =>
                  return .ok (Core.Tla.SourceUnit.create .borrowedDirectory logicalPath text)

/-- Read one borrowed module file whose logical name is a canonical
`<ModuleName>.tla` reference. -/
private def borrowedSourceUnit (rootDir : System.FilePath)
    (limits : SourceProviderLimits) (moduleName : Core.Tla.ModuleName)
    (logicalPath : String) :
    IO (Except SourceReadError Core.Tla.SourceUnit) := do
  if !ModuleRef.validLogicalPath logicalPath then
    return .error (.invalidReference logicalPath "expected a canonical bare .tla file name")
  readSourceFile (rootDir / logicalPath) limits logicalPath (.notFound moduleName)

/-- Read one borrowed root file by its bare logical `.tla` file name. The root
is read under `rootDir` with the borrowed-directory checks (regular file only,
bounded bytes, identity rechecked after the read, UTF-8 validated) but without
requiring the stem to be a valid module-name spelling. -/
def readRootFile (rootDir : System.FilePath) (logicalPath : String)
    (limits : SourceProviderLimits := {}) :
    IO (Except SourceReadError Core.Tla.SourceUnit) := do
  if !validRootFileName logicalPath then
    return .error (.invalidReference logicalPath "expected a bare .tla file name")
  readSourceFile (rootDir / logicalPath) limits logicalPath
    (.unreadable logicalPath "file does not exist")

/-- A provider over one pinned root directory. Dependencies resolve to sibling
`<Name>.tla` files; a name with no sibling file is reported as `notFound` so the
caller can consult the standard-module catalog. -/
def borrowedDirectory (rootDir : System.FilePath)
    (limits : SourceProviderLimits := {})
    (catalog : StandardModuleCatalog := StandardModuleCatalog.default) :
    SourceProvider :=
  { readRoot := fun ref => borrowedSourceUnit rootDir limits ref.moduleName ref.logicalPath
    readDependency := fun moduleName =>
      borrowedSourceUnit rootDir limits moduleName (moduleName.name ++ ".tla")
    resolveStandard := standardLookup catalog }

/-- A provider over a caller-supplied closed source map. No filesystem access
occurs, and a name that is absent from the map is reported as `notFound`. -/
def inline (sources : Array (Core.Tla.ModuleName × String))
    (catalog : StandardModuleCatalog := StandardModuleCatalog.default) :
    SourceProvider :=
  let lookup (moduleName : Core.Tla.ModuleName) :
      IO (Except SourceReadError Core.Tla.SourceUnit) :=
    match sources.find? (fun entry => entry.1 == moduleName) with
    | some (_, text) =>
        pure (.ok (Core.Tla.SourceUnit.create .inlineSourceMap
          (moduleName.name ++ ".tla") text))
    | none => pure (.error (.notFound moduleName))
  { readRoot := fun ref => lookup ref.moduleName
    readDependency := lookup
    resolveStandard := standardLookup catalog }

end SourceProvider

end Shell.Tla
