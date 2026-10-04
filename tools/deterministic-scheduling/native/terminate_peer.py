#!/usr/bin/env python3
"""Negative control: terminate only this proxy's verified native child."""
import base64
import json
from pathlib import Path
import subprocess
import sys

worker, marker = Path(sys.argv[1]), Path(sys.argv[2])
child = subprocess.Popen([str(worker)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1, cwd=worker.parent)
identity = None
try:
    for index, line in enumerate(sys.stdin):
        if index == 2:
            if not identity: raise RuntimeError('native identity not observed')
            # Windows PID reuse is guarded by both image path and creation time.
            image = identity['imagePath'].replace("'", "''")
            script = "$ErrorActionPreference='Stop';$p=Get-Process -Id " + str(identity['processId']) + ";"
            script += "if($p.Path -ne '" + image + "' -or $p.StartTime.ToFileTimeUtc().ToString() -ne '" + identity['createdFileTime'] + "'){throw 'Owned native identity changed'};"
            script += "$p.Kill();$p.WaitForExit();"
            command = ['/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe', '-NoProfile', '-NonInteractive',
                       '-EncodedCommand', base64.b64encode(script.encode('utf-16-le')).decode()]
            subprocess.run(command, check=True, capture_output=True, timeout=20, cwd=worker.parent)
            exit_code = child.wait(timeout=10)
            marker.write_text(json.dumps({'nativeIdentity': identity, 'terminationConfirmed': True, 'carrierExitCode': exit_code}) + '\n')
            raise SystemExit(41)
        child.stdin.write(line); child.stdin.flush()
        reply_line = child.stdout.readline()
        if not reply_line: raise RuntimeError('native worker ended before failure injection')
        reply = json.loads(reply_line)
        if identity is None: identity = reply['nativeIdentity']
        if reply['nativeIdentity'] != identity: raise RuntimeError('native identity changed')
        print(reply_line.rstrip('\n'), flush=True)
finally:
    if child.poll() is None:
        try:
            child.stdin.write('{"op":"Quit"}\n'); child.stdin.flush(); child.stdin.close()
            child.wait(timeout=20)
        except (BrokenPipeError, OSError):
            child.wait(timeout=20)
