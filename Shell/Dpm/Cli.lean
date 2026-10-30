import Codec.Dpm
import Codec.DpmEvidence
import Codec.DpmSyncComparison
import Shell.FrameworkCatalog
import Shell.Dpm.HostIdentity
import Core.ModelInterface.Sha256

namespace Shell.Dpm

def main (args : List String) : IO UInt32 := do
  try
    match args with
    | ["_sync-check", path] =>
      let raw ← match ← Shell.FrameworkCatalog.readBounded path (1024*1024) with
        | .ok bytes => pure bytes
        | .error e => throw (IO.userError e)
      match Codec.DpmSyncComparison.check raw with
      | .error e => IO.eprintln e; return 2
      | .ok result => IO.println result.compress; return 0
    | ["_value-check", path] =>
      let raw ← match ← Shell.FrameworkCatalog.readBounded path (32*1024*1024) with
        | .ok bytes => pure bytes
        | .error e => throw (IO.userError e)
      match Codec.DpmEvidence.check raw with
      | .error e => IO.eprintln e; return 2
      | .ok result => IO.println result.compress; return 0
    | ["_plan", path] =>
      let raw ← match ← Shell.FrameworkCatalog.readBounded path (4*1024*1024) with
        | .ok bytes => pure bytes
        | .error e => throw (IO.userError e)
      match Codec.Dpm.decode raw with
      | .error e => IO.eprintln e; return 2
      | .ok (_, candidates) => IO.println (Codec.Dpm.plan candidates).compress; return 0
    | _ =>
      let executable ← IO.appPath
      let installed := executable.parent.getD "." / ".." / "share" / "mirrors-dpm" / "cli.py"
      let source := executable.parent.getD "." / ".." / ".." / ".." / "tools" / "deterministic-scheduling" / "cli.py"
      let driver ← if ← installed.pathExists then pure installed else pure source
      unless ← driver.pathExists do throw (IO.userError "packaged DPM host driver is missing")
      for (name, digest) in HostIdentity.files do
        let file := driver.parent.getD "." / name
        let raw ← IO.FS.readBinFile file
        unless raw.size ≤ 1048576 && Core.ModelInterface.Sha256.digestHex raw == digest do
          throw (IO.userError s!"DPM host artifact differs: {name}")
      let python ← IO.FS.readBinFile HostIdentity.interpreter
      unless Core.ModelInterface.Sha256.digestHex python == HostIdentity.interpreterSha256 do
        throw (IO.userError "DPM Python runtime differs")
      let child ← IO.Process.spawn
        { cmd := HostIdentity.interpreter
          args := #["-I", "-S", "-B", driver.toString, "--host-identities",
            (Lean.Json.mkObj (HostIdentity.files.map fun (name, digest) =>
              (name, Lean.Json.str digest))).compress, "--policy", executable.toString] ++ args.toArray }
      child.wait
  catch e => IO.eprintln s!"DPM operation refused: {e}"; return 2

end Shell.Dpm
