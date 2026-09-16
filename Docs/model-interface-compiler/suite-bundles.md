# Trusted suite bundles

`bundle` publishes the existing `mirrorecma-async-v1` target together with an
inert `SuiteModel` companion. The target profile and semantic digest retain their
existing meaning. This is a publication mode, not a fourth compiler target.

```sh
model_interface_gen bundle --lock Counter.mirror-interface.lock.json \
  --target mirrorecma-async-v1 --out generated
model_interface_gen check-bundle --spec specs/Counter.tla \
  --contract Counter.mirror-interface.json --evidence counter.itf.json \
  --param-var parameters --lock Counter.mirror-interface.lock.json \
  --target mirrorecma-async-v1 --out generated
```

Both commands accept `--diagnostics json`. Generation requires a sealed,
verified semantic lock. Freshness checking re-resolves the reviewed inputs and
compares exact bytes without writing or repairing files. It does not generate
traces or seal proposals.

The owned payload contains:

- The original `<Model>Mirror.generated.ts` and `.model-interface-generated.json`,
  byte-for-byte identical to ordinary async generation.
- `<Model>.suite.ts`, exporting `<Model>Model`, `<Model>NativeAdapter`, and
  `<Model>NativeObservation` through the public `mirrorecma` suite contract.
- `descriptor.json`, the canonical private semantic descriptor.
- `public-manifest.json`, the sanitized existing `mirrorgate.port/v1` manifest.
- `bundle-metadata.json`, tagged `mirrors.suite-bundle-metadata/v1`, recording
  compiler version, provenance digest, semantic digest, target profile,
  computer contract, root model hash, the complete module/source hash closure, and
  independently versioned native representation. Source hashes omit original paths.

The separate `.suite-bundle-generated.json` uses `mirrors.suite-bundle/v1`.
Its `files` list includes itself; `payloadSha256` lists one `{path, sha256}`
entry for every other owned file. Each digest covers the complete UTF-8 file
bytes, including its final newline. `metadataSha256` independently identifies
the exact metadata payload. The manifest never hashes itself. Existing compiler
ownership parsing remains closed and unchanged.

Publication uses the existing output lock, containment and symlink checks,
same-directory staged replacement, rollback, stale-owned-file deletion and
manifest-last commit. Unowned collisions fail. Ordinary generation cannot
modify a bundle, and a bundle does not adopt an ordinary generated directory.
Use a separate output directory when changing publication modes.

The companion's `bindPublicPort` accepts the existing compiled collection
representations. `bindLocal` accepts stable-ID `actions` and an `observe`
function, converting recursively to native `Set` and string-key `Map` values.
Integers remain arbitrary-precision `bigint`; records are closed, tuples have
exact arity, and variants require declared tags. Set duplicates are compared
structurally, including nested sets and maps. Record names such as `__proto__`
are ordinary own data keys. Unsupported maps or opaque types fail emission.
All operation input fields are validated before the handler runs; all
observations are validated before returning the compiled state. Generated
imports neither construct an application adapter nor start a process.

The emitted provenance also appears on the model handle. Suite preflight compares
the root model and full source closure before constructing an implementation.
Prepared JavaScript evaluator modules remain trusted executable inputs; an
optional module hash pin identifies bytes but does not prove TypeScript compilation.

The suite factory transfers an explicit disposer to MirrorECMA; merely defining
an adapter `dispose` method does not transfer ownership. Local bridges do not
import Gate. Gate providers bind compiled values directly, avoiding a second
native conversion.

Validation lives in `tools/ModelInterfaceSpec.lean` and
`tools/check-suite-bundle.py`, both included in `lake test`. The interop gate also
runs `tools/check-suite-runtime.py`: it generates a fresh Counter bundle,
transforms the two TypeScript modules with the pinned Node runtime, and executes
`tools/check-suite-native.mjs` and the shared `tools/suite-native-vectors.mjs`.
It requires no MirrorECMA checkout or npm packages. Gate copies and hash-pins the
same representation vectors. Installed consumer gates separately typecheck the
generated public API contract; runtime transformation is not a typecheck.
