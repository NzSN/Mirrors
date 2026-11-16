"""Renew owned fixture certificates; private keys stay on their generating host."""
import base64
import sys
from common import *


def main():
    attempt = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    suffix = '' if attempt == 1 else '-attempt' + str(attempt)
    pki = OUT / ('private-pki' + suffix)
    pki.mkdir(mode=0o700)
    prior_umask = os.umask(0o077)
    try:
        run('pki-linux-client-csr' + suffix, ['openssl', 'req', '-new', '-newkey', 'rsa:2048', '-nodes',
            '-subj', '/CN=mirrors-rc12-linux-client', '-keyout', pki / 'linux-client.key',
            '-out', pki / 'linux-client.csr'], env=environment())
    finally:
        os.umask(prior_umask)
    csr = base64.b64encode((pki / 'linux-client.csr').read_bytes()).decode('ascii')
    script = r'''
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
$stage='D:\ModelMirrors\staging\completion-rc12-20261116'
$pki=$stage+'\private-pki'
if(Test-Path -LiteralPath $pki){throw 'retain previous fixture PKI'}
New-Item -ItemType Directory -Path $pki | Out-Null
$acl=New-Object Security.AccessControl.DirectorySecurity
$acl.SetAccessRuleProtection($true,$false)
foreach($sid in @([Security.Principal.WindowsIdentity]::GetCurrent().User.Value,'S-1-5-18','S-1-5-32-544')) {
 $rule=New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier($sid)),'FullControl','ContainerInherit,ObjectInherit','None','Allow')
 $acl.AddAccessRule($rule)
}
Set-Acl -LiteralPath $pki -AclObject $acl
$openssl='D:\Programs\msys2\ucrt64\bin\openssl.exe'
$config=@'
[req]
distinguished_name=dn
prompt=no
[dn]
CN=mirrors-rc12-qualification
[server]
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:localhost,IP:127.0.0.1
[client]
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=clientAuth
'@
[IO.File]::WriteAllText(($pki+'\openssl.cnf'),$config,(New-Object Text.UTF8Encoding($false)))
$env:OPENSSL_CONF=$pki+'\openssl.cnf'
function OpenSsl([string[]]$arguments) {
 $ErrorActionPreference='Continue'
 & $openssl @arguments 2> ($pki+'\last-command.stderr')
 if($LASTEXITCODE -ne 0){throw ('fixture OpenSSL command failed: '+($arguments -join ' '))}
}
OpenSsl @('req','-x509','-newkey','rsa:2048','-nodes','-days','14','-subj','/CN=mirrors-rc12-qualification-ca','-addext','basicConstraints=critical,CA:TRUE','-addext','keyUsage=critical,keyCertSign,cRLSign','-keyout',($pki+'\ca.key'),'-out',($pki+'\ca.crt'))
OpenSsl @('req','-new','-newkey','rsa:2048','-nodes','-subj','/CN=localhost','-keyout',($pki+'\server.key'),'-out',($pki+'\server.csr'))
OpenSsl @('x509','-req','-days','14','-in',($pki+'\server.csr'),'-CA',($pki+'\ca.crt'),'-CAkey',($pki+'\ca.key'),'-set_serial','1201','-extfile',($pki+'\openssl.cnf'),'-extensions','server','-out',($pki+'\server.crt'))
[IO.File]::WriteAllBytes(($pki+'\linux-client.csr'),[Convert]::FromBase64String('CSR_BASE64'))
OpenSsl @('x509','-req','-days','14','-in',($pki+'\linux-client.csr'),'-CA',($pki+'\ca.crt'),'-CAkey',($pki+'\ca.key'),'-set_serial','1202','-extfile',($pki+'\openssl.cnf'),'-extensions','client','-out',($pki+'\linux-client.crt'))
OpenSsl @('req','-new','-newkey','rsa:2048','-nodes','-subj','/CN=mirrors-rc12-windows-client','-keyout',($pki+'\windows-client.key'),'-out',($pki+'\windows-client.csr'))
OpenSsl @('x509','-req','-days','14','-in',($pki+'\windows-client.csr'),'-CA',($pki+'\ca.crt'),'-CAkey',($pki+'\ca.key'),'-set_serial','1203','-extfile',($pki+'\openssl.cnf'),'-extensions','client','-out',($pki+'\windows-client.crt'))
function Certificate([string]$name) {
 $cert=New-Object Security.Cryptography.X509Certificates.X509Certificate2($pki+'\'+$name)
 $sha=[Security.Cryptography.SHA256]::Create()
 return @{sha256=([BitConverter]::ToString($sha.ComputeHash($cert.RawData))).Replace('-','').ToLower();notBeforeUtc=$cert.NotBefore.ToUniversalTime().ToString('o');notAfterUtc=$cert.NotAfter.ToUniversalTime().ToString('o')}
}
[ordered]@{schema='mirrors.rc12.fixture-pki/v1';createdAt=[DateTime]::UtcNow.ToString('o');server=(Certificate 'server.crt');linuxClient=(Certificate 'linux-client.crt');windowsClient=(Certificate 'windows-client.crt');caPem=[IO.File]::ReadAllText($pki+'\ca.crt');clientPem=[IO.File]::ReadAllText($pki+'\linux-client.crt');privateKeysExported=$false;productionCredentialsModified=$false}|ConvertTo-Json -Depth 5
'''.replace('CSR_BASE64', csr).replace("$pki=$stage+'\\private-pki'", "$pki=$stage+'\\private-pki" + suffix + "'")
    value = json.loads(remote('pki-windows-issue' + suffix, script, timeout=120))
    for name, key in [('ca.crt', 'caPem'), ('linux-client.crt', 'clientPem')]:
        (pki / name).write_text(value.pop(key))
    value.update(localRoot=str(pki), remoteRoot=STAGE + '\\private-pki' + suffix)
    write(PLAN / 'fixture-pki.json', value)
    print('FRESH OWNED FIXTURE PKI PREPARED; PRIVATE KEYS REMAIN LOCAL TO EACH HOST', flush=True)


if __name__ == '__main__':
    main()
