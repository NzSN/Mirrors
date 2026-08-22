import Shell.Transport.Stdio
import Std.Sync.Mutex

/-!
# In-memory mock transport pair (Layer 3)

Port of the Haskell @Protocol.Transport.Mock@ used by the async-job test
suite: two transports wired back-to-back, each line buffered until the
peer receives it. Test-only (polling hand-off; no production use).
-/

namespace Shell.Transport

private structure Chan where
  mu : Std.Mutex (List String)

private def Chan.new : BaseIO Chan :=
  return ⟨← Std.Mutex.new []⟩

private def Chan.put (c : Chan) (line : String) : IO Unit :=
  c.mu.atomically do
    modify (fun ls => ls ++ [line])

private def Chan.take (c : Chan) : IO (Option String) := do
  let mut loop := true
  let mut out := none
  while loop do
    let r ← c.mu.atomically do
      let ls ← get
      match ls with
      | [] => return none
      | l :: rest => set rest; return (some l)
    match r with
    | some l => out := some l; loop := false
    | none => IO.sleep 1
  return out

/-- A wired transport pair: lines sent on the first arrive on the second
and vice versa (Haskell @newMockTransport@). -/
def mockPair : IO (Transport × Transport) := do
  let a ← Chan.new
  let b ← Chan.new
  return ({ recv := a.take, send := b.put },
          { recv := b.take, send := a.put })

end Shell.Transport
