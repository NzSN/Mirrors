import Shell.ModelInterface.Compiler

/-! Fresh immutable directory publication. All content is supplied in memory;
the final visibility operation is one same-parent rename. The sibling lock
serializes cooperating publishers. This is not a power-loss durability claim. -/

namespace Shell.ModelInterface.Publication

open Compiler

private def failure (message : String) : Except CompilerError α :=
  .error { kind := .finding, message }
private def infrastructure (message : String) : Except CompilerError α :=
  .error { kind := .infrastructure, message }

private partial def chain (path : System.FilePath) : List System.FilePath :=
  match path.parent with
  | none => [path]
  | some parent => chain parent ++ [path]

private def metadata? (path : System.FilePath) : IO (Option IO.FS.Metadata) := do
  try return some (← path.symlinkMetadata)
  catch error =>
    match error with
    | .noFileOrDirectory .. => return none
    | _ => throw error

/-- Validate an existing root, including every ancestor, without following links. -/
def validateDirectory (path : String) : IO (Except CompilerError String) := do
  let p : System.FilePath := path
  if path.isEmpty || path.contains '\u0000' ||
      (!System.Platform.isWindows && path.contains '\\') ||
      p.components.any (fun c => c == "." || c == "..") then
    return failure s!"unsafe directory path: {path}"
  let cwd ← IO.currentDir
  let absolute := (if p.isAbsolute then p else cwd / p).normalize
  try
    for item in chain absolute do
      let some metadata ← metadata? item
        | return failure s!"directory does not exist: {item}"
      if metadata.type != .dir then
        return failure s!"directory traverses a link or non-directory: {item}"
    let real ← IO.FS.realPath absolute
    if real.normalize != absolute then return failure s!"directory has an alias: {path}"
    return .ok absolute.toString
  catch error => return infrastructure s!"cannot inspect directory {path}: {error}"

private def safeFilename (name : String) : Bool :=
  !name.isEmpty && name != "." && name != ".." &&
    !name.contains '/' && !name.contains '\\' && !name.contains ':' &&
    !name.contains '\u0000' && !name.endsWith "." && !name.endsWith " "

/-- Bounded read of one ordinary direct child. No path segments or links. -/
def readFile (directory name : String) (limit : Nat) : IO (Except CompilerError ByteArray) := do
  if !safeFilename name then return failure s!"unsafe publication filename: {name}"
  let root ← match ← validateDirectory directory with
    | .ok value => pure value
    | .error error => return .error error
  let path := (root : System.FilePath) / name
  try
    let some metadata ← metadata? path | return failure s!"missing publication file: {name}"
    if metadata.type != .file then return failure s!"publication member is not a regular file: {name}"
    if metadata.byteSize > limit.toUInt64 then return failure s!"publication file exceeds byte limit: {name}"
    let handle ← IO.FS.Handle.mk path .read
    let mut bytes := ByteArray.empty
    repeat
      let chunk ← handle.read (min 65536 (limit + 1 - bytes.size)).toUSize
      if chunk.isEmpty then break
      bytes := bytes.append chunk
      if bytes.size > limit then return failure s!"publication file exceeds byte limit: {name}"
    return .ok bytes
  catch error => return infrastructure s!"cannot read publication file {name}: {error}"

private def removeOwnedFile (path : System.FilePath) : IO Unit := do
  match ← metadata? path with
  | none => pure ()
  | some metadata =>
      if metadata.type != .file then throw (IO.userError s!"owned file changed type: {path}")
      IO.FS.removeFile path

/-- Publish flat files into a new directory. The parent must already exist and
be caller-controlled. Concurrent publishers must honor the sibling lock; the
check/rename boundary does not defend against uncoordinated parent mutation.
`failAfterWrites` is a deterministic caught-failure test seam, never a CLI flag. -/
def publishDirectory (destination : String) (files : List (String × ByteArray))
    (failAfterWrites : Option Nat := none) : IO (Except CompilerError Unit) := do
  if files.isEmpty || !files.all (fun f => safeFilename f.1) ||
      !(Core.ModelInterface.duplicateStrings (files.map (fun f => f.1.toLower))).isEmpty then
    return failure "publication filenames are empty, unsafe, or collide"
  let path : System.FilePath := destination
  let some filename := path.fileName | return failure "publication destination has no filename"
  if !safeFilename filename || path.components.any (fun c => c == "." || c == "..") then
    return failure "unsafe publication destination"
  let parent := path.parent.getD "."
  -- A bare relative destination has the current directory as its parent.
  let parent ← if parent.toString == "." then pure (← IO.currentDir).toString else pure parent.toString
  let root ← match ← validateDirectory parent with
    | .ok value => pure value
    | .error error => return .error error
  let target := (root : System.FilePath) / filename
  let lock := (root : System.FilePath) / (filename ++ ".model-interface-directory.lock")
  let nonce ← IO.monoNanosNow
  let stage := (root : System.FilePath) / s!".{filename}.model-interface-stage-{nonce}"
  -- The lock is exclusive; failed acquisition never cleans another owner's lock.
  let ownedLock ← IO.mkRef false
  try
    let handle ← IO.FS.Handle.mk lock .writeNew
    ownedLock.set true
    handle.write "mirrors-immutable-directory/v1\n".toUTF8
    handle.flush
  catch error =>
    if ← ownedLock.get then
      try removeOwnedFile lock
      catch cleanupError =>
        return infrastructure s!"publication lock initialization failed ({error}); cleanup failed ({cleanupError})"
      return infrastructure s!"publication lock initialization failed: {error}"
    return failure s!"publication destination is locked: {error}"
  let ownedStage ← IO.mkRef false
  let stagedFiles ← IO.mkRef ([] : List String)
  let outcome ← try
    if (← metadata? target).isSome then
      pure (failure s!"refusing to replace existing publication: {target}")
    else
      IO.FS.createDir stage
      ownedStage.set true
      if failAfterWrites == some 0 then throw (IO.userError "injected staging failure")
      for (name, bytes) in files do
        -- Record ownership immediately after exclusive create, before write.
        let handle ← IO.FS.Handle.mk (stage / name) .writeNew
        stagedFiles.modify (name :: ·)
        handle.write bytes
        handle.flush
        if failAfterWrites == some (← stagedFiles.get).length then
          throw (IO.userError "injected staging failure")
      if (← metadata? target).isSome then
        throw (IO.userError "publication destination appeared during staging")
      -- Recheck ancestors before the visibility operation.
      match ← validateDirectory root with
      | .error error => throw (IO.userError error.message)
      | .ok _ => pure ()
      IO.FS.rename stage target
      ownedStage.set false
      pure (.ok ())
  catch error => pure (infrastructure s!"immutable publication failed: {error}")
  let mut cleanupErrors : List String := []
  if ← ownedStage.get then
    try
      let some metadata ← metadata? stage | throw (IO.userError "owned staging directory disappeared")
      if metadata.type != .dir then throw (IO.userError "owned staging directory changed type")
      for name in ← stagedFiles.get do removeOwnedFile (stage / name)
      IO.FS.removeDir stage
    catch error => cleanupErrors := cleanupErrors ++ [toString error]
  try removeOwnedFile lock
  catch error => cleanupErrors := cleanupErrors ++ [toString error]
  if !cleanupErrors.isEmpty then
    return infrastructure s!"publication cleanup failed: {cleanupErrors}"
  return outcome

end Shell.ModelInterface.Publication
