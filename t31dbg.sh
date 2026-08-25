#!/bin/bash
cd /d/ModelMirrors/lean4
for i in 1 2 3 4 5 6; do
  ./.lake/build/bin/mirror.exe --serve 1913$i > dbg7-$i.log 2>&1 &
  SPID=$!
  sleep 3
  timeout 5 bash -c "exec 3<>/dev/tcp/127.0.0.1/1913$i && exec 3<&-" > /dev/null 2>&1
  sleep 1
  kill -0 $SPID 2>/dev/null && echo run$i ALIVE || echo run$i DEAD
  kill -9 $SPID 2>/dev/null
  taskkill //F //IM mirror.exe >/dev/null 2>&1
  sleep 1
done
exit 0
