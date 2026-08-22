import Codec.Json
import Core.Value
import Lean

/-!
# Shell.Apalache.SpecSource — spec materialization (Layer 3, design 5.4)

Port of the Haskell @Apalache.SpecSource@: inline spec sources are
materialized as @.tla@ files in a mirror-owned temp directory (released
by deleting the dir); a @Borrowed@ spec uses the config's own
@specPath@ as-is and is never deleted. Also provides the per-session
temp dir (apalache's run dir / cwd).

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

/-- Parse the module name from a spec source: the first
@----- MODULE Name -----@ header line (Haskell @moduleName@). -/
def moduleName (src : String) : Except String String :=
  match (src.splitOn "\n").filter isModuleLine with
  | [] => .error "no MODULE header found in spec source"
  | l :: _ =>
      match l.splitOn " " |>.filter (· != "") with
      | dashes :: kw :: name :: rest =>
          if allDashes dashes && kw == "MODULE" && !allDashes name
              && rest.all allDashes then
            .ok name
          else
            .error s!"malformed MODULE header: {l}"
      | _ => .error s!"malformed MODULE header: {l}"

/-! ## Spec materialization -/

private initialize dirCounter : IO.Ref Nat ← IO.mkRef 0

private def tempBase : IO String := do
  match ← IO.getEnv "TMPDIR" with
  | some t => pure t
  | none => pure "/tmp"

/-- A fresh spec temp dir (Haskell @freshSpecDir@): retry with a new
counter on collision. -/
private partial def freshSpecDir : IO String := do
  let tmp ← tempBase
  let n ← dirCounter.modifyGet (fun m => (m, m + 1))
  let dir := tmp ++ "/modelmirrors-spec-" ++ toString n
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

/-! ## Session dirs -/

/-- Create a fresh per-session temp directory (Haskell
@freshSessionDir@): the dir apalache uses as its run dir / cwd. -/
def freshSessionDir : IO String := do
  let tmp ← tempBase
  let n ← dirCounter.modifyGet (fun m => (m, m + 1))
  let ms ← IO.monoMsNow
  let dir := tmp ++ "/modelmirrors-session-" ++ toString n ++ "-" ++ toString ms
  try IO.FS.createDir dir
  catch _ => IO.FS.createDir (dir ++ "-x")
  return dir

/-- Remove a session dir (total, recursive). -/
def removeSessionDir (path : String) : IO Unit := removeDirRecursive path

end Shell.Apalache.SpecSource