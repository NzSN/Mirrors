import Shell.Cli

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
  | "--serve" :: rest => serveCli rest
  | "--server" :: rest =>
      match parseServerOpts rest with
      | .error e => IO.eprintln e; return 2
      | .ok opts => serveOne opts
  | "validate" :: rest => validateCli rest
  | _ =>
      -- default mode: stdio mirror session (Haskell: run StdioTransport)
      let t ← Shell.Transport.stdio
      Shell.Mirror.run t Shell.Apalache.syncOracles
      return 0