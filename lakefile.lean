import Lake
import Lean
open Lake DSL

/-- t30: shim build/link platform knobs. pkg-config is unavailable on
the windows-dev box, so the OpenSSL include/lib dirs are hardcoded
there (overridable via OSSL_INC / OSSL_LIB env vars) and the socket
shim additionally links ws2_32. The Linux path is unchanged. -/
def winCC : String := "gcc"

def osslInc : IO String := do
  match ← IO.getEnv "OSSL_INC" with
  | some p => pure p
  | none => pure (if System.Platform.isWindows then "/d/Programs/msys2/ucrt64/include" else "")

def osslLib : IO String := do
  match ← IO.getEnv "OSSL_LIB" with
  | some p => pure p
  | none => pure (if System.Platform.isWindows then "/d/Programs/msys2/ucrt64/lib" else "")

/-- t30: link args for exes that use both shims (mirror, registry_spec,
transport_spec). -/
def shimLinkArgs : Array String :=
  if System.Platform.isWindows then
    #[".lake/build/socket_shim.o", ".lake/build/tls_shim.o",
      "-L" ++ "/d/Programs/msys2/ucrt64/lib", "-lssl", "-lcrypto", "-lws2_32"]
  else
    #[".lake/build/socket_shim.o", ".lake/build/tls_shim.o", "-lssl", "-lcrypto"]

/-- t30: link args for exes that use only the socket shim. -/
def sockLinkArgs : Array String :=
  if System.Platform.isWindows then
    #[".lake/build/socket_shim.o", "-lws2_32"]
  else
    #[".lake/build/socket_shim.o"]


package mirrors

@[default_target]
lean_lib Core

@[default_target]
lean_lib Codec

@[default_target]
lean_lib Shell

/-- Phase 0/2: golden wire corpus byte-identity replay (tools/ReplayFixtures.lean). -/
@[default_target]
lean_exe fixtures_replay where
  root := `tools.ReplayFixtures

/-- Phase 1: differential diff-engine test vs the Haskell implementation
(tools/DiffCross.lean, driven by test/fixtures/diff_cases.jsonl). -/
@[default_target]
lean_exe diff_cross where
  root := `tools.DiffCross

/-- Phase 3: the mirror CLI binary (default stdio mode). -/
@[default_target]
lean_exe mirror where
  root := `Main
  extraDepTargets := #[`socket_shim_o, `tls_shim_o]
  moreLinkArgs := shimLinkArgs

/-- Phase 3: stdio session smoke test against the built mirror binary. -/
@[default_target]
lean_exe stdio_smoke where
  root := `tools.StdioSmoke

/-- Phase 4: async job-store parity suite vs the Haskell AsyncJobsSpec
fake-runner workloads (tools/JobStoreSpec.lean). -/
@[default_target]
lean_exe jobstore_spec where
  root := `tools.JobStoreSpec

/-- t14: the C socket shim backing Ffi.Socket (loopback TCP only). -/
/- t14: compile the loopback socket shim with leanc into the build dir
(no extern_lib DSL on this Lake version; mtime-guarded). -/
target socket_shim_o pkg : System.FilePath := do
  let src := pkg.dir / "Ffi" / "socket_shim.c"
  let o := pkg.buildDir / "socket_shim.o"
  let fresh ← do
    let oe ← IO.Process.output { cmd := "test", args := #["-nt", o.toString, src.toString] }
    pure (oe.exitCode == 0)
  if !fresh then do
    let cc ← match (← IO.getEnv "CC") with
      | some c => pure c
      | none => pure (if System.Platform.isWindows then winCC else "cc")
    let leanPrefix ← IO.Process.output { cmd := "lean", args := #["--print-prefix"] }
    let prefixStr := leanPrefix.stdout.trim
    let out ← IO.Process.output
      { cmd := cc, args := #["-c", src.toString, "-o", o.toString,
                             "-I", prefixStr ++ "/include"] }
    if out.exitCode != 0 then
      error s!"leanc failed for socket shim: {out.stderr}"
  inputBinFile o

/- t15: compile the OpenSSL TLS shim with cc + openssl cflags
(pkg-config); mtime-guarded like the socket shim. -/
target tls_shim_o pkg : System.FilePath := do
  let src := pkg.dir / "Ffi" / "tls_shim.c"
  let o := pkg.buildDir / "tls_shim.o"
  let fresh ← do
    let oe ← IO.Process.output { cmd := "test", args := #["-nt", o.toString, src.toString] }
    pure (oe.exitCode == 0)
  if !fresh then do
    let cc ← match (← IO.getEnv "CC") with
      | some c => pure c
      | none => pure (if System.Platform.isWindows then winCC else "cc")
    let leanPrefix ← IO.Process.output { cmd := "lean", args := #["--print-prefix"] }
    let prefixStr := leanPrefix.stdout.trim
    -- t30: pkg-config is broken on windows-dev; hardcode the msys2
    -- ucrt64 OpenSSL include dir there (env-overridable)
    let pcArgs ←
      if System.Platform.isWindows then
        pure #["-I", ← osslInc]
      else
        let pc ← IO.Process.output { cmd := "pkg-config", args := #["--cflags", "openssl"] }
        pure (((pc.stdout.trim.splitOn " ").filter (· != "")).toArray)
    let out ← IO.Process.output
      { cmd := cc, args := #["-c", src.toString, "-o", o.toString,
                             "-I", prefixStr ++ "/include"] ++ pcArgs }
    if out.exitCode != 0 then
      error s!"cc failed for TLS shim: {out.stderr}"
  inputBinFile o

@[default_target]
lean_lib Ffi where
  globs := #[.submodules `Ffi]

/-- Phase 5: apalache CLI adapter regression suite
(tools/ApalacheCliSpec.lean; real-apalache integration runs only with
APALACHE_MC set, self-skipping otherwise). -/
@[default_target]
lean_exe apalache_cli_spec where
  root := `tools.ApalacheCliSpec
  extraDepTargets := #[`socket_shim_o]
  moreLinkArgs := sockLinkArgs

/-- t14: explorer HTTP/JSON-RPC spike, transcript parity, and the
HourClock explorer end-to-end (real apalache integration runs only
with APALACHE_MC set, self-skipping otherwise). -/
@[default_target]
lean_exe explorer_spec where
  root := `tools.ExplorerSpec
  extraDepTargets := #[`socket_shim_o]
  moreLinkArgs := sockLinkArgs

/-- t15: TCP + mTLS transport regression suite (generates a throwaway
PKI with the openssl CLI at test time; skips itself when the openssl
CLI is missing). -/
@[default_target]
lean_exe transport_spec where
  root := `tools.TransportSpec
  extraDepTargets := #[`socket_shim_o, `tls_shim_o]
  moreLinkArgs := shimLinkArgs

/-- t16: registry/discovery + signal-handling gate (mock Consul via
python3; the SIGTERM tier needs the openssl CLI for a throwaway PKI
and self-skips that tier without it). -/
@[default_target]
lean_exe registry_spec where
  root := `tools.RegistrySpec
  extraDepTargets := #[`socket_shim_o, `tls_shim_o]
  moreLinkArgs := shimLinkArgs

/-- Counter end-to-end: register flow (validate + trace-gen + replay)
against test/specs/Counter.tla with a scripted echo client; ports the
intent of the stale upstream MainSpec.testCounterEndToEnd with corrected
expectations (tools/CounterSpec.lean; APALACHE_MC-gated, self-skips). -/
@[default_target]
lean_exe counter_spec where
  root := `tools.CounterSpec

/--- t31: REAL async flows over live mirror server children (plain TCP
and mTLS modes) against real apalache (tools/AsyncSpec.lean; runs only
with APALACHE_MC set, self-skipping otherwise). -/
@[default_target]
lean_exe async_spec where
  root := `tools.AsyncSpec
  extraDepTargets := #[`socket_shim_o, `tls_shim_o]
  moreLinkArgs := shimLinkArgs

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
