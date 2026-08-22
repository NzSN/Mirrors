# test/ — fixtures and differential tests

- Golden JSON wire corpus frozen from the Haskell test suite (all 39
  message constructors × representative payloads) — migration Phase 0.
  See fixtures/README.md for provenance (ModelMirrors@3496251) and the
  Haskell-side replay gate.
- Differential tests: Lean core vs the Haskell mirror pinned by commit
  (design §7, §8). lake test runs:
  1. fixtures_replay (tools/ReplayFixtures.lean) — every corpus line
     decodes to a typed message and re-encodes byte-identically in the
     Lean codec (Phase 2 / §6.6 wire equivalence).
  2. diff_cross (tools/DiffCross.lean) — replays
     fixtures/diff_cases.jsonl (500 QuickCheck-generated state-valuation
     pairs, deterministic seed, with the Haskell Engine.Core.diffState
     verdict recorded per case) through Core.diffState and compares
     verdict + hint list as an *ordered* JSON list (Phase 1 exit
     criterion, Goal 2 byte-for-byte wire parity). The Lean engine
     reproduces the Haskell sorted-key hint interleave exactly
     (Core.Diff.sortHintsByKey). Verified green on the checked-in
     500-case corpus and on a fresh 5000-case sweep.

Regenerate the differential corpus (Haskell side, read-only artifact;
compile flags are recorded in tools/fixtures/run.sh):

    ./.golden-build/gen-diff test/fixtures/diff_cases.jsonl 500

Larger sweeps (not checked in): generate a corpus anywhere and point
the harness at it via the environment, e.g.

    ./.golden-build/gen-diff .golden-build/diff_cases_5000.jsonl 5000
    DIFF_CROSS_CORPUS=.golden-build/diff_cases_5000.jsonl \
      .lake/build/bin/diff_cross

Hint order is compared exactly (ordered lists, no sorting): the sorted
multiset comparison that Phase 1 originally used was upgraded once
Core.Diff reproduced the Haskell hint ordering.
