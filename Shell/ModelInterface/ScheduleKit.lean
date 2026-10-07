import Shell.ModelInterface.Emit.ScheduleKit

namespace Shell.ModelInterface.ScheduleKit
open Compiler

private def load (lockPath mappingPath target : String) :
    IO (Except CompilerError Emit.TypeScript.GeneratedTree) := do
  let lock ← match ← loadVerifiedLock lockPath with
    | .ok lock => pure lock
    | .error error => return .error error
  let raw ← match ← readBytesWithLimit mappingPath 1_048_576 with
    | .ok raw => pure raw
    | .error error => return .error error
  let plan ← match Codec.ModelInterfaceScheduleKitJson.parse raw with
    | .ok plan => pure plan
    | .error message => return .error { kind := .finding, message }
  return Emit.ScheduleKit.emit lock plan target

def generate (lock mapping target out : String) : IO (Except CompilerError (List String)) := do
  let tree ← match ← load lock mapping target with
    | .ok tree => pure tree
    | .error error => return .error error
  writeGeneratedTree out tree

def check (lock mapping target out : String) : IO (Except CompilerError CheckReport) := do
  let tree ← match ← load lock mapping target with
    | .ok tree => pure tree
    | .error error => return .error error
  checkGeneratedTree out tree

end Shell.ModelInterface.ScheduleKit
