import Lean
def main (args : List String) : IO Unit := do
  for path in args do
    let p : System.FilePath := path
    let m ← p.symlinkMetadata
    IO.println s!"{path}: kind={repr m.type}, real={(← IO.FS.realPath p)}"
