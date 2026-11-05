import Ffi.Path

namespace Shell.FileSystem

/-- No-follow metadata for security-sensitive path checks. Lean 4.33's
Windows runtime reports file symlinks as ordinary files. Inspect native
reparse attributes first, including dangling links and junctions.
This is a path inspection, not protection against concurrent path mutation. -/
def symlinkMetadata (path : System.FilePath) : IO IO.FS.Metadata := do
  if System.Platform.isWindows then
    let status ← Ffi.pathReparseStatus path.toString
    if status == 1 then
      return {
        accessed := default
        modified := default
        byteSize := 0
        type := .symlink
        numLinks := 0 }
    if status == 3 then
      throw (IO.userError s!"cannot inspect native path attributes: {path}")
  path.symlinkMetadata

end Shell.FileSystem
