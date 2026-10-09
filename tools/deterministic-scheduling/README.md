# Deterministic scheduling acceptance tools

These tools exercise C++ checkpoint threads, Node workers and Rust threads,
including generated replay, finite exploration, installed consumers and the bounded
native pilot. Kit generation and read-only timelines are a newer source-accepted
slice. Ordinary binding bytes stay stable, and expected model state never initializes
implementation state. Run from the Mirrors repository root.

## Integration kit and read-only timeline

`model_interface_gen generate-dpm/check-dpm` prepares/checks reviewed mapping
helpers alongside ordinary bindings. `timeline.py --receipt FILE --format text|json`
reads actual comparison/worker receipts without changing them or starting a run.
[Kit/timeline contract](../../Docs/dpm-usability-design.md) defines supported
profiles, input trust, actor/checkpoint mapping and honest unknown attribution.

`python3 -m unittest discover -s tools/deterministic-scheduling/tests` runs focused
compiler publication and timeline integrity controls. Static real-receipt inputs
are copied byte-for-byte by `prepare_timeline_fixtures.py`; they are diagnostic
regression data, not fresh model qualification. Never edit retained receipt bytes.

## Portable installed gate

```sh
python3 tools/deterministic-scheduling/check_installed.py \
  --sdk-build /path/to/MirrorCPP-build \
  --dependency-prefix /path/to/admitted-header-dependencies \
  --native-generated /path/to/fresh-native-generated-binding \
  --out /tmp/dpm-installed-new
```

The native generated binding is optional. The dependency prefix supplies Boost
and nlohmann headers plus nlohmann's CMake package. The SDK itself is freshly
installed from `--sdk-build`. The gate builds a new CMake consumer with checkouts
hidden and networking isolated, then runs 15 generated replay cases, 11 finite
exploration cases and artifact/profile refusal controls. Bubblewrap namespace
creation must be permitted. System compiler, OpenSSL and runtime dependencies
remain admitted. A successful gate writes `work/acceptance.json`.

`check.py --trace ... --initial 0|5` can repeat the 15 replay controls against a
freshly captured counter trace. `check_exploration.py` independently verifies the
20-interleaving/two-input denominator and semantic state/transition accounting.
The default checked-in traces are authored test evidence, not fresh model checks.

## Native pilot

The reviewed scope is in
[the DPM-3 pilot](../../Plans/deterministic-production-mbt-dpm3-pilot.md).
`native/freeze.py` freezes selected inputs without changing WriteSentry.
`native/build.ps1` admits only a new output directory beneath the owned
`MirrorsRemote` root, builds the normal worker or one of two isolated production
mutants, and records source/binary hashes. All trap-path synchronization remains
WriteSentry's preallocated atomic handshake.

`native/prepare.py` runs the four declared native schedules and writes a mapping,
model wrapper and diagnostic transcript per case. Its observed states must never
be used as an oracle. Capture an independent trace for each wrapper through the
Mirrors CLI against the approved service, with:

- `--cinit RunConstInit --init MBTInit --next MBTNext`
- `--inv MBTTraceIncomplete --bound <number of mapped phases>`
- `--param-var parameters --num-traces 1`
- the approved direct pinned mTLS connection and shared-trace roots.

Also run `mirror validate` with `--inv MBTSafety` at the same schedule bound.
Resolve/generate/check a campaign-local `mirrorcpp-v2` binding from the raw fresh
ITF evidence and the frozen contract; preserve WriteSentry's existing lock.
Raw Apalache ITF and preprocessed evidence may have different parameter metadata,
which intentionally affects negotiation identity.

```sh
python3 tools/deterministic-scheduling/native/check_installed.py \
  --installed /tmp/dpm-installed-new \
  --prepared /path/to/four-prepared-native-cases \
  --oracles /path/to/four-fresh-captures \
  --worker-root /mnt/c/Users/ayden/Desktop/Workspace/MirrorsRemote/dpm-20261004 \
  --out /tmp/dpm-native-installed-new
```

The current acceptance layout names the worker builds `normal-v3`,
`duplicate-sink-call` and `skip-hit-release`; these names identify this campaign,
not SDK versions. The runtime gate again hides checkouts and isolates networking,
while preserving WSL's local Windows process carrier. Native workers launch from
their owned Windows build directory. It requires eight successful fresh-process
replays, two real production comparison failures, cancellation, image refusal,
verified owned-child termination and actual phase divergence. Three incompatible
mappings must reject before acquisition. The phase-divergence control deliberately
modifies a negative trace/mapping; that modified trace earns no oracle credit.

The static installed capability declaration is separate from the retained
qualification observation. The pilot does not qualify arbitrary thread control,
all WriteSentry behavior, a Windows Gate backend or a new M5 release candidate.
