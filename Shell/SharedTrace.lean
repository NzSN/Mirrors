import Shell.Mirror.Session
import Core.ModelInterface.Sha256

/-! Explicit file mapping for one synchronous, pinned remote trace capture.
The wire result remains bounded; independently bounded artifacts live in a
deployment-granted directory. This module never guesses a server path mapping. -/
namespace Shell.SharedTrace

structure Mapping where
  serverRoot : String
  localRoot : System.FilePath
  leaf : String
  deriving Repr

/-- Async jobs have no durable-file delivery contract. Malformed messages
remain the ordinary session decoder's responsibility. -/
def asyncDestinationRequested (line : String) : Bool :=
  match Codec.StrictJson.parseString line with
  | .error _ => false
  | .ok json => match Codec.decodeClient json with
    | .ok (.registerGenTracesAsync _ (some _) _ _) => true
    | _ => false

private def slash (s : String) : String := s.replace "\\" "/"

def serverRoot (s : String) : Except String String := do
  let s := (slash s).dropEndWhile (· == '/') |>.toString
  let chars := s.toList
  let absolute := s.startsWith "/" || match chars with
    | a :: ':' :: '/' :: _ => a.isAlpha
    | _ => false
  if !absolute || s.isEmpty || s.contains (Char.ofNat 0) then
    throw "shared server root must be an absolute path"
  if (s.splitOn "/").any (fun p => p == "." || p == "..") || s.contains ':' && !((chars.drop 1).head? == some ':') then
    throw "invalid shared server root"
  if s.contains '\n' || s.contains '\r' || s.contains '"' || s.contains '*' || s.contains '?' then
    throw "invalid shared server root"
  return s

def validLeaf (s : String) : Bool :=
  s.startsWith "capture-" && s.length > 8 && s.length ≤ 80 &&
    s.toList.all (fun c => c.toNat < 128 && (c.isAlphanum || c == '-'))

def Mapping.destination (m : Mapping) : String := m.serverRoot ++ "/" ++ m.leaf

private partial def ancestors (p : System.FilePath) : List System.FilePath :=
  match p.parent with
  | none => [p]
  | some parent => ancestors parent ++ [p]

/-- Existing directory roots must have no symlink or non-directory prefix. -/
def ordinaryRoot (root : System.FilePath) : IO System.FilePath := do
  let cwd ← IO.currentDir
  let path := (if root.isAbsolute then root else cwd / root).normalize
  for prefixPath in ancestors path do
    let metadata ← prefixPath.symlinkMetadata
    if metadata.type != .dir then throw (IO.userError "shared root has a non-directory or symlink prefix")
  return ← IO.FS.realPath path

/-- Atomically reserve a new direct child of the operator's server root. -/
def reserveDestination (root : System.FilePath) (destination : Option String) : IO Unit := do
  let some destination := destination | throw (IO.userError "shared trace delivery requires destPath")
  let path : System.FilePath := destination
  if !path.isAbsolute then throw (IO.userError "shared trace destination must be absolute")
  let path := path.normalize
  let root ← ordinaryRoot root
  let some parent := path.parent | throw (IO.userError "invalid shared trace destination")
  if parent.normalize != root.normalize || !validLeaf (path.fileName.getD "") then
    throw (IO.userError "shared trace destination must be a new capture child of the configured root")
  IO.FS.createDir path

/-- Interpret a reply only inside the exact destination sent in this request. -/
def Mapping.filename (m : Mapping) (path : String) : Except String String := do
  let path := slash path
  let pathPrefix := m.destination ++ "/"
  -- Windows roots are case-insensitive; filename bytes remain unchanged.
  let pathMatches := if m.serverRoot.startsWith "/" then path.startsWith pathPrefix
    else path.toLower.startsWith pathPrefix.toLower
  if !pathMatches then throw "shared trace reply escaped the requested destination"
  let name := (path.drop pathPrefix.length).toString
  if name.isEmpty || name.startsWith "." || !name.endsWith ".itf.json" ||
      !name.toList.all (fun c => c.toNat < 128 && (c.isAlphanum || c == '-' || c == '_' || c == '.')) then
    throw "invalid shared trace artifact filename"
  return name

private partial def boundedRead (h : IO.FS.Handle) (limit : Nat)
    (bytes : ByteArray := ByteArray.empty) : IO ByteArray := do
  if bytes.size > limit then throw (IO.userError "shared trace artifact exceeds its byte budget")
  let chunk ← h.read (min 65536 (limit + 1 - bytes.size)).toUSize
  if chunk.isEmpty then return bytes
  boundedRead h limit (bytes.append chunk)

def load (mapping : Mapping) (paths : List String) (maximum : Nat) :
    IO (Except String (List Lean.Json × Lean.Json)) := do
  try
    if paths.isEmpty || paths.length > maximum then return .error "invalid shared trace artifact count"
    let root ← ordinaryRoot mapping.localRoot
    let directory := root / mapping.leaf
    let _ ← ordinaryRoot directory
    let mut seen : List String := []
    let mut total := 0
    let mut traces : List Lean.Json := []
    let mut origins : List Lean.Json := []
    for serverPath in paths do
      let name ← match mapping.filename serverPath with
        | .error e => return .error (toString e)
        | .ok name => pure name
      if seen.contains name.toLower then return .error "duplicate shared trace artifact"
      seen := name.toLower :: seen
      let path := directory / name
      let before ← path.symlinkMetadata
      if before.type != .file then return .error "shared trace artifact is not an ordinary file"
      let limit := min Shell.Mirror.maxItfTraceArtifactBytes (64 * 1024 * 1024 - total)
      if before.byteSize.toNat > limit then return .error "shared trace artifact exceeds its byte budget"
      let h ← IO.FS.Handle.mk path .read
      let bytes ← boundedRead h limit
      let after ← path.symlinkMetadata
      let _ ← ordinaryRoot directory
      if after.type != .file || before.byteSize != after.byteSize || before.modified != after.modified || bytes.size != after.byteSize.toNat then
        return .error "shared trace artifact changed during capture"
      total := total + bytes.size
      let json ← match Codec.StrictJson.parseBytes bytes Shell.Mirror.itfTraceArtifactLimits with
        | .error e => return .error (toString e)
        | .ok json => pure json
      match Shell.Mirror.parseItfTrace json with
      | .error e => return .error s!"invalid shared ITF trace: {e}"
      | .ok trace => if trace.traceStates.isEmpty then return .error "empty shared ITF trace"
      traces := traces ++ [json]
      origins := origins ++ [Lean.Json.mkObj [
        ("serverPath", .str serverPath), ("bytes", .num bytes.size),
        ("sha256", .str (Core.ModelInterface.Sha256.digestHex bytes))]]
    return .ok (traces, Lean.Json.mkObj [
      ("kind", .str "explicit-shared-filesystem"),
      ("serverRoot", .str mapping.serverRoot), ("destination", .str mapping.destination),
      ("artifacts", .arr origins.toArray)])
  catch _ => return .error "unable to capture confined shared trace artifacts"

end Shell.SharedTrace
