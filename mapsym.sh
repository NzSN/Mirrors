#!/bin/bash
for a in c79f7f c7ad51 c96b0c c964f1 c7a406; do
  grep -a "^[0-9a-f]\{8\} " /d/mm.map | awk -v target=$((0x$a)) '
    { v = strtonum("0x" $1); if (v <= target && v > best) { best = v; name = $NF } }
    END { printf "0x%s -> %s (+0x%x)\n", "'"$a"'", name, target - best }'
done
