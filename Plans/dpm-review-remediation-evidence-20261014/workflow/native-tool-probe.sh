#!/usr/bin/env bash
set -eu
ls /usr/bin/g++* /usr/bin/clang* /usr/local/bin/cmake /usr/local/bin/node /usr/lib/llvm-*/bin/clang++ 2>/dev/null || true
ls /home/jlc/Tools /home/jlc/.local/bin /opt 2>/dev/null || true
apt-cache policy g++-12 g++-13 cmake | head -30
python3 -m pip --version || true
ls /home/jlc/Repos/Mirrors/.lake/packages/batteries/.git/HEAD
git -C /home/jlc/Repos/Mirrors/.lake/packages/batteries rev-parse HEAD
