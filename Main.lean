import Shell.Mirror.Session
import Shell.Transport.Stdio

/-!
# Main — the mirror CLI (Layer 3, design 5.4)

CLI parity with the Haskell @app/Main.hs@ surface, phased:

- default (no args): the stdio mirror session — Phase 3, fully
  functional for the @register_traces@ replay flow (the apalache-backed
  oracles land in Phase 5 and answer @register_error@ until then).
- @--serve@ / @--server@ / @validate@: TCP/mTLS/registry modes land in
  Phase 6; they currently exit 2 with a clear message instead of
  silently doing the wrong thing.
-/


/-- The Lean 4.33 IO refactor dropped `IO.getArgs`; read argv from
/proc/self/cmdline (POSIX — same platform caveat as the Phase 6 signal
handling). -/
def getArgsIO : IO (List String) := do
  let r ← try pure (some (← IO.FS.readFile "/proc/self/cmdline")) catch _ => pure none
  match r with
  | none => return []
  | some s =>
      return ((s.splitOn (String.singleton (Char.ofNat 0))).drop 1).filter (fun x => !x.isEmpty)

def main : IO UInt32 := do
  let args ← getArgsIO
  match args with
  | "--serve" :: _ =>
      IO.eprintln "--serve: TCP transport lands in Phase 6"
      return 2
  | "--server" :: _ =>
      IO.eprintln "--server: mTLS transport lands in Phase 6"
      return 2
  | "validate" :: _ =>
      IO.eprintln "validate: client mode lands in Phase 6"
      return 2
  | _ =>
      -- default mode: stdio mirror session (Haskell: run StdioTransport)
      let t ← Shell.Transport.stdio
      Shell.Mirror.run t Shell.Mirror.stubOracles
      return 0