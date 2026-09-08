import Shell.Cli
import Shell.Version

/-!
# Main — dispatch (Layer 3)

The CLI surface itself lives in @Shell.Cli@ (parsers, server and
validate flows) so the gate can unit-test it without building an
executable around it.
-/

/-! ## dispatch -/

def main : IO UInt32 := do
  let args ← getArgsIO
  match args with
  | ["--version"] =>
      IO.println s!"Mirrors {Shell.Version.version}"
      return 0
  | "--serve" :: rest => serveCli rest
  | "--server" :: rest =>
      match parseServerOpts rest with
      | .error e => IO.eprintln e; return 2
      | .ok opts => serveOne opts
  | "validate" :: rest => validateCli rest
  | [] =>
      -- default mode: stdio mirror session (Haskell: run StdioTransport)
      let t ← Shell.Transport.stdio
      runLocalStdioSession t
      return 0
  | _ =>
      -- t27: unknown mode — print the full usage block instead of
      -- silently falling into the stdio session
      IO.eprintln "unknown mode; see usage below"
      IO.eprintln cliUsage
      return 2
