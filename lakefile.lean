import Lake
import Lean
open Lake DSL

/-- Native compiler selection is read at target-fetch time, so environment
changes are not frozen in the compiled lakefile. -/
def shimCompiler : IO String := do
  return (← IO.getEnv "CC").getD
    (if System.Platform.isWindows then "gcc" else "cc")

def opensslPkgConfig (args : Array String) : IO String := do
  let out ← IO.Process.output { cmd := "pkg-config", args := args.push "openssl" }
  if out.exitCode != 0 then
    throw <| IO.userError s!"pkg-config failed for OpenSSL: {out.stderr}"
  return out.stdout.trimAscii.toString

def osslInc : IO String := do
  match ← IO.getEnv "OSSL_INC" with
  | some p => pure p
  | none =>
    if System.Platform.isWindows then
      pure "/d/Programs/msys2/ucrt64/include"
    else
      opensslPkgConfig #["--variable=includedir"]

def osslLib : IO String := do
  match ← IO.getEnv "OSSL_LIB" with
  | some p => pure p
  | none => pure (if System.Platform.isWindows then "/d/Programs/msys2/ucrt64/lib" else "")

/-- ws2_32 is required by both socket and TLS consumers on Windows. -/
def sockLinkArgs : Array String :=
  if System.Platform.isWindows then #["-lws2_32"] else #[]

/-- The C source, selected headers, compiler identity, and flags all feed the
object trace. `moreLinkObjs` below carries that trace into executable linking. -/
def buildShim (pkg : Package) (stem : String) (tls : Bool) : FetchM (Job System.FilePath) := do
  let cc ← shimCompiler
  let version ← IO.Process.output { cmd := cc, args := #["--version"] }
  if version.exitCode != 0 then
    error s!"cannot identify C compiler '{cc}': {version.stderr}"
  let leanInclude ← getLeanIncludeDir
  let mut args := #["-I", leanInclude.toString]
  let mut headerJobs := #[
    ← inputDir leanInclude true (·.extension == some "h"),
    ← inputDir (pkg.dir / "Ffi") true (·.extension == some "h")]
  if tls then
    let includeDir ← osslInc
    let cflags ←
      if System.Platform.isWindows || (← IO.getEnv "OSSL_INC").isSome then
        pure #["-I", includeDir]
      else
        pure (((← opensslPkgConfig #["--cflags"]).splitOn " ").filter (· != "")).toArray
    args := args ++ cflags
    headerJobs := headerJobs.push <|
      ← inputDir (System.FilePath.mk includeDir / "openssl") true (·.extension == some "h")
  let srcJob ← inputTextFile (pkg.dir / "Ffi" / s!"{stem}.c")
  let headersJob := Job.collectArray headerJobs "shim headers"
  let srcJob ← srcJob.bindM fun src => headersJob.mapM fun _ => do
    addLeanTrace
    addPureTrace (cc, version.stdout, version.stderr) "C compiler"
    return src
  buildO (pkg.buildDir / s!"{stem}.o") srcJob #[] args cc

/-- A library directory override is traced at fetch time and reflected in -L;
this also works after the lakefile has been elaborated and cached. -/
def opensslLibrary (name : String) : FetchM (Job Dynlib) := Job.async do
  let dir ← osslLib
  addPureTrace (name, dir) "OpenSSL library"
  addPlatformTrace
  return { name, path := if dir.isEmpty then nameToSharedLib name
    else System.FilePath.mk dir / nameToSharedLib name }


package mirrors

@[default_target]
lean_lib Core where
  globs := #[.submodules `Core]

@[default_target]
lean_lib Codec where
  globs := #[.submodules `Codec]

@[default_target]
lean_lib Shell where
  globs := #[.submodules `Shell]

/-- Phase 0/2: golden wire corpus byte-identity replay (tools/ReplayFixtures.lean). -/
@[default_target]
lean_exe fixtures_replay where
  root := `tools.ReplayFixtures

/-- Phase 1: differential diff-engine test vs the Haskell implementation
(tools/DiffCross.lean, driven by test/fixtures/diff_cases.jsonl). -/
@[default_target]
lean_exe diff_cross where
  root := `tools.DiffCross

/-- Deterministic model-interface compiler, distribution policy, cache, strict
JSON, and TypeScript-emitter gate. -/
@[default_target]
lean_exe model_interface_spec where
  root := `tools.ModelInterfaceSpec

/-- In-memory JSONL negotiation and replay gate for runtime model-interface
distribution. -/
@[default_target]
lean_exe model_interface_distribution_spec where
  root := `tools.ModelInterfaceDistributionSpec

/-- Development-time model-interface compiler CLI. -/
@[default_target]
lean_exe model_interface_gen where
  root := `tools.ModelInterfaceGen

/-- Proposal-only model-interface scaffold CLI and publication gate. -/
@[default_target]
lean_exe model_interface_scaffold_cli_spec where
  root := `tools.ModelInterfaceScaffoldCliSpec

/-- Typed evidence grammar and exact TLA+ variable-source gate. -/
@[default_target]
lean_exe model_interface_evidence_spec where
  root := `tools.ModelInterfaceEvidenceSpec

/-- Pure scaffold synthesis and strict proposal-codec gate. -/
@[default_target]
lean_exe model_interface_scaffold_spec where
  root := `tools.ModelInterfaceScaffoldSpec

/-- Compiler-owned raw ITF projection CLI and paired publication gate. -/
@[default_target]
lean_exe model_interface_trace_projection_cli_spec where
  root := `tools.ModelInterfaceTraceProjectionCliSpec

/-- Pure bounded ITF trace projection and strict receipt-codec gate. -/
@[default_target]
lean_exe model_interface_trace_projection_spec where
  root := `tools.ModelInterfaceTraceProjectionSpec

/-- Phase 3: the mirror CLI binary (default stdio mode). -/
@[default_target]
lean_exe mirror where
  root := `Main
  moreLinkObjs := #[`@/socket_shim_o, `@/tls_shim_o]
  moreLinkLibs := #[`@/openssl_ssl, `@/openssl_crypto]
  moreLinkArgs := sockLinkArgs

/-- Phase 3: stdio session smoke test against the built mirror binary. -/
@[default_target]
lean_exe stdio_smoke where
  root := `tools.StdioSmoke

/-- Phase 4: async job-store parity suite vs the Haskell AsyncJobsSpec
fake-runner workloads (tools/JobStoreSpec.lean). -/
@[default_target]
lean_exe jobstore_spec where
  root := `tools.JobStoreSpec

/-- Content-tracked native objects; requested executables link these jobs. -/
target socket_shim_o pkg : System.FilePath := buildShim pkg "socket_shim" false

target tls_shim_o pkg : System.FilePath := buildShim pkg "tls_shim" true

target openssl_ssl : Dynlib := opensslLibrary "ssl"

target openssl_crypto : Dynlib := opensslLibrary "crypto"

@[default_target]
lean_lib Ffi where
  globs := #[.submodules `Ffi]

/-- Phase 5: apalache CLI adapter regression suite
(tools/ApalacheCliSpec.lean; real-apalache integration runs only with
APALACHE_MC set, self-skipping otherwise). -/
@[default_target]
lean_exe apalache_cli_spec where
  root := `tools.ApalacheCliSpec
  moreLinkObjs := #[`@/socket_shim_o]
  moreLinkArgs := sockLinkArgs

/-- t14: explorer HTTP/JSON-RPC spike, transcript parity, and the
HourClock explorer end-to-end (real apalache integration runs only
with APALACHE_MC set, self-skipping otherwise). -/
@[default_target]
lean_exe explorer_spec where
  root := `tools.ExplorerSpec
  moreLinkObjs := #[`@/socket_shim_o]
  moreLinkArgs := sockLinkArgs

/-- t15: TCP + mTLS transport regression suite (generates a throwaway
PKI with the openssl CLI at test time; skips itself when the openssl
CLI is missing). -/
@[default_target]
lean_exe transport_spec where
  root := `tools.TransportSpec
  moreLinkObjs := #[`@/socket_shim_o, `@/tls_shim_o]
  moreLinkLibs := #[`@/openssl_ssl, `@/openssl_crypto]
  moreLinkArgs := sockLinkArgs

/-- t16: registry/discovery + signal-handling gate (mock Consul via
python3; the SIGTERM tier needs the openssl CLI for a throwaway PKI
and self-skips that tier without it). -/
@[default_target]
lean_exe registry_spec where
  root := `tools.RegistrySpec
  moreLinkObjs := #[`@/socket_shim_o, `@/tls_shim_o]
  moreLinkLibs := #[`@/openssl_ssl, `@/openssl_crypto]
  moreLinkArgs := sockLinkArgs

/-- Counter end-to-end: register flow (validate + trace-gen + replay)
against test/specs/Counter.tla with a scripted echo client; ports the
intent of the stale upstream MainSpec.testCounterEndToEnd with corrected
expectations (tools/CounterSpec.lean; APALACHE_MC-gated, self-skips). -/
@[default_target]
lean_exe counter_spec where
  root := `tools.CounterSpec

/-- Minimal crash demo for the Lean 4.33 Windows task-teardown AV
(tools/MinCrash.lean; Docs/lean-windows-teardown-analysis.md).
NOT a gate: no test_driver wiring, no default target. -/
lean_exe mincrash where
  root := `tools.MinCrash
  moreLinkObjs := #[`@/socket_shim_o, `@/tls_shim_o]
  moreLinkLibs := #[`@/openssl_ssl, `@/openssl_crypto]
  moreLinkArgs := sockLinkArgs

/--- t31: REAL async flows over live mirror server children (plain TCP
and mTLS modes) against real apalache (tools/AsyncSpec.lean; runs only
with APALACHE_MC set, self-skipping otherwise). -/
@[default_target]
lean_exe async_spec where
  root := `tools.AsyncSpec
  moreLinkObjs := #[`@/socket_shim_o, `@/tls_shim_o]
  moreLinkLibs := #[`@/openssl_ssl, `@/openssl_crypto]
  moreLinkArgs := sockLinkArgs

/-- lake test runs the differential/parity + stdio gates; exit 0 = all green. -/
@[test_driver]
script test do
  -- Build first: the gates below exec .lake/build/bin/* directly, and a
  -- silently skipped rebuild would run STALE binaries (a green-looking
  -- run once shipped on a tree where transport_spec did not compile).
  let pre : IO.Process.Output ← IO.Process.output
    ({ cmd := "lake", args := #["build"] } : IO.Process.SpawnArgs)
  if pre.exitCode != 0 then
    IO.println "lake build FAILED before test run:"
    IO.eprintln pre.stderr
    return pre.exitCode
  let asyncEmitter : IO.Process.Output ← IO.Process.output
    ({ cmd := "python3", args := #["tools/check-async-emitter.py"] } : IO.Process.SpawnArgs)
  IO.println asyncEmitter.stdout
  if asyncEmitter.exitCode != 0 then
    IO.eprintln asyncEmitter.stderr
    return asyncEmitter.exitCode
  let out1 : IO.Process.Output ← IO.Process.output ({ cmd := ".lake/build/bin/fixtures_replay", args := #[] } : IO.Process.SpawnArgs)
  IO.println out1.stdout
  if out1.exitCode != 0 then
    IO.println s!"fixtures_replay FAILED ({out1.exitCode})"
    return out1.exitCode
  let out2 : IO.Process.Output ← IO.Process.output ({ cmd := ".lake/build/bin/diff_cross", args := #[] } : IO.Process.SpawnArgs)
  IO.println out2.stdout
  if out2.exitCode != 0 then
    IO.println s!"diff_cross FAILED ({out2.exitCode})"
    return out2.exitCode
  let outMi : IO.Process.Output ← IO.Process.output
    ({ cmd := ".lake/build/bin/model_interface_spec", args := #[] } : IO.Process.SpawnArgs)
  IO.println outMi.stdout
  if outMi.exitCode != 0 then
    IO.println s!"model_interface_spec FAILED ({outMi.exitCode})"
    return outMi.exitCode
  let outMiDistribution : IO.Process.Output ← IO.Process.output
    ({ cmd := ".lake/build/bin/model_interface_distribution_spec", args := #[] } :
      IO.Process.SpawnArgs)
  IO.println outMiDistribution.stdout
  if outMiDistribution.exitCode != 0 then
    IO.println s!"model_interface_distribution_spec FAILED ({outMiDistribution.exitCode})"
    return outMiDistribution.exitCode
  let outMiScaffoldCli : IO.Process.Output ← IO.Process.output
    ({ cmd := ".lake/build/bin/model_interface_scaffold_cli_spec", args := #[] } :
      IO.Process.SpawnArgs)
  IO.println outMiScaffoldCli.stdout
  if outMiScaffoldCli.exitCode != 0 then
    IO.eprintln outMiScaffoldCli.stderr
    IO.println s!"model_interface_scaffold_cli_spec FAILED ({outMiScaffoldCli.exitCode})"
    return outMiScaffoldCli.exitCode
  let outMiEvidence : IO.Process.Output ← IO.Process.output
    ({ cmd := ".lake/build/bin/model_interface_evidence_spec", args := #[] } :
      IO.Process.SpawnArgs)
  IO.println outMiEvidence.stdout
  if outMiEvidence.exitCode != 0 then
    IO.eprintln outMiEvidence.stderr
    IO.println s!"model_interface_evidence_spec FAILED ({outMiEvidence.exitCode})"
    return outMiEvidence.exitCode
  let outMiScaffold : IO.Process.Output ← IO.Process.output
    ({ cmd := ".lake/build/bin/model_interface_scaffold_spec", args := #[] } :
      IO.Process.SpawnArgs)
  IO.println outMiScaffold.stdout
  if outMiScaffold.exitCode != 0 then
    IO.eprintln outMiScaffold.stderr
    IO.println s!"model_interface_scaffold_spec FAILED ({outMiScaffold.exitCode})"
    return outMiScaffold.exitCode
  let outMiProjectionCli : IO.Process.Output ← IO.Process.output
    ({ cmd := ".lake/build/bin/model_interface_trace_projection_cli_spec", args := #[] } :
      IO.Process.SpawnArgs)
  IO.println outMiProjectionCli.stdout
  if outMiProjectionCli.exitCode != 0 then
    IO.eprintln outMiProjectionCli.stderr
    IO.println s!"model_interface_trace_projection_cli_spec FAILED ({outMiProjectionCli.exitCode})"
    return outMiProjectionCli.exitCode
  let outMiProjection : IO.Process.Output ← IO.Process.output
    ({ cmd := ".lake/build/bin/model_interface_trace_projection_spec", args := #[] } :
      IO.Process.SpawnArgs)
  IO.println outMiProjection.stdout
  if outMiProjection.exitCode != 0 then
    IO.eprintln outMiProjection.stderr
    IO.println s!"model_interface_trace_projection_spec FAILED ({outMiProjection.exitCode})"
    return outMiProjection.exitCode
  let outMiGolden : IO.Process.Output ← IO.Process.output
    ({ cmd := ".lake/build/bin/model_interface_gen", args := #[
      "check",
      "--spec", "specs/Counter.tla",
      "--contract", "test/fixtures/model-interface/counter/Counter.mirror-interface.json",
      "--evidence", "test/fixtures/model-interface/counter/counter.itf.json",
      "--param-var", "parameters",
      "--lock", "test/fixtures/model-interface/counter/Counter.mirror-interface.lock.json",
      "--target", "mirrorecma-v1",
      "--out", "test/fixtures/model-interface/counter/generated"
    ] } : IO.Process.SpawnArgs)
  IO.println outMiGolden.stdout
  if outMiGolden.exitCode != 0 then
    IO.eprintln outMiGolden.stderr
    IO.println s!"model_interface_gen check FAILED ({outMiGolden.exitCode})"
    return outMiGolden.exitCode
  let outMiAsyncGolden : IO.Process.Output ← IO.Process.output
    ({ cmd := ".lake/build/bin/model_interface_gen", args := #[
      "check",
      "--spec", "specs/Counter.tla",
      "--contract", "test/fixtures/model-interface/counter/Counter.mirror-interface.json",
      "--evidence", "test/fixtures/model-interface/counter/counter.itf.json",
      "--param-var", "parameters",
      "--lock", "test/fixtures/model-interface/counter/Counter.mirror-interface.lock.json",
      "--target", "mirrorecma-async-v1",
      "--out", "test/fixtures/model-interface/counter/generated-async"
    ] } : IO.Process.SpawnArgs)
  IO.println outMiAsyncGolden.stdout
  if outMiAsyncGolden.exitCode != 0 then
    IO.eprintln outMiAsyncGolden.stderr
    IO.println s!"model_interface_gen async check FAILED ({outMiAsyncGolden.exitCode})"
    return outMiAsyncGolden.exitCode
  let outMiCppGolden : IO.Process.Output ← IO.Process.output
    ({ cmd := ".lake/build/bin/model_interface_gen", args := #[
      "check",
      "--spec", "specs/Counter.tla",
      "--contract", "test/fixtures/model-interface/counter/Counter.mirror-interface.json",
      "--evidence", "test/fixtures/model-interface/counter/counter.itf.json",
      "--param-var", "parameters",
      "--lock", "test/fixtures/model-interface/counter/Counter.mirror-interface.lock.json",
      "--target", "mirrorcpp-v1",
      "--out", "test/fixtures/model-interface/counter/generated-cpp"
    ] } : IO.Process.SpawnArgs)
  IO.println outMiCppGolden.stdout
  if outMiCppGolden.exitCode != 0 then
    IO.eprintln outMiCppGolden.stderr
    IO.println s!"model_interface_gen C++ check FAILED ({outMiCppGolden.exitCode})"
    return outMiCppGolden.exitCode
  let outMiPreflight : IO.Process.Output ← IO.Process.output
    ({ cmd := ".lake/build/bin/model_interface_gen", args := #[
      "preflight",
      "--lock", "test/fixtures/model-interface/counter/Counter.mirror-interface.lock.json",
      "--trace", "test/fixtures/model-interface/counter/counter.itf.json",
      "--require-all-actions"
    ] } : IO.Process.SpawnArgs)
  IO.println outMiPreflight.stdout
  if outMiPreflight.exitCode != 0 then
    IO.eprintln outMiPreflight.stderr
    IO.println s!"model_interface_gen preflight FAILED ({outMiPreflight.exitCode})"
    return outMiPreflight.exitCode
  let expectedMiPreflight ← IO.FS.readBinFile
    "test/fixtures/model-interface/counter/Counter.mirror-interface.coverage.json"
  if outMiPreflight.stdout.toUTF8 != expectedMiPreflight then
    IO.eprintln "model_interface_gen preflight coverage differed from exact golden bytes"
    IO.eprintln s!"actual: {outMiPreflight.stdout}"
    return 1
  let out3 : IO.Process.Output ← IO.Process.output ({ cmd := ".lake/build/bin/stdio_smoke", args := #[] } : IO.Process.SpawnArgs)
  IO.println out3.stdout
  if out3.exitCode != 0 then
    IO.println s!"stdio_smoke FAILED ({out3.exitCode})"
    return out3.exitCode
  let out4 : IO.Process.Output ← IO.Process.output ({ cmd := ".lake/build/bin/jobstore_spec", args := #[] } : IO.Process.SpawnArgs)
  let apalacheMc? ← IO.getEnv "APALACHE_MC"
  let apalacheMc? ← match apalacheMc? with
    | some p => pure (some p)
    | none =>
      let cand := "/home/nzsn/.local/bin/apalache/bin/apalache-mc"
      let probe ← IO.Process.output ({ cmd := "test", args := #["-x", cand] } : IO.Process.SpawnArgs)
      pure (if probe.exitCode == 0 then some cand else none)
  let out5 : IO.Process.Output ← IO.Process.output
    ({ cmd := ".lake/build/bin/apalache_cli_spec", args := #[],
       env := match apalacheMc? with
              | some p => #[("APALACHE_MC", some p)]
              | none => #[] } : IO.Process.SpawnArgs)
  IO.println out4.stdout
  if out4.exitCode != 0 then
    IO.println s!"jobstore_spec FAILED ({out4.exitCode})"
    return out4.exitCode
  IO.println out5.stdout
  if out5.exitCode != 0 then
    IO.println s!"apalache_cli_spec FAILED ({out5.exitCode})"
    return out5.exitCode
  let out6 : IO.Process.Output ← IO.Process.output
    ({ cmd := ".lake/build/bin/explorer_spec", args := #[],
       env := match apalacheMc? with
              | some p => #[("APALACHE_MC", some p)]
              | none => #[] } : IO.Process.SpawnArgs)
  IO.println out6.stdout
  if out6.exitCode != 0 then
    IO.println s!"explorer_spec FAILED ({out6.exitCode})"
    return out6.exitCode
  let out7 : IO.Process.Output ← IO.Process.output
    ({ cmd := ".lake/build/bin/transport_spec", args := #[] } : IO.Process.SpawnArgs)
  IO.println out7.stdout
  if out7.exitCode != 0 then
    IO.println s!"transport_spec FAILED ({out7.exitCode})"
    return out7.exitCode
  let out8 : IO.Process.Output ← IO.Process.output
    ({ cmd := ".lake/build/bin/registry_spec", args := #[] } : IO.Process.SpawnArgs)
  IO.println out8.stdout
  if out8.exitCode != 0 then
    IO.println s!"registry_spec FAILED ({out8.exitCode})"
    return out8.exitCode
  let out9 : IO.Process.Output ← IO.Process.output
    ({ cmd := ".lake/build/bin/counter_spec", args := #[],
       env := match apalacheMc? with
              | some p => #[("APALACHE_MC", some p)]
              | none => #[] } : IO.Process.SpawnArgs)
  IO.println out9.stdout
  if out9.exitCode != 0 then
    IO.println s!"counter_spec FAILED ({out9.exitCode})"
    return out9.exitCode
  let out10 : IO.Process.Output ← IO.Process.output
    ({ cmd := ".lake/build/bin/async_spec", args := #[],
       env := match apalacheMc? with
              | some p => #[("APALACHE_MC", some p)]
              | none => #[] } : IO.Process.SpawnArgs)
  IO.println out10.stdout
  if out10.exitCode != 0 then
    IO.println s!"async_spec FAILED ({out10.exitCode})"
    return out10.exitCode
  IO.println "ALL LAKE TESTS GREEN"
  return 0

require batteries from git
  "https://github.com/leanprover-community/batteries" @ "v4.33.0"

/-- t32: minimal Windows task-teardown crash repro; NOT run by gates. -/
lean_exe wintaskcrash where
  root := `tools.WinTaskCrash
