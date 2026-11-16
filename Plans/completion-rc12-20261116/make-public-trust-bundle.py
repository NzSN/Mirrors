"""Package only renewed public certificates and operator instructions; never keys."""
import hashlib
import json
import re
import zipfile
from pathlib import Path

STAGE=Path(r'D:\ModelMirrors\staging\completion-rc12-20261116')
WORK=STAGE/'production-renewal'


def main():
    source=json.loads((WORK/'renewed-public.json').read_text())
    root=WORK/'public-trust'
    root.mkdir(exist_ok=False)
    for name in ['ca.crt','server.crt','client.crt']:
        (root/name).write_bytes((WORK/name).read_bytes())
    metadata={'schema':'mirrors.public-trust-renewal/v1','endpoint':{'host':'192.168.150.219','port':8999},
              'serverCertificateSha256':source['renewedCertificates']['server']['sha256'],
              'certificates':source['renewedCertificates'],'publicKeySha256':source['publicKeySha256'],
              'existingPrivateKeysPreserved':True,'privateKeysIncluded':False,
              'externalConsumerAcknowledgementsReceived':False}
    (root/'TRUST.json').write_text(json.dumps(metadata,indent=2)+'\n',encoding='utf-8',newline='\n')
    (root/'README.txt').write_text(
        'Mirrors production trust renewal\nEndpoint: 192.168.150.219:8999\n\n'
        'The CA, server and default client certificates expired on 2026-11-13 and are renewed here.\n'
        'Existing CA/server/client private keys and subjects were preserved; renewed certificates have 90-day validity.\n'
        'No private key is included. client.crt pairs with the existing default client key; use TRUST.json public-key hashes to identify the matching key.\n'
        'Replace the expired CA/client certificate in each authorized client and update its server leaf pin to the value in TRUST.json.\n'
        'Replace the old trust anchor rather than retaining the expired same-subject anchor ahead of the renewed one.\n'
        'Keep existing private keys private and do not add them to this bundle or repository.\n'
        'The requesting operator must coordinate other consumers; no acknowledgement or workload acceptance is inferred.\n',
        encoding='utf-8',newline='\n')
    names=['README.txt','TRUST.json','ca.crt','client.crt','server.crt']
    archive=WORK/'mirrors-rc12-public-trust.zip'
    records=[]
    with zipfile.ZipFile(archive,'x',compression=zipfile.ZIP_DEFLATED) as handle:
        for name in names:
            raw=(root/name).read_bytes()
            assert not re.search(rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',raw)
            handle.writestr(name,raw)
            records.append({'name':name,'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest()})
    value={'schema':'mirrors.rc12.public-trust-bundle/v1','status':'public-only-trust-bundle-prepared',
           'archive':{'name':archive.name,'bytes':archive.stat().st_size,'sha256':hashlib.sha256(archive.read_bytes()).hexdigest()},
           'members':records,'privateKeysIncluded':False,'certificates':metadata['certificates'],
           'serverCertificateSha256':metadata['serverCertificateSha256'],
           'externalDistributionOrAcknowledgementsClaimed':False}
    (WORK/'public-trust-bundle.json').write_text(json.dumps(value,indent=2)+'\n')
    print(json.dumps(value,indent=2))


if __name__=='__main__':main()
