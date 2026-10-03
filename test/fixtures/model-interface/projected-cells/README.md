# Public projected-cells fixture

This synthetic model and its two supplied ITF witnesses exercise M6 without
private application data or a model checker. The witnesses describe a mutable
two-cell implementation. Integer-function `cells` becomes a sequence of
`{entry: cell}` records in domain order, retaining the variable name. Each cell
contains an integer, a set of strings, and a string-keyed integer map.

`review.json` is explicit **test review data**: its literal approval and complete
action universes apply only to the pinned synthetic proposal. The companion
contract is written in the review. The harness does not extract a contract from
a proposal, infer approval, or silently update the proposal digest. Changes to
the inputs require an explicit fixture-review update.

From the Mirrors repository root, choose a fresh output directory:

```sh
python3 tools/model-interface-projected-corpus/check.py \
  --out /tmp/projected-cells-acceptance
```

The command runs `scaffold --reviewable`, `project-corpus`, `seal-scaffold`,
`resolve-sealed`, `bundle`, `check-sealed-bundle`, `check-corpus`, and member
preflight. All generated artifacts come from the compiler. The generated
loader-test copies in MirrorECMA live at `test/fixtures/projected-corpus`;
their README describes refresh paths.

The same suite runs locally and through a real Gate Node worker. Its native
adapter owns its mutable state and uses actual `Set` and `Map` values. Both
successful runs must match four updates and two Update/Update pairs, with
confirmed cleanup. A well-typed faulty observer must produce an actual
expected-zero/actual-one model mismatch. Cleanup failure must prevent a pass,
and artifact admission failure must precede implementation acquisition.

The harness packs local SDKs, relocates the installation, hides the three
source checkouts, and isolates the execution network. An executable sentinel
detects any attempted local model-check invocation. Results and Gate receipts
remain beneath the chosen output directory. This establishes the exercised
source and packed-package integration tier; it is not release qualification.
