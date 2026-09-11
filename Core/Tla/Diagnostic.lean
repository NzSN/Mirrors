import Core.Tla.Source

/-!
# TLA+ frontend diagnostics (Core/Tla/Diagnostic.lean)

Bounded structured diagnostics for the general TLA+ frontend
(`Docs/model-interface-compiler/tla-frontend-design.md`, §20 "Diagnostics" and
§21 "Resource and security limits").

A diagnostic is data: rendering to text or JSON happens in a separate shell
step, so both renderings always carry the same facts. Locations are logical:
the module name (when known), the logical path, and a source range. Physical
paths are never part of this type.

`DiagnosticBuffer` enforces the count and byte budgets. It drops diagnostics
once a budget is exhausted and counts the dropped items, so a failure result
stays bounded and deterministic; callers that must report the truncation push a
single forced notice with `DiagnosticBuffer.pushForced` (see `Core/Tla/Lexer`).
-/

namespace Core.Tla

/-- Diagnostic severity. A result that carries any `error` diagnostic cannot
enter successful elaboration or compilation. -/
inductive Severity where
  | error
  | warning
  | info
  deriving Repr, BEq, DecidableEq

namespace Severity

/-- `true` for `Severity.error`. -/
def isError : Severity → Bool
  | .error => true
  | .warning => false
  | .info => false

/-- Stable lowercase rendering used by inspection output. -/
def toString : Severity → String
  | .error => "error"
  | .warning => "warning"
  | .info => "info"

end Severity

/-- Frontend stage that produced a diagnostic. -/
inductive DiagnosticStage where
  | lex
  | parse
  | moduleGraph
  | nameResolution
  | substitution
  | level
  | sourceEvidence
  deriving Repr, BEq, DecidableEq

namespace DiagnosticStage

/-- Stable rendering used by inspection output and tests. -/
def toString : DiagnosticStage → String
  | .lex => "lex"
  | .parse => "parse"
  | .moduleGraph => "moduleGraph"
  | .nameResolution => "nameResolution"
  | .substitution => "substitution"
  | .level => "level"
  | .sourceEvidence => "sourceEvidence"

end DiagnosticStage

/-- A logical source location. `moduleName` is absent before the parser reads a
module header; `logicalPath` is a module-relative name, never a physical path. -/
structure SourceLocation where
  moduleName : Option ModuleName
  logicalPath : String
  range : SourceRange
  deriving Repr, BEq, DecidableEq

namespace SourceLocation

/-- Location of a range inside a captured unit, before the module name is known. -/
def ofUnit (unit : SourceUnit) (range : SourceRange) : SourceLocation :=
  { moduleName := none, logicalPath := unit.logicalPath, range }

/-- Attach the module name once the header has been read. -/
def withModule (location : SourceLocation) (moduleName : ModuleName) :
    SourceLocation :=
  { location with moduleName := some moduleName }

end SourceLocation

/-- A secondary location with its own explanation. -/
structure RelatedLocation where
  message : String
  location : SourceLocation
  deriving Repr, BEq, DecidableEq

/-- Bounded, structured frontend diagnostic. -/
structure Diagnostic where
  code : String
  severity : Severity
  stage : DiagnosticStage
  message : String
  primary : SourceLocation
  related : Array RelatedLocation
  arguments : Array (String × String)
  deriving Repr, BEq

namespace Diagnostic

/-- An error diagnostic with no secondary locations or arguments. -/
def error (code : String) (stage : DiagnosticStage) (message : String)
    (primary : SourceLocation) : Diagnostic :=
  { code, severity := .error, stage, message, primary, related := #[], arguments := #[] }

/-- A warning diagnostic. Warnings never make a slice fail by themselves. -/
def warning (code : String) (stage : DiagnosticStage) (message : String)
    (primary : SourceLocation) : Diagnostic :=
  { code, severity := .warning, stage, message, primary, related := #[], arguments := #[] }

/-- Add a machine-readable argument. Arguments are part of the diagnostic
identity and of its byte accounting. -/
def withArgument (diagnostic : Diagnostic) (name value : String) : Diagnostic :=
  { diagnostic with arguments := diagnostic.arguments.push (name, value) }

/-- Add a secondary location with its own explanation. -/
def withRelated (diagnostic : Diagnostic) (message : String)
    (location : SourceLocation) : Diagnostic :=
  { diagnostic with related := diagnostic.related.push ⟨message, location⟩ }

/-- `true` when this diagnostic is an error. -/
def hasErrorSeverity (diagnostic : Diagnostic) : Bool :=
  diagnostic.severity.isError

/-- Deterministic byte accounting for the `maxDiagnosticBytes` budget: UTF-8
length of the code, message, argument names and values, related messages, and
the primary and related logical paths. Source text is never measured, so the
accounting stays independent of the rendered source excerpt. -/
def byteWeight (diagnostic : Diagnostic) : Nat :=
  let locationWeight (location : SourceLocation) : Nat :=
    location.logicalPath.toUTF8.size
  let relatedWeight (related : RelatedLocation) : Nat :=
    related.message.toUTF8.size + locationWeight related.location
  let argumentWeight (argument : String × String) : Nat :=
    argument.1.toUTF8.size + argument.2.toUTF8.size
  diagnostic.code.toUTF8.size + diagnostic.message.toUTF8.size +
    locationWeight diagnostic.primary +
    diagnostic.related.foldl (fun total related => total + relatedWeight related) 0 +
    diagnostic.arguments.foldl (fun total argument => total + argumentWeight argument) 0

end Diagnostic

/-- Count and byte budgets for an accumulation. -/
structure DiagnosticLimits where
  maxCount : Nat
  maxBytes : Nat
  deriving Repr, BEq, DecidableEq

namespace DiagnosticLimits

/-- Defaults from the frontend limits design (`maxDiagnostics`,
`maxDiagnosticBytes`). -/
def default : DiagnosticLimits := { maxCount := 256, maxBytes := 1024 * 1024 }

end DiagnosticLimits

/-- A bounded diagnostic accumulation. `dropped` counts diagnostics that a
budget refused, which is how callers detect truncation. -/
structure DiagnosticBuffer where
  diagnostics : Array Diagnostic := #[]
  byteWeight : Nat := 0
  dropped : Nat := 0
  deriving Repr

namespace DiagnosticBuffer

/-- The empty buffer. -/
def empty : DiagnosticBuffer := {}

/-- `true` when no further diagnostic fits the budgets. -/
def isFull (limits : DiagnosticLimits) (buffer : DiagnosticBuffer) : Bool :=
  buffer.diagnostics.size ≥ limits.maxCount ||
    buffer.byteWeight + 1 > limits.maxBytes

/-- Append a diagnostic when the budgets allow it; otherwise count it as
dropped. The check is deterministic: it depends only on the budgets and the
already accumulated diagnostics. -/
def push (limits : DiagnosticLimits) (buffer : DiagnosticBuffer)
    (diagnostic : Diagnostic) : DiagnosticBuffer :=
  let weight := diagnostic.byteWeight
  if buffer.diagnostics.size ≥ limits.maxCount ||
      buffer.byteWeight + weight > limits.maxBytes then
    { buffer with dropped := buffer.dropped + 1 }
  else
    { diagnostics := buffer.diagnostics.push diagnostic
      byteWeight := buffer.byteWeight + weight
      dropped := buffer.dropped }

/-- Append a diagnostic without consulting the budgets. Only truncation notices
use this path; they are bounded by one diagnostic per accumulation. -/
def pushForced (buffer : DiagnosticBuffer) (diagnostic : Diagnostic) :
    DiagnosticBuffer :=
  { diagnostics := buffer.diagnostics.push diagnostic
    byteWeight := buffer.byteWeight + diagnostic.byteWeight
    dropped := buffer.dropped }

/-- `true` when at least one diagnostic was dropped. -/
def truncated (buffer : DiagnosticBuffer) : Bool := buffer.dropped > 0

end DiagnosticBuffer

end Core.Tla
