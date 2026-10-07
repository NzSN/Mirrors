import Shell.ModelInterface.Compiler
import Codec.ModelInterfaceMigrationJson

namespace Shell.ModelInterface.Migration

/-- No writes or effects beyond normal bounded input reads. -/
def compareLocks (oldPath newPath : String) :
    IO (Except Compiler.CompilerError Lean.Json) := do
  let old ← match ← Compiler.loadVerifiedLock oldPath with
    | .ok lock => pure lock
    | .error error => return .error error
  let new ← match ← Compiler.loadVerifiedLock newPath with
    | .ok lock => pure lock
    | .error error => return .error error
  return .ok (Codec.ModelInterfaceMigrationJson.encodeComparison old new)

end Shell.ModelInterface.Migration
