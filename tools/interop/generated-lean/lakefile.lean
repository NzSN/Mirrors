import Lake
open Lake DSL
open System (FilePath)

package generatedLeanTransport

require mirrorlean from "./sdk"

lean_lib CounterMirror

target native_tls (pkg : NPackage __name__) : FilePath := do
  let lean ← getLeanInstall
  let output := pkg.buildDir / "native" / "mirrorlean_tls.o"
  let source ← inputFile (pkg.dir / "native" / "mirrorlean_tls.c") false
  buildFileAfterDep output source fun path =>
    compileO output path #["-I", lean.includeDir.toString, "-fPIC"] "cc"

@[default_target]
lean_exe runner where
  root := `Main
  moreLinkObjs := #[`@/native_tls]
  moreLinkArgs := #["-lssl", "-lcrypto"]
