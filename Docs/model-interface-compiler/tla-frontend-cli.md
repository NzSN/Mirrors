# TLA+ frontend inspection CLI (`tla_frontend`)

Status: **implemented and accepted on 2026-09-12 as task package TF8 of the
[general TLA+ frontend tasks](tla-frontend-tasks.md)**. Design authority:
[inspection tool section of the frontend design](tla-frontend-design.md).

`tla_frontend` is the development-only view of the same captured analysis the
model-interface compiler consumes. It exists for debugging, editor integration,
corpus generation, and differential tests; `model_interface_gen` never requires
it as a prerequisite, and the operational `mirror` executable gains no
development command.

## Usage

```text
tla_frontend parse --spec FILE [--format json]
tla_frontend resolve --spec FILE [--format json]
tla_frontend inspect --spec FILE [--variables] [--dependencies]
  [--operators] [--levels] [--format json]
tla_frontend help
```

- `parse` captures the root file once and reports syntax facts only: the
  declared module name, declaration and dependency-declaration counts, and
  parse diagnostics.
- `resolve` performs full graph resolution and elaboration and reports the
  effective variables, dependency edges, operators, classified levels, and the
  captured source manifest.
- `inspect` projects the requested fact sections from the same analysis.
  Without a section flag it prints every section.

`--spec` must name a bare `*.tla` file; its directory is the borrowed root for
sibling dependencies. Exit codes follow `model_interface_gen`: `0` success,
`1` analysis failure with reported diagnostics, `2` malformed arguments.

Examples:

```bash
.lake/build/bin/tla_frontend parse --spec Spec.tla
.lake/build/bin/tla_frontend inspect --spec ../dump-ledger/specs/DumpLedgerTransfer.tla --variables
.lake/build/bin/tla_frontend resolve --spec Spec.tla --format json
```

```text
module: AcceptPrecedence
path: AcceptPrecedence.tla
declarations: 11
dependencies: 1
diagnostics: 0
```

## JSON documents

Every document is compact JSON with the closed schema
`mirrors.tla-frontend-inspection/v1`:

| Key | Meaning |
| --- | --- |
| `schema` | Closed schema identity, currently `mirrors.tla-frontend-inspection/v1`. |
| `command` | `parse`, `resolve`, or `inspect`. |
| `ok` | `true` only for a complete result with no error diagnostic. |
| `source.path` | Captured logical path; a bare `.tla` file name. |
| `module` | Declared root module name, or `null` when no module was produced. |
| `diagnostics` | Bounded structured diagnostics: code, severity, stage, message, logical location, related locations, and arguments. |
| `declarations`, `dependencies` | `parse` only: counts from the parsed root module. |
| `variables` | `resolve` and `inspect`: effective root variables with declared name, declaring module, import path, `LOCAL` flag, and declaration location. |
| `dependencies` | `resolve` and `inspect`: graph edges with owner, dependency, kind, resolution, `LOCAL` flag, declaration order, and substitution formals. |
| `operators` | `resolve` and `inspect`: resolved operators with arity, fixity, classified level, and declaration origin. |
| `levels` | `resolve` and `inspect`: every effective constant, variable, operator, and assumption with its classified level. |
| `sources` | `resolve` only: the sorted captured source manifest with logical path and normalized SHA-256 digest. |

A failed analysis keeps the same key set with `ok: false`, `module: null`, and
empty fact sections, so a consumer never has to guess a second shape.

```json
{"command":"parse","declarations":11,"dependencies":1,"diagnostics":[],"module":"AcceptPrecedence","ok":true,"schema":"mirrors.tla-frontend-inspection/v1","source":{"path":"AcceptPrecedence.tla"}}
```

## Guarantees

- **One analysis per command.** `resolve` and `inspect` consume one
  `Shell.Tla.Frontend` result; the scaffold, projection, `resolve`, and `check`
  compiler paths use the same frontend module.
- **Logical identities only.** Default output never contains a physical path:
  `--spec` is admitted only when it has a bare `.tla` file name, and module,
  import, and diagnostic locations are captured logical paths.
- **Fail closed.** Any error diagnostic yields exit code `1`, `ok: false`, and
  no fact entries; no partial graph is reported as a result.
- **Deterministic.** Keys are emitted in canonical order and repeated runs of
  the same command are byte-identical.
- **Closed schema.** The key set of every document and nested object is fixed
  by `Codec/TlaFrontendJson.lean`; caller text never reaches a key position.

## Validation

The gate `tools/TlaFrontendCliSpec.lean` builds and runs the executable and
checks exact help and malformed-argument behavior, closed key sets, human/JSON
diagnostic equivalence, physical-path absence, deterministic output, and the
public fixture below. It runs from `lake test` as `tla_frontend_cli_spec`:

```bash
lake build
lake env lean --run tools/TlaFrontendCliSpec.lean
.lake/build/bin/tla_frontend_cli_spec
```

`test/fixtures/tla-frontend/cli/inspect-generic-transfer-variables.json` pins
the exact `inspect --variables --format json` output for the public
`accepted/generic-transfer/GenericTransfer.tla` corpus fixture, whose twelve
inherited plus seven local variables are the motivating acceptance case. See
[the fixture note](../../test/fixtures/tla-frontend/cli/README.md) for the
regeneration command.
