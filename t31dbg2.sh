#!/bin/bash
cd /d/ModelMirrors/lean4
CDB="/c/Program Files/WindowsApps/Microsoft.WinDbg_1.2606.22001.0_x64__8wekyb3d8bbwe/amd64/cdb.exe"
"$CDB" -g -G -lines -y "D:\\ModelMirrors\\lean4\\.lake\\build\\bin" \
  -c "g; ~* kb 20; q" \
  D:\\ModelMirrors\\lean4\\.lake\\build\\bin\\mirror.exe --serve 19141 > cdb2.log 2>&1 &
CPID=$!
sleep 6
timeout 5 bash -c 'exec 3<>/dev/tcp/127.0.0.1/19141 && exec 3<&-' >/dev/null 2>&1
sleep 5
grep -a -A12 "second chance" cdb2.log | head -16
kill $CPID 2>/dev/null
taskkill //F //IM mirror.exe >/dev/null 2>&1
taskkill //F //IM cdb.exe >/dev/null 2>&1
exit 0
