import Codec.Json
import Codec.ExplorerRpc
import Codec.Consul
import Lean.Data.Json

open Lean Lean.Json.Parser

/-! Fixture round-trip replay (Phase 2 exit).
Parses every fixture line, decodes it into a typed message, re-encodes it,
and compares the compressed byte forms in both directions. -/

def checkLine (kind : String) (idx : Nat) (line : String) : IO Bool := do
  match Json.parse line with
  | Except.error e =>
      IO.println s!"FAIL {kind}:{idx}: parse error {e}"
      return false
  | Except.ok j =>
      let decoded := match kind with
        | "client" => (Codec.decodeClient j).map Codec.encodeClient
        | _ => (Codec.decodeMirror j).map Codec.encodeMirror
      match decoded with
      | Except.error e =>
          IO.println s!"FAIL {kind}:{idx}: decode error {repr e}"
          return false
      | Except.ok j' =>
          let a := Json.compress j
          let b := Json.compress j'
          let rawOk := a == line
          if a == b && rawOk then
            return true
          else
            IO.println s!"FAIL {kind}:{idx}:"
            IO.println s!"  parsed : {a}"
            IO.println s!" rencoded: {b}"
            if !rawOk then IO.println s!"  (raw line differs from compressed parse)"
            return false

def checkFile (kind : String) (path : String) : IO Nat := do
  let mut fails := 0
  let content ← IO.FS.readFile path
  let mut idx := 0
  for line in content.splitOn "\n" do
    if !line.isEmpty then
      idx := idx + 1
      let ok ← checkLine kind idx line
      if !ok then fails := fails + 1
  return fails


/- One explorer transcript line. -/
def checkExplorerLine (idx : Nat) (line : String) : IO Bool := do
  match Json.parse line with
  | Except.error e =>
      IO.println s!"FAIL explorer:{idx}: parse error {e}"
      return false
  | Except.ok j =>
      let mth := match j.getObjVal? "method" with | Except.ok (Json.str s) => s | _ => ""
      let reqLine := match j.getObjVal? "request" with | Except.ok (Json.str s) => s | _ => ""
      let respLine := match j.getObjVal? "response" with | Except.ok (Json.str s) => s | _ => ""
      let mut ok := true
      match Json.parse reqLine with
      | Except.error e =>
          IO.println s!"FAIL explorer:{idx} request: parse error {e}"
          ok := false
      | Except.ok rj =>
          match (Codec.decodeRpcRequest rj).map Codec.encodeRpcRequest with
          | Except.error e =>
              IO.println s!"FAIL explorer:{idx} request: decode error {repr e}"
              ok := false
          | Except.ok rj2 =>
              if Json.compress rj != Json.compress rj2 then
                IO.println s!"FAIL explorer:{idx} request mismatch"
                ok := false
      match Json.parse respLine with
      | Except.error e =>
          IO.println s!"FAIL explorer:{idx} response: parse error {e}"
          ok := false
      | Except.ok pj =>
          match (Codec.decodeRpcResponse mth pj).map Codec.encodeRpcResponse with
          | Except.error e =>
              IO.println s!"FAIL explorer:{idx} response: decode error {repr e}"
              ok := false
          | Except.ok pj2 =>
              if Json.compress pj != Json.compress pj2 then
                IO.println s!"FAIL explorer:{idx} response mismatch"
                ok := false
      return ok

def checkExplorerFile (path : String) : IO Nat := do
  let mut fails := 0
  let content <- IO.FS.readFile path
  let mut idx := 0
  for line in content.splitOn (String.mk [Char.ofNat 10]) do
    if !line.isEmpty then
      idx := idx + 1
      let ok <- checkExplorerLine idx line
      if !ok then fails := fails + 1
  return fails


/- Decode-only parity cases (bare JSON numbers, t23): each line is
a {"json":J,"expect":E} pair; E is "ok:<compressed re-encode>" or "error:<msg>". -/
def checkDecodeOnlyLine (idx : Nat) (line : String) : IO Bool := do
  match Json.parse line with
  | Except.error e =>
      IO.println s!"FAIL decode_only:{idx}: parse error {e}"
      return false
  | Except.ok mj =>
      let jstr := match mj.getObjVal? "json" with | Except.ok (Json.str s) => s | _ => ""
      let expect := match mj.getObjVal? "expect" with | Except.ok (Json.str s) => s | _ => ""
      match Json.parse jstr with
      | Except.error e =>
          IO.println s!"FAIL decode_only:{idx}: inner parse error {e}"
          return false
      | Except.ok j =>
          if expect.startsWith "error:" then
            match (Codec.decodeClient j).map Codec.encodeClient with
            | Except.error e =>
                let want := expect.drop 6
                if e.msg == want then return true
                else
                  IO.println s!"FAIL decode_only:{idx}: error {e.msg} != {want}"
                  return false
            | Except.ok _ =>
                IO.println s!"FAIL decode_only:{idx}: expected error {expect.drop 6}, decoded ok"
                return false
          else
            match (Codec.decodeClient j).map Codec.encodeClient with
            | Except.error e =>
                IO.println s!"FAIL decode_only:{idx}: decode error {e.msg}"
                return false
            | Except.ok j2 =>
                let want := expect.drop 3
                if Json.compress j2 == want then return true
                else
                  IO.println s!"FAIL decode_only:{idx}: {Json.compress j2} != {want}"
                  return false

def checkDecodeOnlyFile (path : String) : IO Nat := do
  let mut fails := 0
  let content <- IO.FS.readFile path
  let mut idx := 0
  for line in content.splitOn (String.mk [Char.ofNat 10]) do
    if !line.isEmpty then
      idx := idx + 1
      let ok <- checkDecodeOnlyLine idx line
      if !ok then fails := fails + 1
  return fails


/- Consul payload fixtures (t24): each line is a {"kind":K,"json":J,"expect":E}
triple; K is "register" or "health", E is "ok:<compressed re-encode>" or
"error:<msg>". -/
def checkConsulLine (idx : Nat) (line : String) : IO Bool := do
  match Json.parse line with
  | Except.error e =>
      IO.println s!"FAIL consul:{idx}: parse error {e}"
      return false
  | Except.ok mj =>
      let kind := match mj.getObjVal? "kind" with | Except.ok (Json.str s) => s | _ => ""
      let jstr := match mj.getObjVal? "json" with | Except.ok (Json.str s) => s | _ => ""
      let expect := match mj.getObjVal? "expect" with | Except.ok (Json.str s) => s | _ => ""
      if jstr == "" then
        IO.println s!"FAIL consul:{idx}: missing json"
        return false
      match Json.parse jstr with
      | Except.error e =>
          IO.println s!"FAIL consul:{idx}: inner parse error {e}"
          return false
      | Except.ok j =>
          let r := if kind == "register" then
            (Consul.decodeRegisterBody j).map Consul.encodeRegisterBody
          else
            (Consul.decodeServices j).map Consul.encodeServices
          if expect.startsWith "error:" then
            match r with
            | Except.error e =>
                let want := expect.drop 6
                if e.msg == want then return true
                else
                  IO.println s!"FAIL consul:{idx}: error {e.msg} != {want}"
                  return false
            | Except.ok _ =>
                IO.println s!"FAIL consul:{idx}: expected error {expect.drop 6}, decoded ok"
                return false
          else
            match r with
            | Except.error e =>
                IO.println s!"FAIL consul:{idx}: decode error {e.msg}"
                return false
            | Except.ok j2 =>
                let want := expect.drop 3
                if Json.compress j2 == want then return true
                else
                  IO.println s!"FAIL consul:{idx}: {Json.compress j2} != {want}"
                  return false

def checkConsulFile (path : String) : IO Nat := do
  let mut fails := 0
  let content <- IO.FS.readFile path
  let mut idx := 0
  for line in content.splitOn (String.mk [Char.ofNat 10]) do
    if !line.isEmpty then
      idx := idx + 1
      let ok <- checkConsulLine idx line
      if !ok then fails := fails + 1
  return fails

def main : IO UInt32 := do
  let cf ← checkFile "client" "test/fixtures/client_messages.jsonl"
  let mf ← checkFile "mirror" "test/fixtures/mirror_messages.jsonl"
  let ef <- checkExplorerFile "test/fixtures/explorer_transcripts.jsonl"
  let df <- checkDecodeOnlyFile "test/fixtures/decode_only.jsonl"
  let cf2 <- checkConsulFile "test/fixtures/consul_payloads.jsonl"
  if cf == 0 && mf == 0 && ef == 0 && df == 0 && cf2 == 0 then
    IO.println "ALL FIXTURES ROUND-TRIP BYTE-IDENTICAL"
    return 0
  else
    IO.println s!"FAILURES: client={cf} mirror={mf} explorer={ef} decode_only={df} consul={cf2}"
    return 1