#!/usr/bin/env bash
set -euo pipefail
audit_root=/mnt/d/Desktop/Workspaces/Mirrors-client-conformance-20261015
trap 'audit_result=$?; printf "%s\n" "$audit_result" > "$audit_root/lean-phase.exit"' EXIT
export PATH=/home/jlc/.elan/bin:/usr/bin:/bin
export LEAN_NUM_THREADS=2
cd "$audit_root/lean-probes"
lake -Kjobs=2 build closure-probe tls-identity-probe > "$audit_root/logs/lean-build.log" 2>&1
.lake/build/bin/closure-probe fixtures > "$audit_root/closure.jsonl"
python3 run-tls-probe.py --client-root ../MirrorLean --output "$audit_root/tls-results" > "$audit_root/logs/tls-probe.stdout.log" 2> "$audit_root/logs/tls-probe.stderr.log"
echo LEAN_BOUNDED_PROBES_COMPLETED
