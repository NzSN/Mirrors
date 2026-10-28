# DV1 reference qualification

This record qualifies the local artifacts for frontend-only differential work.
It does not claim corpus conformance or independent parser implementations.

## Artifacts

`toolchain.lock.json` records the release URLs, archive sizes and SHA-256
identities, Apalache build revision and extracted JAR/launcher identities, the
derived standard-library digests, and the required JDK version/build.
Acquisition is explicit. Local installation writes only under the ignored
`.golden-build/tla-differential/toolchain/` directory; an explicitly selected
artifact store is written only at that operator-chosen path. Pinned release
URLs are used only with `--download`:

```sh
python3 tools/tla-differential/acquire.py --download
```

An operator may instead select an explicit content-addressed SHA-256 store,
populating it during download or restoring from it with no network access:

```sh
python3 tools/tla-differential/acquire.py --download --artifact-store /approved/store
python3 tools/tla-differential/acquire.py --offline --artifact-store /approved/store
```

Store objects live at `<store>/sha256/<lower-case-sha256>`; the tool never
discovers a store from an environment variable, repository sibling, package
cache, or `PATH`. Normal verification
(`python3 tools/tla-differential/acquire.py`) uses only the installed
toolchain, performs no network access, and does not discover ambient SANY or
Apalache installations. See [`README.md`](README.md) for the no-overwrite and
fail-closed acquisition contract.

The Apalache archive hash matches the repository pin in
`tools/ci/versions.env`. The standalone jar is acquired from the v1.8.0 release
asset URL, which has served different builds. The October 28 re-pin identifies
TLA+ Tools `2.0 2026-10-28`, revision `56d37a9`, with SANY 2.2; the lock records
the exact artifact hash, size, computed SHA-1, native help banner and manifest
metadata. The legacy `tla2tools-1.8.0.jar` local filename is a locator, not a
version assertion. All 20 standard-module entries retain the prior aggregate
digest, so frontend profile 6 and catalog v3 stay unchanged. See
[the re-pin evidence](../../Plans/sany-repin-evidence-20261028/README.md).
The catalog's historical `TLA+ Tools 1.8.0` review label continues to name that
byte-identical reviewed module set; the executable identity comes from the lock.
Java is operator-supplied OpenJDK 25.0.4+7 and is admitted by the exact
version/build in the lock; it is not downloaded or installed by this tool.

The SANY jar contains `tla2sany/StandardModules/*.tla`; the Apalache jar also
contains that prefix plus Apalache extension/internal modules. Standard-module
entry hashes are available from the qualification command's jar inventory.
The two Apalache/SANY parser paths share `tla2sany` code by design; the separately
pinned standalone SANY jar is a distinct artifact, while Apalache is the compatibility
oracle with correlated parser lineage.

## Frontend commands

Standalone SANY:

```text
java -cp downloads/tla2tools-1.8.0.jar tla2sany.SANY -help
java -cp downloads/tla2tools-1.8.0.jar tla2sany.SANY [-error-codes] MODULE.tla
```

`-s` disables semantic analysis and level checking; default execution performs
parse, semantic analysis, and level checking. `-error-codes` requests exit 2
for parse errors and exit 4 for semantic/level errors. The help text is the
native stage/exit contract; diagnostics must still be retained and checked.

Apalache:

```text
apalache-mc parse MODULE.tla
apalache-mc parse --output=parsed.json MODULE.tla
```

The `parse` command runs `PASS #0: SanyParser`, does not require Init/Next,
invariants, type annotations, or model checking, and exits 0 only after the
`Parsed successfully` and `EXITCODE: OK` records. `--output=...` is the
reliable option spelling; the separated `--output file` form was rejected by
the 0.61.0 CLI. JSON is Apalache IR 1.0 and carries module/declaration names,
source locations, formal parameters, and expression bodies. It does not
constitute a qualified source for all required SANY structural facts.

## Bridge API

The standalone jar exposes the following public APIs for a test-only bridge:

* `tla2sany.drivers.SANY.parse(SpecObj, String, SanyOutput, SanySettings)`
  returns `SanyExitCode`; `frontEndParse` and `frontEndSemanticAnalysis` are
  separately callable.
* `SpecObj.getRootModule()`, `getModuleNames()`, `getModules()`,
  `getParseErrors()`, `getSemanticErrors()`, and `getErrorLevel()` expose the
  loaded result and error channels.
* `ModuleNode.getVariableDecls()`, `getConstantDecls()`, `getOpDefs()`,
  `getInstances()`, `getInnerModules()`, `getContext()`,
  `getExtendedModuleSet()`, `isLocal()`, and `getLevel()` expose module facts.
* `OpDefOrDeclNode.getName()`, `getNumberOfArgs()`,
  `getOriginallyDefinedInModuleNode()` and `getSymbolTable()` expose identity,
  arity, and declaration origin. `OpDefNode.getSource()`, `getParams()`,
  `getBody()`, `isLocal()`, `getArity()`, `getLevel()`, and
  `getArgMaxLevels()` expose definition/source/level facts.
* `InstanceNode.getName()`, `getModule()`, `getLocal()`, `getStepName()`,
  `getChildren()`, and level accessors expose instance identity and target.
  The bridge reads the package-private `Subst[] substs` field with pinned
  reflection, then uses public `getOp()`, `getExpr()`, and `isImplicit()`.
  Name/integer/boolean/string actuals are calibrated; richer expression
  identities are not certified. The bridge uses `SANY.frontEndMain`, and
  checks both parse and semantic error channels before publishing any graph.
  `ExternalModuleTable.getModuleNodes()` supplies the observed loaded closure;
  `getExtendedModuleSet(false)` supplies direct edges. `getSource()` follows
  instance operator origins with an explicit 64-hop bound.

SANY has global state and the Apalache launcher explicitly serializes SANY
calls. A bridge must use one process per fixture or an equivalent lock.

## Capability status

| Fact | Status | Extraction/evidence |
|---|---|---|
| Outcome and native phase | calibrated | SANY parse/semantic error channels; Apalache SanyParser markers, exit and valid IR |
| Variables, origins, arity | calibrated projection | root effective declarations, original source chain, local source identities |
| EXTENDS/dependency identities | calibrated projection | actual external module table and direct extendee/instance edges |
| LOCAL visibility and operator levels | calibrated projection | root effective operators, locality flags, level 0/1/2/3 |
| INSTANCE identity | calibrated sites | named/unnamed/chained/LOCAL fixture probes; source owner, name, line |
| Substitution actuals | calibrated atomic values/spellings only | reflected Subst records; implicit same-name rule; full resolved expression identity remains uncertified |
| Apalache structural rows | unqualified | raw IR retained; structural normalizer is deliberately absent |
| Native-to-Mirrors stage mapping | unsupported | phases retained; differing internal stage organization is not guessed |
| Token/CST/expression-tree equivalence | unsupported | initial tier does not externally certify these surfaces |

No full corpus run was performed during qualification.

## Calibrated scope

The opt-in `DV_LIVE_REFERENCES=1` suite calibrates pinned SANY on selected
accepted/rejected fixtures and temporary named, chained, and LOCAL INSTANCE
bundles. It is not a 57-fixture conformance run. The bridge records only atomic
substitution actuals (name, integer, boolean, string); other expressions remain
explicitly unavailable. Source closures come from actually loaded semantic
modules; origin traversal is bounded by the bridge's 64-hop guard. SANY and
Apalache share tla2sany lineage, so their agreement is correlated evidence.


## Execution isolation

The actual adapters disable HotSpot performance-data files (`-XX:-UsePerfData`)
and use a private `java.io.tmpdir` inside the bounded invocation artifact tree.
This avoids JVM telemetry filename collisions between process namespaces and
keeps extracted standard-library temporaries inside the invocation budget.
Startup warnings are never stripped to manufacture valid JSON; malformed SANY
stdout remains `invalid_output`. The earlier concurrent D/E probes exposed this
environment issue and are not acceptance checkpoints.
