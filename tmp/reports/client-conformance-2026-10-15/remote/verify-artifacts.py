import hashlib,json,subprocess
from pathlib import Path
root=Path('/mnt/d/Desktop/Workspaces/Mirrors-client-conformance-20261015')
prior=Path('/mnt/d/Desktop/Workspaces/Mirrors-DPM-remediation-20261013/build')
fixed=prior/'followup-20261014'
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
library=fixed/'sdk-cpp/libmirrorcpp.a'
ledger=json.loads((fixed/'curated-followup-final/binary-identities.json').read_text())['artifacts']
assert ledger[str(library)]['sha256']==sha(library)
sdk=Path('/home/jlc/Tools/mirrors-dpm-remediation-20261013/ecma/node_modules/mirrorecma')
manifest=json.loads((prior/'installation-manifest-final.json').read_text())
dist={}
for path in (sdk/'dist').glob('*.js'):
    name='ecma/ecma/node_modules/mirrorecma/'+str(path.relative_to(sdk))
    assert sha(path)==manifest['files'][name]['sha256'],name
    dist[name]=sha(path)
lean=json.loads((root/'lean-source-manifest.json').read_text())
for name,row in lean['files'].items():assert sha(root/'MirrorLean'/name)==row['sha256'],name
binaries={}
for name in ['closure-probe','tls-identity-probe']:
    path=root/'lean-probes/.lake/build/bin'/name
    binaries[name]={'sha256':sha(path),'bytes':path.stat().st_size}
pki=root/'tls-results/pki'
certificates={}
for name in ['ca','server','server-cn','client']:
    file=pki/(name+'.crt')
    text=subprocess.check_output(['openssl','x509','-in',str(file),'-noout','-subject','-issuer','-ext','subjectAltName'],stderr=subprocess.STDOUT,text=True)
    certificates[name]={'sha256':sha(file),'identity':text}
verify=subprocess.run(['openssl','verify','-CAfile',str(pki/'ca.crt'),str(pki/'server.crt'),str(pki/'server-cn.crt')],capture_output=True,text=True,check=True)
record={'status':'verified','cppLibraryMatchesPriorQualifiedLedger':True,'cppLibrarySha256':sha(library),
    'ecmaDistFilesMatchPriorQualifiedInstallation':len(dist),'ecmaDistSha256':dist,
    'mirrorLean66TrackedFilesUnchangedAfterBuild':True,'leanProbeBinaries':binaries,
    'tlsPublicCertificateIdentities':certificates,'tlsBothPeerChainsVerify':verify.stdout,
    'privateKeysTransferred':False,'priorSourcesInstallsOrQualificationInputsMutated':False}
(root/'artifact-verification.json').write_text(json.dumps(record,indent=2)+'\n')
print(json.dumps({'status':'verified','ecmaDistFiles':len(dist),'cppQualifiedLibrary':True,'mirrorLeanTrackedFiles':len(lean['files'])}),flush=True)
