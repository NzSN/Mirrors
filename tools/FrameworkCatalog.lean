import Shell.FrameworkCatalog

namespace FrameworkCatalogCli

def usage : String := String.intercalate "\n" [
  "usage:",
  "  framework_catalog validate CATALOG",
  "  framework_catalog render --catalog CATALOG [--json-out FILE] [--markdown-out FILE] [--check]",
  "  defaults: catalog/framework-catalog.compact.json and Docs/framework-map.md"
]

private structure RenderOptions where
  catalog : Option String := none
  jsonOut : Option String := none
  markdownOut : Option String := none
  check : Bool := false

private def parseRender : List String → Except String RenderOptions
  | [] => .ok {}
  | "--check" :: rest => do
      let parsed ← parseRender rest
      if parsed.check then throw "duplicate option: --check"
      return { parsed with check := true }
  | "--catalog" :: value :: rest => do
      let parsed ← parseRender rest
      if parsed.catalog.isSome then throw "duplicate option: --catalog"
      return { parsed with catalog := some value }
  | "--json-out" :: value :: rest => do
      let parsed ← parseRender rest
      if parsed.jsonOut.isSome then throw "duplicate option: --json-out"
      return { parsed with jsonOut := some value }
  | "--markdown-out" :: value :: rest => do
      let parsed ← parseRender rest
      if parsed.markdownOut.isSome then throw "duplicate option: --markdown-out"
      return { parsed with markdownOut := some value }
  | option :: _ => .error s!"unknown or incomplete option: {option}"

private def requireOption (name : String) : Option String → Except String String
  | some value => .ok value
  | none => .error s!"missing required option: {name}"

private def reportLoad (path : String) : IO (Except String Codec.FrameworkCatalog.Decoded) := do
  try
    match ← Shell.FrameworkCatalog.load path with
    | .ok decoded => return .ok decoded
    | .error errors => return .error (Shell.FrameworkCatalog.formatErrors errors)
  catch problem => return .error s!"cannot read catalog {path}: {problem}"

def run (arguments : List String) : IO UInt32 := do
  match arguments with
  | ["validate", path] =>
      match ← reportLoad path with
      | .error message => IO.eprintln message; return 1
      | .ok decoded =>
          IO.println s!"framework catalog valid: {path} sha256={decoded.selectionDigest}"
          return 0
  | "render" :: rest =>
      match parseRender rest with
      | .error message => IO.eprintln message; IO.eprintln usage; return 2
      | .ok options =>
          let required := do
            return (← requireOption "--catalog" options.catalog,
              options.jsonOut.getD "catalog/framework-catalog.compact.json",
              options.markdownOut.getD "Docs/framework-map.md")
          match required with
          | .error message => IO.eprintln message; IO.eprintln usage; return 2
          | .ok (catalogPath, jsonOut, markdownOut) =>
              match ← reportLoad catalogPath with
              | .error message => IO.eprintln message; return 1
              | .ok decoded =>
                  match ← Shell.FrameworkCatalog.render decoded jsonOut markdownOut options.check with
                  | .error message => IO.eprintln message; return 1
                  | .ok _ =>
                      IO.println (if options.check then "framework catalog outputs current"
                        else "framework catalog rendered")
                      return 0
  | _ => IO.eprintln usage; return 2

end FrameworkCatalogCli

def main (arguments : List String) : IO UInt32 := FrameworkCatalogCli.run arguments
