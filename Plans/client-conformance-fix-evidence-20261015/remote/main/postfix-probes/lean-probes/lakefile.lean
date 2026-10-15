import Lake
open Lake DSL System

package "mirrorlean-audit-probes"

-- Remote layout: this owned probe package is a sibling of the read-only
-- MirrorLean source snapshot (or a sibling symlink named MirrorLean).
require mirrorlean from "../MirrorLean"

target audit_tls (pkg : NPackage __name__) : FilePath := do
  let lean ← getLeanInstall
  let srcJob ← inputFile (pkg.dir / ".." / "MirrorLean" / "server-mode" / "native" / "mirrorlean_tls.c") false
  buildFileAfterDep (pkg.buildDir / "native" / "audit_tls.o") srcJob fun src => do
    compileO (pkg.buildDir / "native" / "audit_tls.o") src #["-I", lean.includeDir.toString, "-fPIC"] "cc"

lean_exe "closure-probe" where
  root := `ClosureProbe

lean_exe "tls-identity-probe" where
  root := `TlsIdentityProbe
  moreLinkObjs := #[`@/audit_tls]
  moreLinkArgs := #["-lssl", "-lcrypto"]
