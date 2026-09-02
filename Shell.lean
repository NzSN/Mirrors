import Shell.Transport.Stdio
import Shell.Transport.Mock
import Shell.Jobs.Store
import Shell.Apalache.SpecSource
import Shell.Apalache.Cli
import Shell.Apalache.Runner
import Shell.Mirror.Session
import Shell.ModelInterface.Evidence
import Shell.ModelInterface.Cache
import Shell.ModelInterface.Runtime
import Shell.ModelInterface.Auth
import Shell.ModelInterface.Compiler
import Shell.ModelInterface.Emit.TypeScript

/-!
# Layer 3: the effectful shell — trusted, thin, audited (design 5.4)

Transports (Stdio now; TCP/TLS in Phase 6), apalache adapters
(Phase 5), Consul registry client (Phase 6), and
@Shell.Mirror.Session@ which runs @Core.Protocol@ against a
@Shell.Transport.Transport@ as a thin fold.
-/
