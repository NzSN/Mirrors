"""Stop only identity-matched owned oracle/tunnel processes and retain cleanup."""
import signal
import socket
import sys
import time
from common import *


def main():
    suffix = sys.argv[1] if len(sys.argv) > 1 else ''
    value = json.loads(run('owned-oracle-shutdown' + suffix, SSH + ['powershell', '-NoProfile', '-NonInteractive',
        '-ExecutionPolicy', 'Bypass', '-File', STAGE.replace('\\', '/') + '/stop-owned-oracle-admitted.ps1'], timeout=90))
    write(OUT / 'oracle-cleanup-admitted.json', value)
    state = json.loads((OUT / 'tunnel-state.json').read_text())
    proc = Path('/proc') / str(state['pid'])
    if proc.exists():
        born = (proc / 'stat').read_text().rsplit(')', 1)[1].split()[19]
        argv = (proc / 'cmdline').read_bytes().rstrip(b'\0').split(b'\0')
        assert born == state['startTime'] and [part.decode() for part in argv] == state['argv']
        os.kill(state['pid'], signal.SIGTERM)
    for _ in range(100):
        if not proc.exists():
            break
        time.sleep(0.1)
    else:
        raise ValueError('owned tunnel did not stop')
    with socket.socket() as probe:
        probe.bind(('127.0.0.1', 19109))
    write(PLAN / 'fixture-cleanup.json', {'status': 'owned-oracle-and-tunnel-stopped',
          'oracle': identity(OUT / 'oracle-cleanup-admitted.json'), 'localTunnelPortFree': True,
          'productionBinarySha256': value['productionBinarySha256'], 'productionModified': False})
    print('OWNED ORACLE AND TUNNEL CLEANUP VERIFIED', flush=True)


if __name__ == '__main__':
    main()
