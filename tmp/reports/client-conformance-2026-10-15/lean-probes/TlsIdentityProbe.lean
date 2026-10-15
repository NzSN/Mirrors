import MirrorLean.ServerMode
open MirrorLean Lean

def main (args : List String) : IO Unit := do
  let dir := args[0]!
  let portText := args[1]!
  let peer := args[2]!
  let some portNat := portText.toNat? | throw (IO.userError "invalid port")
  for (label, serverName) in [("default", (none : Option String)),
      ("wrong-name", some "wrong.example"), ("empty-name", some "")] do
    let cfg : ServerMode.TlsClientConfig := {
      caFile := dir ++ "/ca.crt", certFile := dir ++ "/client.crt",
      keyFile := dir ++ "/client.key", serverName }
    try
      let transport ← ServerMode.connectMirrorTls cfg "127.0.0.1" (UInt16.ofNat portNat)
      let _ ← transport.close
      IO.println (Json.mkObj [("peer", .str peer), ("case", .str label),
        ("connected", .bool true)]).compress
    catch error =>
      IO.println (Json.mkObj [("peer", .str peer), ("case", .str label),
        ("connected", .bool false), ("error", .str error.toString)]).compress
