#!/usr/bin/env bash
set -euo pipefail
fix_root=/home/jlc/Tools/mirrors-client-fixes-20261015
fix_build=/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015
trap 'result=$?; printf "%s\n" "$result" > "$fix_build/ecma-ci.exit"' EXIT
export PATH="$fix_root/tools/bin:/home/jlc/.elan/toolchains/leanprover--lean4---v4.33.0/bin:/usr/bin:/bin"
export ELAN_TOOLCHAIN=leanprover/lean4:v4.33.0 LEAN_NUM_THREADS=2 TMPDIR=/tmp/fix-tests LC_ALL=C.UTF-8
export XDG_CACHE_HOME="$fix_root/tools/xdg-cache" PYTHONDONTWRITEBYTECODE=1
export MIRRORS_ROOT="$fix_root/source/Mirrors"
export MIRRORS_REF="$(git -C "$MIRRORS_ROOT" rev-parse HEAD)"
unset APALACHE_MC MIRROR_BIN DV_LIVE_REFERENCES
cd "$fix_root/source/MirrorECMA"
pnpm run ci > "$fix_build/logs/ecma-ci.log" 2>&1
echo ECMA_FULL_PINNED_NONLIVE_CI_PASSED
