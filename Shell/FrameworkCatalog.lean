import Codec.FrameworkCatalog

/-! Filesystem orchestration for the read-only validator and deterministic renderer. -/

namespace Shell.FrameworkCatalog

open Core.FrameworkCatalog Codec.FrameworkCatalog

private partial def readBoundedAux (handle : IO.FS.Handle) (limit : Nat)
    (accumulator : ByteArray) : IO (Except Unit ByteArray) := do
  if accumulator.size > limit then return .error ()
  let remaining := limit + 1 - accumulator.size
  let chunk ← handle.read (min 65536 remaining).toUSize
  if chunk.isEmpty then return .ok accumulator
  readBoundedAux handle limit (accumulator.append chunk)

/-- Read at most `limit` bytes plus one refusal byte. Callers receive bytes only
when the complete file fits; no truncated prefix is returned. -/
def readBounded (path : System.FilePath) (limit : Nat) : IO (Except String ByteArray) := do
  try
    let handle ← IO.FS.Handle.mk path .read
    match ← readBoundedAux handle limit ByteArray.empty with
    | .ok bytes => return .ok bytes
    | .error _ => return .error s!"file exceeds {limit}-byte limit: {path}"
  catch error => return .error s!"cannot read {path}: {error}"

def load (path : System.FilePath) : IO (Except (List ValidationError) Decoded) := do
  match ← readBounded path (4 * 1024 * 1024) with
  | .error message => return .error [ValidationError.mk "E-FCAT-BOUND-001" "$" message]
  | .ok raw =>
      match String.fromUTF8? raw with
      | none => return .error [ValidationError.mk "E-FCAT-SCHEMA-001" "$"
          "catalog is not valid UTF-8"]
      | some text => return decodeString text

def formatError (error : ValidationError) : String :=
  s!"{error.code} {error.path}: {error.message}"

def formatErrors (errors : List ValidationError) : String :=
  String.intercalate "\n" (errors.map formatError)

def compactOutput (decoded : Decoded) : String := decoded.canonical ++ "\n"

def markdownOutput (decoded : Decoded) : String := renderMarkdown decoded.catalog

private def beginMarker : String := "<!-- BEGIN GENERATED FRAMEWORK SUPPORT -->"
private def endMarker : String := "<!-- END GENERATED FRAMEWORK SUPPORT -->"

def mergeMarkdown (existing generated : String) : Except String String :=
  if existing.isEmpty then .ok generated
  else
    match existing.splitOn beginMarker with
    | [before, remainder] =>
        match remainder.splitOn endMarker with
        | [_oldGenerated, after] =>
            let after := if generated.endsWith "\n" && after.startsWith "\n" then
              after.drop 1 else after
            .ok (before ++ generated ++ after)
        | _ => .error "generated Markdown end marker is missing or duplicated"
    | _ => .error "generated Markdown begin marker is missing or duplicated"

private def checkBytes (path : System.FilePath) (expected : String) : IO (Except String Unit) := do
  if !(← path.pathExists) then return .error s!"missing rendered output: {path}"
  let actual ← IO.FS.readFile path
  if actual == expected then return .ok ()
  return .error s!"rendered output is stale: {path}"

def render (decoded : Decoded) (jsonOut markdownOut : System.FilePath)
    (checkOnly : Bool) : IO (Except String Unit) := do
  let json := compactOutput decoded
  let existingMarkdown ← if ← markdownOut.pathExists then IO.FS.readFile markdownOut else pure ""
  let markdown ← match mergeMarkdown existingMarkdown (markdownOutput decoded) with
    | .ok value => pure value
    | .error message => return .error message
  if checkOnly then
    match ← checkBytes jsonOut json with
    | .error message => return .error message
    | .ok _ => checkBytes markdownOut markdown
  else
    IO.FS.writeFile jsonOut json
    IO.FS.writeFile markdownOut markdown
    return .ok ()

end Shell.FrameworkCatalog
