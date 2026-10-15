import MirrorLean
open MirrorLean Lean

def main (args : List String) : IO Unit := do
  let dir := args.headD "fixtures"
  for stem in ["ControlRoot", "MarkerRoot"] do
    match ← specFromFiles (System.FilePath.mk (dir ++ "/" ++ stem ++ ".tla")) with
    | .error error =>
        IO.println (Json.mkObj [("case", .str stem), ("ok", .bool false),
          ("error", .str error.toString)]).compress
    | .ok spec =>
        IO.println (Json.mkObj [("case", .str stem), ("ok", .bool true),
          ("sourceCount", toJson spec.sources.size),
          ("dependencyPresent", .bool (spec.sources.any (fun source => source.contains "MODULE Dep"))) ]).compress
  -- Peripheral API parity observation: these inputs are request configs,
  -- not inbound mirror replies and not the typed client's own emission.
  for (label, text) in [("optional absent", "{\"specPath\":\"M.tla\"}"),
      ("optional null", "{\"specPath\":\"M.tla\",\"constInit\":null}")] do
    let decoded := (Json.parse text).bind ApalacheConfig.ofJson?
    IO.println (Json.mkObj [("case", .str label), ("decoded", .bool decoded.isOk)]).compress
