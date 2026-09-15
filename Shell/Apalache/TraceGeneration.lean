import Codec.Json
import Core.Value
import Lean

/-!
# Shell.Apalache.TraceGeneration

Private shell facts and resource-ordering helpers for file-backed Apalache
trace generation. These types do not enter `Codec` or the public protocol.
-/

namespace Shell.Apalache

/-- A generated wire result together with whether its paths name copies
outside the owned Apalache session directory. Inline values have already been
decoded and therefore survive cleanup regardless of this flag. -/
structure GeneratedTraceDelivery where
  result : Codec.TraceGenResult
  pathsDurable : Bool
deriving Repr

/-- Stable, bounded evidence for failures from the two owned cleanup steps.
Physical paths and exception strings are intentionally omitted: the labels
identify the failed ownership boundary without creating an unbounded wire
diagnostic. -/
private def cleanupFailureEvidence (releaseFailed removeFailed : Bool) : String :=
  match releaseFailed, removeFailed with
  | false, false => ""
  | true, false => "spec release"
  | false, true => "session directory removal"
  | true, true => "spec release; session directory removal"

private def cleanupFailed (cleanup : IO Unit) : IO Bool := do
  try
    cleanup
    return false
  catch _ =>
    return true

/-- Run one trace-generation operation and then both independent cleanup
steps while retaining the primary operation error. The second cleanup is
always attempted even when the first throws. Cleanup evidence is attached as
a stable bounded suffix to a primary operation error; cleanup becomes primary
only after a successful operation. -/
def withTraceGenerationCleanup (operation : IO (Except String α))
    (releaseResource removeSession : IO Unit) : IO (Except String α) := do
  let result ← try operation catch error =>
    pure (.error s!"TRACE_GENERATION_IO_FAILED: {error}")
  let releaseFailed ← cleanupFailed releaseResource
  let removeFailed ← cleanupFailed removeSession
  let cleanupEvidence := cleanupFailureEvidence releaseFailed removeFailed
  match result with
  | .error primary =>
      if cleanupEvidence.isEmpty then
        return .error primary
      else
        return .error
          (primary ++ "\n[secondary cleanup failures: " ++ cleanupEvidence ++ "]")
  | .ok value =>
      if cleanupEvidence.isEmpty then
        return .ok value
      else
        return .error ("TRACE_GENERATION_CLEANUP_FAILED: " ++ cleanupEvidence)

private def decodeTraceValues (paths : List String) :
    IO (Except String (List Value)) := do
  try
    let mut values := []
    for path in paths do
      let text ← IO.FS.readFile path
      match Lean.Json.parse text with
      | .error _ => return .error "generated ITF trace is not valid JSON"
      | .ok json =>
          match Codec.decodeValue json with
          | .error _ => return .error "generated ITF trace has an invalid value"
          | .ok value => values := values ++ [value]
    return .ok values
  catch _ =>
    return .error "unable to read generated ITF trace"

private def pathWithin (parent child : System.FilePath) : Bool :=
  let parentText := parent.toString
  let childText := child.toString
  let separator := if System.Platform.isWindows then "\\" else "/"
  childText == parentText || childText.startsWith (parentText ++ separator)

/-- Copy, decode, and classify one generated trace-file result before the
owned session directory is removed. Any failed copy/read/decode rejects the
whole operation; it cannot become a successful partial trace set. -/
def prepareGeneratedTraceDelivery (runDir outDir : String)
    (paths : List String) (dest : Option String) :
    IO (Except String GeneratedTraceDelivery) := do
  try
    let (finalPaths, copied) ← match dest with
      | some destination =>
          if destination != "" && destination != outDir then
            IO.FS.createDirAll destination
            let copiedPaths ← paths.mapM (fun (path : String) => do
              let fileName := (path : System.FilePath).fileName.getD path
              let target := ((destination : System.FilePath) / fileName).toString
              let text ← IO.FS.readFile path
              IO.FS.writeFile target text
              pure target)
            pure (copiedPaths, true)
          else
            pure (paths, false)
      | none => pure (paths, false)
    match ← decodeTraceValues finalPaths with
    | .error error => return .error error
    | .ok contents =>
        let durable ← if copied then
          let owned ← IO.FS.realPath runDir
          let destination ← IO.FS.realPath (dest.getD "")
          pure (!pathWithin owned destination)
        else
          pure false
        return .ok {
          result := { itfTracePaths := finalPaths, itfTraces := contents }
          pathsDurable := durable
        }
  catch _ =>
    return .error "unable to copy generated ITF trace"

end Shell.Apalache
