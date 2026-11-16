"""Run an owned loopback-only SSH tunnel with a PID/start-time shutdown guard."""
from common import *


def start_time(pid):
    return Path('/proc/' + str(pid) + '/stat').read_text().rsplit(')', 1)[1].split()[19]


def main():
    argv = SSH[:-1] + ['-o', 'ExitOnForwardFailure=yes', '-N', '-T', '-L',
                       '127.0.0.1:19109:127.0.0.1:19099', SSH[-1]]
    stdout, stderr = OUT / 'tunnel.stdout', OUT / 'tunnel.stderr'
    with stdout.open('xb') as out, stderr.open('xb') as err:
        process = subprocess.Popen(argv, stdout=out, stderr=err, stdin=subprocess.DEVNULL)
        write(OUT / 'tunnel-state.json', {'pid': process.pid, 'startTime': start_time(process.pid),
              'argv': argv, 'createdAt': datetime.now(timezone.utc).isoformat()})
        code = process.wait(timeout=7200)
    write(OUT / 'tunnel-completion.json', {'exitCode': code, 'stdout': identity(stdout), 'stderr': identity(stderr)})
    print('OWNED TUNNEL EXIT ' + str(code), flush=True)


if __name__ == '__main__':
    main()
