"""Admit the actual native package and transfer owned fixture lifecycle helpers."""
import zipfile
from common import *


def main():
    package = json.loads((PLAN / 'windows-package.json').read_text())
    archive = OUT / 'windows-receipts' / package['archive']['name']
    assert identity(archive)['sha256'] == package['archive']['sha256']
    prefix = 'mirrors-' + TAG + '-windows-x86_64/'
    with zipfile.ZipFile(archive) as handle:
        wanted = {prefix + name for name in package['package']['files']} | {prefix + 'BUILD.json', prefix + 'README.txt'}
        assert len(handle.namelist()) == len(wanted) and set(handle.namelist()) == wanted
        assert json.loads(handle.read(prefix + 'BUILD.json')) == package['package']
        for name, expected in package['package']['files'].items():
            raw = handle.read(prefix + name)
            assert len(raw) == expected['bytes'] and hashlib.sha256(raw).hexdigest() == expected['sha256']
    write(PLAN / 'windows-package-local-verification.json', {
        'status': 'archive-membership-and-every-member-identity-verified',
        'sourceCommit': COMMIT, 'archive': identity(archive), 'embeddedBuildManifestMatches': True,
        'binaryAndDllMembersVerified': len(package['package']['files']), 'published': False})
    names = ['windows-oracle.ps1', 'observe-remote2.ps1', 'stop-owned-oracle-admitted.ps1', 'fixture-pki.json']
    paths = [PLAN / name for name in names]
    scp = ['scp', '-F', str(Path.home() / '.ssh/config'), '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes']
    run('fixture-helper-transfer', scp + paths + ['win10:D:/ModelMirrors/staging/completion-rc12-20261116/'], timeout=180)
    expected = {name: identity(PLAN / name)['sha256'] for name in names}
    script = r'''
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
$stage='D:\ModelMirrors\staging\completion-rc12-20261116'
$expected=ConvertFrom-Json 'EXPECTED_JSON'
foreach($property in $expected.PSObject.Properties) {
 $path=$stage+'\'+$property.Name
 if((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLower() -ne $property.Value){throw 'fixture helper transfer hash mismatch'}
}
if(Get-NetTCPConnection -State Listen -LocalPort 19099 -ErrorAction SilentlyContinue){throw 'owned fixture port already occupied'}
$prod=(Get-FileHash -Algorithm SHA256 -LiteralPath 'D:\ModelMirrors\bin\ModelMirrors.exe').Hash.ToLower()
if($prod -ne '5bfb5248a7ab74bfbe6c86361146daa20b0e5e864699c820269279747ef81fd4'){throw 'production baseline changed'}
[ordered]@{status='fixture-inputs-admitted';sourceCommit='6882d5b8b4787977e847e5a77467b30bfdac19a2';productionBinarySha256=$prod;productionModified=$false;portAvailable=$true}|ConvertTo-Json
'''.replace('EXPECTED_JSON', json.dumps(expected, separators=(',', ':')))
    value = json.loads(remote('fixture-input-admission', script))
    write(PLAN / 'fixture-input-admission.json', value)
    print('NATIVE PACKAGE AND OWNED FIXTURE INPUTS ADMITTED', flush=True)


if __name__ == '__main__':
    main()
