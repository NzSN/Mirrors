# DPM timeline regression inputs

Selected actual C++/Node/Rust receipts copied byte-for-byte from the accepted
DPM records. These are diagnostic inputs, not new replay/qualification results.
Regenerate with `python3 tools/deterministic-scheduling/prepare_timeline_fixtures.py`
into an absent output directory; do not edit frozen receipt bytes. The manifest
binds every original source path and copied digest. Malformed controls are
constructed in tests without changing these inputs.
