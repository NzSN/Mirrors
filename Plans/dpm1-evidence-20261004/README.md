# DPM-0 / DPM-1 local acceptance — 2026-10-04

`acceptance.json` records the final source and binary hashes, 202 local unit tests,
615 focused assertions and sanitizer results. `replay/` and `asan-replay/`
retain the actual serialized schedules, fresh-process receipts and verified
observations. Diagnostic sanitizer startup failures receive no acceptance credit.
The successful ThreadSanitizer run used per-process ASLR disabling only.

This record qualifies the declared portable fixture scope. Generated-binding
comparison, native WriteSentry integration, exploration completeness and
capability publication remain DPM-2 through DPM-5. The executable files remain
local build artifacts; this is not a self-contained release archive.
