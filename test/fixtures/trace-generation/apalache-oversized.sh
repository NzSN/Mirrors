#!/bin/sh
set -eu

run_dir=""
for arg in "$@"; do
  case "$arg" in
    --run-dir=*) run_dir=${arg#--run-dir=} ;;
  esac
done

if [ -z "$run_dir" ]; then
  printf '%s\n' 'fake apalache requires --run-dir' >&2
  exit 255
fi

if [ -n "${FAKE_APALACHE_COUNT_FILE:-}" ]; then
  printf '%s\n' invocation >> "$FAKE_APALACHE_COUNT_FILE"
fi

output_dir="$run_dir/fake-output"
mkdir -p "$output_dir"
{
  printf '%s' '{"#meta":{"format":"ITF"},"vars":["payload"],"states":[{"#meta":{"index":0},"payload":"'
  head -c 70000 /dev/zero | tr '\000' x
  printf '%s\n' '"}]}'
} > "$output_dir/oversized.itf.json"

printf 'Output directory: %s\n' "$output_dir"
exit 12
