"""Exercise the selected host's tracer, namespaces and local sockets."""
from common import *


def main():
    tracer = ROOT / '.golden-build/qualification-rc7-20261105/tracer/bin/strace'
    assert identity(tracer)['sha256'] == '10345119eae5a82fc79488417078fc19a145df378311f7e0b8da34e09fb9fadd'
    version = run('host-tracer-version', [tracer, '--version'])
    run('host-tracer-execution', [tracer, '-o', OUT / 'tracer-probe.log', '/usr/bin/true'])
    bubblewrap = run('host-bwrap-version', ['/usr/bin/bwrap', '--version'])
    probe = "import json,os,socket; s=socket.socket(); s.bind(('127.0.0.1',0)); print(json.dumps({'uid':os.getuid(),'netns':os.readlink('/proc/self/ns/net'),'localSocketBound':True})); s.close()"
    direct = json.loads(run('host-loopback', ['/usr/bin/python3', '-I', '-S', '-c', probe]))
    isolated = json.loads(run('host-namespace-isolation', ['/usr/bin/bwrap', '--die-with-parent',
        '--unshare-user', '--unshare-pid', '--unshare-ipc', '--unshare-uts', '--unshare-net',
        '--ro-bind', '/', '/', '--proc', '/proc', '--dev', '/dev', '--tmpfs', '/tmp',
        '--', '/usr/bin/python3', '-I', '-S', '-c', probe]))
    assert direct['netns'] != isolated['netns']
    write(PLAN / 'host-admission.json', {'schema': 'mirrors.rc12.host-capabilities/v1',
          'status': 'capability-probes-passed', 'osRelease': Path('/etc/os-release').read_text(),
          'tracer': identity(tracer), 'tracerVersion': version, 'bubblewrapVersion': bubblewrap,
          'direct': direct, 'isolated': isolated, 'installedAuditAcceptance': False})
    print('SELECTED HOST CAPABILITY PROBES GREEN', flush=True)


if __name__ == '__main__':
    main()
