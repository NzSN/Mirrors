#!/usr/bin/env python3
"""Create a task CA and local host client identities; never export key bytes."""
import os
from common import OUT, PLAN, run, environment, write, identity


def main():
    os.umask(0o077)
    pki = OUT / 'private-pki'
    pki.mkdir(mode=0o700)
    run('pki-new-ca', ['openssl', 'req', '-x509', '-newkey', 'rsa:3072', '-nodes', '-days', '14',
        '-subj', '/CN=Mirrors Qualification 20261105', '-addext', 'basicConstraints=critical,CA:TRUE',
        '-addext', 'keyUsage=critical,keyCertSign,cRLSign', '-keyout', pki / 'ca.key',
        '-out', pki / 'ca.crt'], env=environment())
    extension = pki / 'client.ext'
    extension.write_text('basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=clientAuth\n')
    for name in ['linux-client', 'denied-client']:
        run('pki-new-' + name, ['openssl', 'req', '-newkey', 'rsa:2048', '-nodes',
            '-subj', '/CN=' + name, '-keyout', pki / (name + '.key'), '-out', pki / (name + '.csr')], env=environment())
        run('pki-sign-' + name, ['openssl', 'x509', '-req', '-days', '14', '-in', pki / (name + '.csr'),
            '-CA', pki / 'ca.crt', '-CAkey', pki / 'ca.key', '-CAcreateserial', '-extfile', extension,
            '-out', pki / (name + '.crt')], env=environment())
        run('pki-verify-' + name, ['openssl', 'verify', '-CAfile', pki / 'ca.crt',
            '-purpose', 'sslclient', pki / (name + '.crt')], env=environment())
        run('pki-fingerprint-' + name, ['openssl', 'x509', '-in', pki / (name + '.crt'),
            '-outform', 'DER', '-out', pki / (name + '.der')], env=environment())
    write(PLAN / 'local-public-credentials.json', {'newTaskCA': identity(pki / 'ca.crt'),
        'clientLeafSha256': identity(pki / 'linux-client.der')['sha256'],
        'deniedLeafSha256': identity(pki / 'denied-client.der')['sha256'],
        'privateKeysRemainLocal': True, 'privateKeyBytesExported': False})


if __name__ == '__main__':
    main()
