# General TLA+ frontend for Mirrors

> Status: **proposed design only; no implementation is claimed**
>
> Parent compiler design: [model-interface compiler](design.md)
>
> Implementation plan: [TLA+ frontend tasks](tla-frontend-tasks.md)
>
> Affected implementation areas: `Shell/Apalache/SpecSource.lean`,
> `Shell/ModelInterface/SpecVariables.lean`, and
> `Shell/ModelInterface/Compiler.lean`

## 1. Decision

Mirrors should provide a native, reusable TLA+ frontend with three distinct
stages:

1. a lossless parser produces concrete syntax with stable source spans;
2. a module resolver constructs a bounded source graph; and
3. a semantic elaborator resolves declarations, scopes, arities, module
   instances, and expression levels.

The model-interface compiler consumes the frontend's elaborated model facts. It
must not scan the root file independently for variables or dependencies.

The frontend is broader than the immediate inherited-variable fix, but it is
not a model checker, evaluator, type checker for arbitrary Apalache annotations,
or proof checker. Apalache remains the execution backend. During development,
SANY and Apalache serve as differential compatibility oracles rather than
runtime dependencies of ordinary offline interface generation.

### 1.1 Why a native frontend

The existing compiler is an offline Lean executable with pure resolution and
deterministic emission. A native frontend preserves that deployment shape,
makes captured source facts available to Lean callers without a second process,
and allows one parsed graph to serve compiler and server paths. Its cost is a
large grammar and conformance obligation. The design pays that cost explicitly
through staged delivery and differential tests; it does not claim that native
code is automatically more correct than established TLA+ tooling.

## 2. Motivation

Mirrors currently has two intentionally narrow source scanners:

- `Shell.Apalache.SpecSource` discovers local `EXTENDS` and `INSTANCE`
  dependencies for snapshotting and source digests; and
- `Shell.ModelInterface.SpecVariables` extracts `VARIABLE` and `VARIABLES`
  declarations from one source string for scaffold and trace-projection
  admission.

Those scanners do not share a parsed module representation. The model-interface
compiler follows a dependency closure for provenance, while scaffold validates
evidence variables against declarations from only the root file. A composed
module can therefore execute correctly through the full TLA+ loader but fail
scaffold admission.

For example:

```tla
---------------- MODULE Base ----------------
VARIABLE x
=============================================
```

```tla
---------------- MODULE Transfer ------------
EXTENDS Base
VARIABLE y
=============================================
```

The effective state variables of `Transfer` are `x` and `y`. A root-only lexical
scan returns only `y`. Rejecting unexplained evidence variables is correct; the
source analysis supplying the explanation is incomplete.

Adding more independent scanners would spread TLA+ knowledge across callers.
A frontend creates one deep module: callers ask for parsed or elaborated facts,
while grammar, scope, substitution, traversal, diagnostics, and limits remain in
one implementation.

## 3. Goals

The frontend must:

- parse the executable TLA+ module language used by Mirrors models;
- retain comments, whitespace, spelling, and precise source spans in a lossless
  concrete syntax tree;
- produce a normalized abstract syntax tree for semantic consumers;
- resolve local and standard-module dependencies deterministically;
- distinguish `EXTENDS`, named `INSTANCE`, unnamed `INSTANCE`, and `LOCAL`;
- elaborate module parameters, declarations, operator scopes, arities, and
  instance substitutions;
- compute effective constants, variables, and operator declarations with their
  origins;
- classify expressions by constant, state, action, or temporal level;
- expose bounded structured diagnostics;
- preserve current source-byte identities and source-closure provenance;
- support borrowed files and caller-supplied inline source maps;
- terminate under explicit byte, token, nesting, module, edge, declaration, and
  diagnostic limits; and
- give the model-interface compiler one consistent source/evidence admission
  result across `scaffold`, `project-trace`, `resolve`, and `check`.

## 4. Non-goals

The first completed frontend does not:

- evaluate TLA+ expressions;
- enumerate states or traces;
- replace Apalache or TLC;
- prove invariants;
- check TLAPS proofs;
- infer implementation-facing types from arbitrary expressions;
- change the Mirrors JSONL model protocol;
- change generated MirrorECMA or MirrorCPP runtime contracts;
- canonicalize source by reprinting an AST;
- silently repair invalid modules;
- accept syntax merely because error recovery produced a partial tree; or
- expose private model source through MirrorGate or an LLM task.

PlusCal translation is also outside the initial semantic scope. The frontend
preserves algorithm text and translation markers as trivia, but consumes the
translated TLA+ module as the executable authority. A later PlusCal parser needs
its own design and provenance contract.

## 5. Compatibility authority

Mirrors must not define an accidental TLA+ dialect. The frontend records a
versioned language profile that identifies:

- the accepted module and expression grammar;
- supported Unicode and ASCII operator spellings;
- standard-module names and revisions;
- module-instantiation and substitution semantics;
- level-checking rules;
- proof-language treatment; and
- known intentional differences from the selected SANY and Apalache baselines.

Acceptance requires differential corpora against pinned versions of both tools.
A module accepted by Mirrors but rejected by both compatibility oracles is a
frontend finding unless an explicit profile difference covers it. A module
rejected by Mirrors but accepted by the baselines is either a documented limit
or a defect; it must never be silently classified as malformed evidence.

Compatibility is compared at several levels:

| Level | Compared result |
| --- | --- |
| Lexical | token boundaries, spellings, comments, strings, and locations |
| Syntactic | module/declaration/expression shape and parse success/failure |
| Resolution | dependency identities, visible names, origins, and arities |
| Elaboration | instance substitutions and expression levels |
| Execution handoff | root module, source closure, and bytes given to Apalache |

Exact external error wording is not a compatibility requirement. Mirrors uses
stable diagnostic codes plus structured arguments and source ranges.

## 6. Architecture

The frontend is split between pure domain logic and effectful source loading:

```text
borrowed directory / inline source map / standard-module catalog
                              |
                              v
                   Shell.Tla.SourceProvider
                  bounded reads and identity checks
                              |
                              v
                        Core.Tla.Parser
                 tokens + lossless concrete syntax
                              |
                              v
                    Shell.Tla.ModuleResolver
             requests dependencies through SourceProvider
                              |
                              v
                      Core.Tla.Elaborator
       names + substitutions + arities + levels + effective facts
                              |
                +-------------+--------------+
                |                            |
                v                            v
       model_interface_gen             Apalache snapshot
     scaffold/resolve/check       exact captured source closure
```

Suggested modules:

```text
Core/Tla/Source.lean
Core/Tla/Token.lean
Core/Tla/Syntax.lean
Core/Tla/Lexer.lean
Core/Tla/Parser.lean
Core/Tla/Names.lean
Core/Tla/Elaboration.lean
Core/Tla/Level.lean
Core/Tla/Diagnostic.lean
Shell/Tla/SourceProvider.lean
Shell/Tla/ModuleResolver.lean
Shell/Tla/Frontend.lean
tools/TlaFrontendCli.lean
```

The existing `Shell.Apalache.SpecSource` retains ownership of materializing and
releasing Apalache inputs until migration completes. Its dependency scanner and
the model-interface variable scanner are removed only after all existing callers
use the frontend and their replacement gates pass.

## 7. Frontend interface

The main shell interface accepts a root reference, a source provider, a language
profile, and limits:

```lean
namespace Shell.Tla

structure FrontendRequest where
  root : Core.Tla.ModuleRef
  profile : Core.Tla.LanguageProfile
  limits : FrontendLimits := {}

structure FrontendResult where
  root : Core.Tla.ModuleName
  graph : Core.Tla.ResolvedModuleGraph
  elaborated : Core.Tla.ElaboratedModule
  sourceManifest : List Core.Tla.SourceIdentity
  diagnostics : List Core.Tla.Diagnostic

def analyze
    (provider : SourceProvider)
    (request : FrontendRequest) :
    IO (Except FrontendFailure FrontendResult)

end Shell.Tla
```

Callers do not orchestrate recursive loading, merge variable lists, interpret
substitutions, or sort provenance. The interface returns either a complete,
usable result with no error diagnostics or a failure with bounded diagnostics.
A partial syntax tree may be retained internally for diagnostics, but it cannot
cross the successful result path.

### 7.1 Two source-provider adapters

Two source forms already exist and justify one real seam:

```lean
structure SourceProvider where
  readRoot : ModuleRef → IO (Except SourceReadError SourceUnit)
  readDependency : ModuleName → IO (Except SourceReadError SourceUnit)
  resolveStandard : ModuleName → IO (Except SourceReadError StandardModule)
```

- `BorrowedDirectoryProvider` resolves sibling files beneath one pinned root
  directory and rejects symlinks, special files, escapes, size overflow, and
  identity changes.
- `InlineSourceProvider` resolves only entries in a caller-supplied closed source
  map and exposes no filesystem path.

Providers return logical names and captured bytes. They do not parse source or
decide TLA+ semantics.

## 8. Source units and identity

```lean
structure SourceUnit where
  logicalPath : String
  normalizedText : String
  normalizedUtf8 : ByteArray
  contentSha256 : String
  origin : SourceOrigin
```

The frontend owns a compiler-independent manifest identity:

```lean
structure SourceIdentity where
  moduleName : ModuleName
  logicalPath : String
  contentSha256 : String
```

The model-interface shell converts it to the existing lock `SourceDigest` at its
adapter seam. The general TLA+ frontend does not depend on model-interface types.

Line endings are normalized exactly as current model-source hashing specifies:
CRLF and CR become LF. Hashes remain over normalized UTF-8 source bytes, not an
AST or pretty-printed form. Whitespace and comment changes therefore continue
to change source provenance.

Local absolute paths never enter locks, generated output, or public diagnostics.
Trusted diagnostics may attach an internal physical location while the public
source name remains logical.

The loader captures each source once per analysis. Parsing, elaboration, source
digests, scaffold admission, and any subsequent Apalache snapshot use those same
captured bytes. A changed source produces a new analysis; it cannot be combined
with facts from an earlier read.

## 9. Lexer

The lexer is pure and total under limits:

```lean
def lex (profile : LanguageProfile) (limits : LexerLimits)
    (source : SourceUnit) : Except (List Diagnostic) TokenStream
```

Each token contains:

```lean
structure Token where
  kind : TokenKind
  spelling : String
  range : SourceRange
  leadingTrivia : Array Trivia
  trailingTrivia : Array Trivia
```

`SourceRange` uses half-open offsets into normalized UTF-8 bytes and also stores
one-based line and Unicode-scalar column coordinates. Byte offsets make slicing
unambiguous; line/column coordinates make diagnostics readable.

The lexer recognizes:

- identifiers and qualified names;
- decimal integers and supported numeric spellings;
- strings and escapes;
- punctuation;
- ASCII and Unicode operator aliases;
- reserved words;
- line comments;
- nested block comments;
- module-header and module-end delimiters; and
- Apalache/TLAPS annotations as structured comment trivia where applicable.

Invalid UTF-8, isolated surrogate representations, unterminated strings or
comments, excessive comment nesting, oversized tokens, and unknown control
characters are errors. The lexer never drops invalid bytes and continues as if
the source were valid.

## 10. Concrete and abstract syntax

The concrete syntax tree (CST) is lossless. It supports diagnostics, source
tools, formatter experiments, and future model-aware diffs without changing
semantic consumers.

The abstract syntax tree (AST) removes trivia and normalizes equivalent operator
spellings while retaining source ranges:

```lean
structure ParsedModule where
  name : ModuleName
  declarations : Array Declaration
  range : SourceRange

inductive Declaration where
  | constant (names : Array OperatorDecl)
  | variable (names : Array NameDecl)
  | recursive (operators : Array OperatorDecl)
  | operator (definition : OperatorDefinition)
  | local (declaration : Declaration)
  | instance (declaration : InstanceDeclaration)
  | assumption (declaration : Assumption)
  | theorem (declaration : Theorem)
```

Expression syntax covers the executable TLA+ language, including:

- names, literals, tuples, records, sets, and functions;
- operator application and user-defined infix/prefix/postfix operators;
- `IF/THEN/ELSE`, `CASE`, `LET/IN`, and `CHOOSE`;
- bounded and unbounded quantification;
- function and set comprehensions;
- record/function selection and `EXCEPT` updates;
- priming, `ENABLED`, and `UNCHANGED`;
- action composition and fairness operators; and
- temporal operators and quantified temporal expressions.

Proof bodies are retained with source spans. Until a proof grammar and checker
are implemented, they are not elaborated and cannot contribute model-interface
facts. The parser must still find the following top-level declaration reliably.

## 11. Parsing behavior

The parser uses explicit precedence and associativity tables owned by the
language profile. User-defined operators do not alter parser precedence; TLA+
operator spellings and fixities are defined by the language.

Diagnostics use bounded recovery at declaration and delimiter synchronization
points. Recovery exists to report more than one useful error. Any error-severity
diagnostic makes the module unusable.

The parser must distinguish syntax that narrow token scans commonly confuse:

- `EXTENDS` inside comments or strings;
- `INSTANCE` nested in an operator definition;
- module names versus qualified operator names;
- commas belonging to declarations versus expressions;
- proof steps that resemble declarations;
- nested `LET` declarations;
- unary minus versus an infix operator; and
- ASCII/Unicode aliases with overlapping prefixes.

Parser implementation technique is not fixed by this design. A hand-written
recursive-descent/Pratt parser is acceptable if grammar tables are explicit and
the conformance corpus covers every production. Generated parser machinery is
acceptable only if its generator and grammar become pinned build inputs and its
output remains reproducible.

## 12. Module graph resolution

The module resolver parses a module before requesting its dependencies. It
retains dependency kind and declaration location:

```lean
inductive DependencyKind where
  | extends
  | namedInstance
  | unnamedInstance

structure ModuleEdge where
  owner : ModuleName
  dependency : ModuleName
  kind : DependencyKind
  local : Bool
  substitutions : Array Substitution
  range : SourceRange
```

The resolved graph contains one captured module per logical identity, ordered
canonically for output while retaining source declaration order on edges.

Resolution rules:

1. The requested root's declared module name must match its expected identity.
2. Local module names resolve through the selected provider only.
3. Known standard modules resolve through the pinned standard-module catalog.
4. Missing nonstandard dependencies fail.
5. Two sources declaring the same module name fail.
6. Dependency cycles fail with the complete bounded cycle path.
7. A diamond graph parses and elaborates a shared module once.
8. Resource limits apply before allocating an unbounded graph or diagnostic.

The current source resolver treats a missing known standard module as external.
The frontend makes that choice explicit in `StandardModule`; it does not silently
invent declarations for a standard module it does not understand.

## 13. Semantic elaboration

Parsing answers what text was written. Elaboration answers what each name means.
The elaborator is pure over a resolved module graph and standard-module facts:

```lean
def elaborate
    (profile : LanguageProfile)
    (limits : ElaborationLimits)
    (graph : ResolvedModuleGraph) :
    Except (List Diagnostic) ElaboratedModule
```

### 13.1 Names and scopes

The elaborator assigns stable analysis-local symbol IDs and resolves:

- module constants and variables;
- operator definitions and formal parameters;
- bound variables in quantifiers and comprehensions;
- `LET` definitions;
- qualified instance names;
- unqualified declarations introduced by `EXTENDS` or unnamed instances; and
- `LOCAL` visibility.

Symbol IDs are not persisted as semantic identities. Persisted artifacts use
module/name/origin records and source hashes.

Shadowing, duplicate declarations, ambiguous imports, unknown names, and arity
mismatches produce errors with primary and related declaration locations.

### 13.2 Operator arity

Every operator symbol has an arity, including higher-order operator parameters.
Elaboration validates application counts and substitution compatibility before
the model-interface compiler consumes a declaration.

### 13.3 Expression levels

The frontend classifies expressions and operators as:

```text
constant < state < action < temporal
```

Level constraints follow TLA+ substitution and application rules. Level checking
is required before claiming a general semantic frontend because an instance can
be syntactically valid while violating semantic level constraints.

Model-interface generation does not use level information initially, but storing
it prevents every future source tool from reimplementing the analysis.

## 14. `EXTENDS` semantics

`EXTENDS M` makes the eligible declarations of `M` available unqualified in the
extending module. Effective declarations are computed from the elaborated graph,
not by concatenating filenames.

For effective state variables:

```text
effectiveVariables(M) =
  stableUnique(
    effectiveVariables(each directly extended module in source order)
    ++ variables declared directly by M
  )
```

`stableUnique` deduplicates the same resolved declaration reached through a
diamond. Two different declarations with the same visible name are an ambiguity,
not a deduplication.

Each result retains its origin and import path:

```lean
structure ResolvedVariable where
  symbol : SymbolId
  visibleName : Name
  declaredName : Name
  declaredIn : ModuleName
  declarationRange : SourceRange
  importPath : Array ModuleEdgeId
```

This directly resolves the root-only scaffold failure without weakening exact
evidence admission.

## 15. `INSTANCE` and substitution semantics

The frontend must never treat all variables from every `INSTANCE` dependency as
root state variables. An instance may substitute a child variable with a parent
expression or expose definitions only through a qualified name.

```tla
ChildInstance == INSTANCE Child
  WITH childState <- parentState
```

Elaboration must:

- resolve every substituted child declaration;
- validate the substituted expression or operator arity;
- apply level constraints;
- distinguish qualified from unqualified visibility;
- retain the child source in provenance;
- map references in instantiated definitions to substituted parent symbols; and
- determine whether any unsubstituted state declaration is visible in the root.

Until these rules pass conformance tests, the frontend may land `EXTENDS`
support first, but it must reject variable-bearing `INSTANCE` analysis with a
specific unsupported diagnostic. It must not guess or silently union variables.

## 16. Effective model facts

The elaborated root exposes a small interface for downstream tools:

```lean
structure EffectiveModelFacts where
  moduleName : ModuleName
  constants : Array ResolvedConstant
  variables : Array ResolvedVariable
  operators : Array ResolvedOperator
  assumptions : Array ResolvedAssumption
  sourceManifest : Array SourceIdentity
```

The model-interface compiler initially consumes:

- `moduleName`;
- the exact effective variable set and declaration origins;
- the normalized source manifest; and
- diagnostics.

It continues to obtain structural value types from reviewed contract assertions
or typed ITF evidence. A general parser does not make arbitrary TLA+ expression
types mechanically available to the current generated targets.

Later compiler milestones may use elaborated action definitions or annotations,
but sampled actions never become an authoritative closed action universe. Human
review and sealing remain required.

## 17. Model-interface compiler integration

### 17.1 One source-analysis path

`model_interface_gen scaffold`, `project-trace`, `resolve`, and `check` call the
same frontend with the same language profile and source limits.

The current split is removed:

```text
before
  resolve/check -> borrowedSourceDigests
  scaffold      -> read root -> SpecVariables.extract
  project-trace -> read root -> SpecVariables.extract

after
  every command -> TlaFrontend.analyze -> FrontendResult
```

### 17.2 Evidence admission

Evidence variables must equal the elaborated effective variables as sets:

```text
sourceOnly   = effectiveVariables − evidence.traceVars
evidenceOnly = evidence.traceVars − effectiveVariables
```

Either nonempty set is an error. Diagnostics name the declaring module for
source-only variables. For evidence-only variables, diagnostics list similarly
spelled declarations and the modules searched, without claiming a source origin
that was not resolved.

Parameter variables remain part of raw evidence admission and are removed only
by the existing explicit run-profile partition. Trace projection remains an
explicit, receipted representation change and cannot hide a source/evidence
mismatch.

### 17.3 Scaffold proposals

A new scaffold proposal revision should carry:

- root module identity;
- complete sorted source manifest;
- effective variables and declaration origins;
- frontend language/semantics profile;
- raw evidence digest;
- optional projection plan/output digests; and
- observed initializer/transition labels, still marked unsealed.

A dependency edit therefore invalidates the proposal even when the root file is
unchanged. Proposal review still decides public stable IDs, projections,
observations, action phases, and the closed action universe.

### 17.4 Resolve and check

`resolve` validates the reviewed contract and structural evidence only after the
frontend has established their source relationship. `check` repeats the exact
analysis in memory and writes nothing.

The frontend does not change the semantic descriptor merely because a variable
origin moved between source modules. Contract semantics determine the descriptor;
the complete source manifest and frontend profile belong to provenance.

### 17.5 Generated targets

Emitters consume only a verified lock. They do not import the frontend or parse
TLA+ independently. Existing targets remain:

- `mirrorecma-v1`;
- `mirrorecma-async-v1`; and
- `mirrorcpp-v1`.

No model protocol, StateComputer contract, public-port RPC, or MirrorGate control
record changes as part of the frontend.

## 18. Apalache integration

The frontend and Apalache must receive the same captured source closure. The
frontend result may therefore provide a snapshot publication input, but
`Shell.Apalache.SpecSource` continues to own temporary-directory lifecycle.

```text
captured source units
        |                    |
        v                    v
frontend analysis      snapshot publication
        |                    |
        +---- same hashes ---+
```

The frontend does not rewrite source before execution. Apalache receives the
normalized captured bytes under the same logical filenames used for provenance.
If Apalache rejects a frontend-accepted module, the run fails and records a
compatibility diagnostic; it never falls back to a different source read.

## 19. Standard modules

The current hardcoded known-name list is insufficient for semantic elaboration.
The frontend uses a versioned standard-module catalog:

```lean
structure StandardModuleCatalog where
  profile : StandardModuleProfile
  modules : Array StandardModule

structure StandardModule where
  name : ModuleName
  declarations : Array StandardDeclaration
  contentIdentity : Option String
```

The catalog distinguishes:

- language-defined modules with frontend-owned declaration facts;
- Apalache extension modules pinned to an Apalache compatibility profile; and
- filesystem-supplied modules that must be captured like application sources.

Changing catalog semantics invalidates the frontend cache and must be visible in
compiler provenance. A name in a list is not enough to invent operator arities
or variable facts.

## 20. Diagnostics

```lean
structure Diagnostic where
  code : String
  severity : Severity
  stage : DiagnosticStage
  message : String
  primary : SourceLocation
  related : Array RelatedLocation
  arguments : Array (String × String)
```

Stages are `lex`, `parse`, `moduleGraph`, `nameResolution`, `substitution`,
`level`, and `sourceEvidence`.

Example inherited-variable success information may be emitted only in verbose
or inspection output:

```text
caseStatus: declared in DumpLedger.tla, visible through
DumpLedgerTransfer.tla EXTENDS DumpLedger
```

A genuine mismatch is an error:

```text
MIC-S-SOURCE-001
evidence variable oldStatus has no effective declaration in DumpLedgerTransfer
```

Diagnostics obey count and byte limits. Rendering is separate from diagnostic
construction so JSON and human output contain the same facts.

## 21. Resource and security limits

Frontend inputs are untrusted compiler inputs. The limit interface must cover at
least the following dimensions; these candidate values require measurement
against the conformance corpus:

```lean
structure FrontendLimits where
  maxModules : Nat := 128
  maxDependencyDepth : Nat := 64
  maxDependencyEdges : Nat := 4096
  maxFileBytes : Nat := 4 * 1024 * 1024
  maxTotalSourceBytes : Nat := 16 * 1024 * 1024
  maxTokensPerModule : Nat := 1_000_000
  maxSyntaxDepth : Nat := 1024
  maxDeclarations : Nat := 65536
  maxSymbols : Nat := 262144
  maxSubstitutionWork : Nat := 1_000_000
  maxDiagnostics : Nat := 256
  maxDiagnosticBytes : Nat := 1 * 1024 * 1024
```

Exact defaults remain an implementation decision and require adversarial tests.
The contract is that every recursive structure has a checked bound before
unbounded allocation or traversal.

Borrowed-file rules retain current protections:

- one approved root directory;
- canonical logical `.tla` names;
- no symlinks or special files;
- no parent traversal or alternate extension probing;
- bounded reads;
- module header/filename agreement; and
- identity/content consistency across analysis and snapshot publication.

Parser recovery, recursive expressions, nested comments, dependency graphs,
instance substitution, and diagnostic accumulation require independent resource
budgets. Stack overflow or process exhaustion is never an ordinary parse error.

## 22. Determinism and caching

Pure parsing and elaboration are deterministic functions of:

- normalized captured source bytes;
- logical module identities;
- language profile;
- standard-module profile; and
- frontend limits that affect acceptance.

Any cache key contains those identities. Filesystem timestamps, physical paths,
process environment, current directory, and diagnostic rendering format are not
semantic cache inputs.

Cached success contains no open handle or physical path. Cached failure is safe
only when keyed by the complete captured input and frontend profile. A cache hit
cannot bypass current borrowed-source admission or reuse a result after source
identity changes.

## 23. Versioning and existing artifacts

The frontend introduces three separately versioned concerns:

1. syntax/language profile;
2. elaboration semantics profile; and
3. standard-module catalog profile.

The current source digest remains unchanged because it hashes normalized source
bytes. Existing model-interface semantic digests remain unchanged when the
reviewed contract and resolved types are unchanged.

Self-contained version-1 fixtures should retain byte-identical locks and
generated output. Accepting a previously rejected composed module is a capability
extension, not a reason to change target-profile or worker-wire versions.

If new profile fields are added to lock provenance, use a new compatible lock
schema revision or a deliberately versioned migration. Do not silently insert
fields into canonical version-1 bytes. Scaffold proposals can move to a new
schema because they are unsealed review artifacts, but existing proposal inputs
must either migrate explicitly or continue through a compatibility reader.

An AST hash is not introduced in the first delivery. If a future feature needs
semantic source identity independent of formatting, it requires a separate
domain-separated digest and canonical AST specification.

## 24. Inspection tool

Development tooling should use a separate executable, not enlarge the
operational `mirror` CLI:

```text
tla_frontend parse --spec FILE [--format json]
tla_frontend resolve --spec FILE [--format json]
tla_frontend inspect --spec FILE
  [--variables] [--dependencies] [--operators] [--levels]
```

`parse` reports syntax only. `resolve` performs full graph resolution and
elaboration. `inspect` projects approved facts from the same result. JSON output
uses a closed, versioned diagnostic/inspection schema and never includes local
absolute paths by default.

`model_interface_gen` should not require users to run this tool first. It calls
the frontend module directly. The executable exists for debugging, editor
integration, corpus generation, and differential tests.

## 25. Testing strategy

### 25.1 Pure lexer/parser tests

- one fixture for every grammar production and operator spelling;
- nested comments, strings, escapes, Unicode, CRLF normalization, and malformed
  byte cases;
- precedence/associativity goldens;
- source-range and trivia round trips;
- bounded recovery with multiple diagnostics;
- deeply nested and oversized adversarial inputs; and
- mutation/fuzz tests that assert termination and deterministic diagnostics.

### 25.2 Module-resolution tests

- direct and transitive `EXTENDS`;
- dependency diamonds;
- cycles;
- missing dependencies;
- filename/header mismatches;
- duplicate module identities;
- standard versus local module selection;
- comments/strings containing fake dependency keywords;
- borrowed symlink, special-file, escape, size, and mutation cases; and
- inline/borrowed adapters producing equivalent logical graphs.

### 25.3 Elaboration tests

- inherited and local declarations;
- ambiguous imports and legal diamond reuse;
- operator arity and higher-order parameters;
- bound-name and `LET` scopes;
- named and unnamed instances;
- complete, partial, invalid, and chained substitutions;
- constant/state/action/temporal level constraints;
- `LOCAL` visibility; and
- related-location diagnostics for every conflict.

### 25.4 Differential conformance

Maintain a pinned corpus with:

- accepted executable modules;
- rejected modules grouped by lexical, syntactic, resolution, arity, and level
  failure;
- standard-module usage;
- real repository models;
- SANY results;
- Apalache parse/typecheck results where applicable; and
- an explicit allowlist of reviewed profile differences.

Differential tests compare outcomes and structural facts, not unstable prose.
Corpus updates require a reviewed tool-version or language-profile change.

### 25.5 Model-interface integration

Required cases include:

- all existing self-contained compiler goldens remain byte-identical;
- an extended base variable is accepted as evidence for the root;
- a stale variable absent from the effective closure is rejected;
- changing a dependency invalidates `check`;
- scaffold and project-trace use the same effective variables;
- resolve/check cannot accept source/evidence pairs that scaffold rejects;
- generated TypeScript and C++ targets still compile; and
- preflight behavior remains unchanged after lock construction.

## 26. DumpLedgerTransfer acceptance fixture

The motivating cross-repository acceptance case uses:

```text
DumpLedger.tla
  12 directly declared variables
        ^
        | EXTENDS
DumpLedgerTransfer.tla
  7 directly declared variables
```

The frontend must report nineteen effective variables with exact declaration
origins. Acceptance requires:

1. resolve the complete local source closure once;
2. scaffold from an actual nineteen-variable transfer ITF trace;
3. report no evidence-only inherited variables;
4. preserve exact source/evidence rejection for a fabricated twentieth variable;
5. seal or hand-review the resulting contract through the existing review
   workflow;
6. resolve and generate `mirrorecma-async-v1`;
7. preflight the approved transfer trace corpus;
8. run the reusable MBT harness against a correct implementation;
9. reject a deliberate transfer implementation defect; and
10. confirm MirrorGate worker and session cleanup for the sandboxed path.

A transitive scenario module that `EXTENDS DumpLedgerTransfer` must resolve the
same nineteen variables unless it declares additional state. This prevents a
fix narrowly special-cased to one dependency depth.

## 27. Delivery phases

### Phase 0: Freeze the profile and corpus

- choose pinned SANY/Apalache compatibility baselines;
- inventory syntax used by Mirrors and sibling application models;
- publish grammar/profile decisions and limits; and
- capture accepted/rejected differential fixtures.

Exit: every supported production and intentional omission has an owned test.

### Phase 1: Lossless lexer and parser

- add source/token/CST/AST/diagnostic types;
- implement module and expression parsing;
- retain trivia and source spans; and
- add pure and fuzz/resource tests.

Exit: syntax corpus and parser differential gate pass; no production caller is
migrated.

### Phase 2: Source providers and module graph

- add borrowed and inline providers;
- build typed dependency edges;
- integrate standard-module identity;
- preserve current snapshot and digest rules; and
- run filesystem adversarial gates.

Exit: the new graph produces the same source manifest as current valid closures.

### Phase 3: `EXTENDS` elaboration and compiler unblock

- resolve declarations, scopes, arities, and `EXTENDS` visibility;
- expose effective variables with origins;
- migrate scaffold/project-trace evidence admission;
- migrate resolve/check to the same admission path; and
- pass the DumpLedgerTransfer fixture.

Exit: composed-module variables work; variable-bearing `INSTANCE` remains an
explicit unsupported error rather than an approximation.

### Phase 4: `INSTANCE`, substitutions, and levels

- elaborate named and unnamed instances;
- implement substitution and visibility rules;
- implement level constraints; and
- expand differential conformance.

Exit: supported instance fixtures agree with the compatibility baselines and no
instance fallback remains in production source analysis.

### Phase 5: Unified snapshot and removal of scanners

- feed the same captured closure to analysis and Apalache publication;
- remove `SpecVariables` and token-based dependency discovery from production;
- retain compatibility wrappers only where needed during migration; and
- update compiler designs, interface references, and usage documentation.

Exit: one frontend owns TLA+ source interpretation across all compiler commands.

### Phase 6: Inspection and ecosystem gates

- publish the separate inspection executable;
- add machine-readable diagnostics;
- run Mirrors, MirrorECMA, MirrorCPP, and MirrorGate integration gates; and
- document the supported language profile and remaining proof/PlusCal limits.

Exit: the frontend is usable as a framework capability rather than only an
internal blocker fix.

## 28. Acceptance criteria

The frontend is complete for production use only when:

1. every successful result comes from a fully parsed and elaborated captured
   source graph;
2. syntax or semantic errors cannot enter model-interface resolution through a
   partial recovery tree;
3. `EXTENDS` and supported `INSTANCE` semantics agree with pinned compatibility
   baselines;
4. source closure, effective declarations, and evidence admission are identical
   across compiler commands;
5. self-contained version-1 locks and generated outputs remain stable;
6. dependency changes invalidate provenance and checks;
7. all resource limits have exact boundary tests;
8. borrowed and inline sources have equivalent logical semantics;
9. Apalache executes the exact captured bytes analyzed by the frontend;
10. the DumpLedgerTransfer correct/faulty MBT pair passes its expected outcomes;
11. no private model facts are added to worker or agent-facing interfaces; and
12. the old independent scanners have no production callers.

## 29. Rejected designs

### 29.1 Allow evidence variables missing from the root file

Rejected. `--allow-extra-evidence-vars` would remove the source/evidence safety
property and allow stale or fabricated state into generated contracts.

### 29.2 Concatenate variables from every dependency

Rejected. It loses declaration identity, mishandles diamonds, and is incorrect
for qualified instances and substitutions.

### 29.3 Add `--variable-source` flags

Rejected as the primary interface. Callers would need to understand and recreate
module semantics, producing a shallow compiler interface and inconsistent CI.

### 29.4 Flatten source before compilation

Rejected as the framework design. A generated flattened model can drift,
obscures declaration provenance, and introduces another canonicalization and
identity problem. A manually reviewed standalone model remains a temporary
application workaround, not the compiler solution.

### 29.5 Invoke Apalache for every compiler command

Rejected for the default path. `resolve`, `generate`, and `check` are designed to
work from pinned local inputs without live model execution. An optional external
oracle belongs in conformance or explicit validation modes.

### 29.6 Embed a JVM frontend without a stable adapter contract

Rejected. Process availability and human-oriented output are not a reproducible
compiler interface. A future SANY adapter would require pinned versions, bounded
machine-readable output, exact source identity, cancellation, and error mapping.

### 29.7 Parse separately in every emitter or client

Rejected. Emitters consume verified locks, and clients consume generated
bindings. TLA+ interpretation remains centralized in Mirrors.

### 29.8 Hash or emit pretty-printed AST source

Rejected initially. It would change source identity and make parser formatting a
hidden semantic input. Current normalized-byte hashing remains authoritative.

## 30. Open decisions

The implementation plan must resolve these before Phase 1:

1. Which exact TLA+ grammar and SANY/Apalache versions define the first language
   profile?
2. Does the initial parser structurally parse TLAPS proofs or retain bounded
   proof regions as opaque syntax?
3. Which Apalache annotations become structured frontend facts, and which remain
   trivia?
4. What are the measured default limits for large real modules?
5. How is the standard-module catalog sourced and versioned?
6. Is parser generation acceptable in the Lean build, or must the implementation
   be hand-written?
7. Which diagnostic/inspection JSON schema is stable enough for editor use?
8. Does full `INSTANCE` support ship before the old scanners are removed, or may
   unsupported instance semantics remain a documented fail-closed profile limit?
9. Does scaffold proposal v2 carry the complete elaborated declaration manifest
   or only effective variables and their origins?
10. Which corpus may be published without exposing private application models?

These decisions affect language compatibility, reproducibility, and maintenance.
They do not change the central architecture: one bounded TLA+ frontend supplies
one elaborated source graph to every model-interface compiler command.
