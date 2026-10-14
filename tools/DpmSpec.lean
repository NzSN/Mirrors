import Codec.Dpm
open Core.Dpm

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

def main : IO Unit := do
  let chains : List Chain := [{ actor := "a", checkpoints := ["read", "$done"] },
    { actor := "b", checkpoints := ["read", "$done"] }]
  let serial : Candidate :=
    { id := "serial"
      inputRank := 0
      steps := [{actor := "a", checkpoint := "read"}, {actor := "a", checkpoint := "$done"},
      {actor := "b", checkpoint := "read"}, {actor := "b", checkpoint := "$done"}] }
  let overlap : Candidate :=
    { id := "overlap"
      inputRank := 1
      steps := [{actor := "a", checkpoint := "read"}, {actor := "b", checkpoint := "read"},
      {actor := "a", checkpoint := "$done"}, {actor := "b", checkpoint := "$done"}] }
  check ((validate chains [serial, overlap] "overlap").isOk) "valid complete schedules refused"
  check (cost serial == [2,0,0,4] && cost overlap == [2,1,2,4]) "cost does not match finite reference"
  check ((ordered [overlap,serial]).map (·.id) == ["serial","overlap"]) "search order differs"
  let subset : Candidate := {serial with id := "subset", steps := serial.steps.filter (·.actor == "a")}
  check ((validate chains [subset] "subset").isOk && cost subset == [1,0,0,2]) "whole-actor removal refused"
  let truncated : Candidate := {serial with steps := serial.steps.take 3}
  check (!(validate chains [truncated] "serial").isOk) "truncated actor chain accepted"
  check (!(validate chains [serial,serial] "serial").isOk) "duplicate candidate accepted"
  check (!(validate chains [serial] "unknown").isOk) "absent baseline accepted"
  check (!(Codec.Dpm.decode "{\"schema\":1,\"schema\":2}".toUTF8).isOk) "duplicate JSON accepted"
  let project := r#"{"schema":"mirrors.dpm-project/v2","profile":"mirrorcpp.cooperative-checkpoints/v1","identity":{"modelSemanticDigest":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","mappingSha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","implementationSha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},"explorerIdentity":null,"command":{"kind":"native","executable":"runner","args":[{"literal":"--mode"},{"artifact":"application.json"}]},"artifacts":[{"path":"artifact","sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}],"chains":[{"actor":"a","checkpoints":["$done"]}],"baseline":"base","candidates":[{"id":"base","inputRank":0,"schedule":{"schema":"mirrors.checkpoint-schedule/v1","profile":"mirrorcpp.cooperative-checkpoints/v1","identity":{"modelSemanticDigest":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","mappingSha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","implementationSha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},"inputs":{},"steps":[{"actor":"a","checkpoint":"$done"}]},"oracle":{"path":"artifact","sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},"provenance":{"path":"artifact","sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}}],"signature":"exact-terminal/v1","limits":{"attempts":8,"timeoutMs":1000,"totalTimeoutMs":5000,"outputBytes":10000,"totalOutputBytes":1048576}}"#
  check ((Codec.Dpm.decode project.toUTF8).isOk) "typed v2 native project refused"
  let literalProject := fun (value : String) => project.replace r#"{"literal":"--mode"}"#
    (Lean.Json.mkObj [("literal", Lean.Json.str value)]).compress
  check ((Codec.Dpm.decode (literalProject "").toUTF8).isOk) "empty literal argv entry refused"
  check (!(Codec.Dpm.decode (project.replace r#""executable":"runner""# r#""executable":"""#).toUTF8).isOk)
    "empty executable path accepted"
  check (!(Codec.Dpm.decode (project.replace r#""artifact":"application.json""# r#""artifact":"""#).toUTF8).isOk)
    "empty artifact argument path accepted"
  let pythonProject := project.replace r#""kind":"native""# r#""kind":"python-isolated","script":"""#
  check (!(Codec.Dpm.decode pythonProject.toUTF8).isOk) "empty Python script path accepted"
  check (!(Codec.Dpm.decode (literalProject "\x00").toUTF8).isOk) "NUL literal argument accepted"
  check ((Codec.Dpm.decode (literalProject (String.ofList (List.replicate 4096 'x'))).toUTF8).isOk)
    "literal at UTF-8 byte bound refused"
  check (!(Codec.Dpm.decode (literalProject (String.ofList (List.replicate 4097 'x'))).toUTF8).isOk)
    "overlong literal argument accepted"
  check ((Codec.Dpm.decode (literalProject (String.ofList (List.replicate 2048 'é'))).toUTF8).isOk)
    "multibyte literal at UTF-8 byte bound refused"
  check (!(Codec.Dpm.decode (literalProject (String.ofList (List.replicate 2049 'é'))).toUTF8).isOk)
    "literal bound counted characters instead of UTF-8 bytes"
  check (!(Codec.Dpm.decode (project.replace "mirrors.dpm-project/v2" "mirrors.dpm-project/v1").toUTF8).isOk) "invalid v2 command/budget accepted"
  check (!(Codec.Dpm.decode (project.replace "\"kind\":\"native\"" "\"kind\":\"unknown\"").toUTF8).isOk) "invalid v2 command/budget accepted"
  check (!(Codec.Dpm.decode (project.replace "\"literal\":\"--mode\"" "\"unknown\":\"--mode\"").toUTF8).isOk) "invalid v2 command/budget accepted"
  check (!(Codec.Dpm.decode (project.replace "\"totalOutputBytes\":1048576" "\"totalOutputBytes\":1").toUTF8).isOk) "invalid v2 command/budget accepted"
  check (!(Codec.Dpm.decode (project.replace "\"explorerIdentity\":null" "\"explorerIdentity\":{}").toUTF8).isOk) "invalid v2 command/budget accepted"
  check ((Codec.Dpm.decode (project.replace "\"kind\":\"native\"" "\"kind\":\"python-isolated\",\"script\":\"runner.py\"").toUTF8).isOk) "isolated Python project refused"
  let legacy := (((project.replace "mirrors.dpm-project/v2" "mirrors.dpm-project/v1").replace
      r#""explorerIdentity":null,"# "").replace
      r#"{"kind":"native","executable":"runner","args":[{"literal":"--mode"},{"artifact":"application.json"}]}"#
      r#"["runner"]"#).replace r#","totalOutputBytes":1048576"# ""
  match Codec.Dpm.decode legacy.toUTF8 with
  | .error message =>
    check (message == "unsupported project; reprepare as mirrors.dpm-project/v2")
      "legacy project lacks explicit reprepare diagnostic"
  | .ok _ => throw (IO.userError "legacy project was accepted")
  IO.println "DPM pure policy: 25 gates passed; projection preservation theorem checked by kernel"
