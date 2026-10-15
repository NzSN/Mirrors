#!/usr/bin/env bash
set -euo pipefail
fix_root=/home/jlc/Tools/mirrors-client-fixes-20261015
fix_build=/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015
out="$fix_build/cpp-gate"
if [[ ${1-} != inside ]]; then
  test "$(id -u)" = 0
  exec /usr/bin/unshare --mount --propagation private -- /bin/bash "$0" inside "$@"
fi
shift
test "$(id -u)" = 0
test "$#" -eq 1
case "$1" in "$fix_build"/cpp-gate/workflow/*.sh) ;; *) exit 2 ;; esac
sha256sum -c "$out/manifests/system-bwrap-before.sha256"
mount --bind "$fix_root/tools/bwrap09/bin/bwrap" /usr/bin/bwrap
test "$(/usr/bin/bwrap --version)" = 'bubblewrap 0.9.0'
findmnt -T /usr/bin/bwrap
readlink /proc/self/ns/mnt
exec /usr/bin/setpriv --reuid=1000 --regid=1000 --init-groups -- \
  /usr/bin/env PATH="$fix_root/tools/cpp-bin:$fix_root/tools/bin:/usr/bin:/bin" \
  TMPDIR=/tmp/fix-tests CC=/usr/bin/gcc-12 CXX=/usr/bin/g++-12 \
  /bin/bash "$1"
