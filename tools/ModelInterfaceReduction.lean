import Codec.ModelInterfaceReductionJson
import Shell.FrameworkCatalog

/-! Production validator for evaluator-owned domain-reduction requests. -/

open Core.ModelInterface

private def usage : String :=
  "Usage: model_interface_reduction validate CANDIDATE.json"

def main (arguments : List String) : IO UInt32 := do
  match arguments with
  | ["validate", path] =>
      try
        let raw ← match ← Shell.FrameworkCatalog.readBounded path 262144 with
          | .ok bytes => pure bytes
          | .error error =>
              IO.eprintln s!"reduction candidate unavailable: {error}"
              return 2
        match Codec.ModelInterfaceReductionJson.decodeAndValidate raw with
        | .error error =>
            IO.eprintln s!"reduction candidate refused: {error}"
            return 2
        | .ok validated =>
            IO.println <| Lean.Json.compress <| Lean.Json.mkObj [
              ("schema", .str "mirrors.reduction-candidate-validation/v1"),
              ("status", .str "accepted"),
              ("profile", .str validated.profile),
              ("domainVersion", .str validated.domainVersion)]
            return 0
      catch error =>
        IO.eprintln s!"reduction candidate unavailable: {error}"
        return 2
  | _ =>
      IO.eprintln usage
      return 2
