#!/usr/bin/env bash
set -eu
export PATH=/home/jlc/.elan/bin:/home/jlc/.cargo/bin:/usr/local/bin:/usr/bin:/bin
cat /etc/os-release
ls /home/jlc/.elan/toolchains
ls /home/jlc/.rustup/toolchains
for tool in lake lean elan rustc cargo python3 c++ cmake pkg-config bwrap; do
  command -v "$tool" || true
done
python3 --version
c++ --version | head -1
cmake --version | head -1
pkg-config --modversion openssl
ls -d /home/jlc/Repos/Mirrors/.lake/build /home/jlc/Repos/Mirrors/.lake/packages /home/jlc/Repos/MirrorCPP /home/jlc/Repos/MirrorECMA /home/jlc/Repos/MirrorRust /usr/local/bin/node 2>/dev/null || true
cat /home/jlc/Repos/Mirrors/lean-toolchain
du -sh /home/jlc/Repos/Mirrors/.lake/build /home/jlc/Repos/Mirrors/.lake/packages 2>/dev/null || true
bwrap --unshare-net --ro-bind / / --proc /proc --dev /dev /usr/bin/true
echo 'BWRAP_PROBE_PASSED'
