"""Reobserve availability/source identities and verify no owned producer remains."""
from common import *


def main():
    script=r'''
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
$app='D:\Services\dump-ledger'
$git='C:\Program Files\Git\cmd\git.exe'
$files=@()
foreach($relative in @('package.json','dist\src\main.js','specs\DumpLedger.tla','specs\DumpLedgerTransfer.tla','dist\src\mbt\harness.js','dist\src\mbt\transfer-harness.js')) {
 $path=Join-Path $app $relative;$files+=@(@{path=$path;bytes=(Get-Item -LiteralPath $path).Length;sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLower()})
}
$revision=(& $git -C $app rev-parse HEAD|Out-String).Trim()
$status=@(& $git -C $app status --porcelain)
$health=& C:\Windows\System32\curl.exe --silent --max-time 4 --output NUL --write-out '%{http_code}' http://127.0.0.1:4081/health
$healthExit=$LASTEXITCODE
$owned=@(Get-CimInstance Win32_Process|Where-Object{$_.CommandLine -like '*s8-dumpledger-workload-20261116*produce-observations*'}|Select-Object ProcessId,ParentProcessId,ExecutablePath)
[ordered]@{observedAtUtc=[DateTime]::UtcNow.ToString('o');sourceRevision=$revision;sourceStatus=$status;files=$files;backendHealthStatus=([string]$health);backendHealthExitCode=$healthExit;ownedProducerProcesses=$owned;productionMutationRequested=$false}|ConvertTo-Json -Depth 6
'''
    value=json.loads(remote('after-replay-source-and-service-observation',script))
    before=json.loads((PLAN/'deployment-intake.json').read_text())
    assert value['sourceRevision']==before['sourceRevision'] and value['sourceStatus']==before['sourceStatus']
    expected={item['path']:item for item in before['files']}
    for item in value['files']:
        assert item['sha256']==expected[item['path']]['sha256'] and item['bytes']==expected[item['path']]['bytes']
    assert value['backendHealthExitCode']==0 and value['backendHealthStatus']=='200'
    assert not value['ownedProducerProcesses']
    value.update(selectedSourceAndModelBytesUnchanged=True,sourceOverlaysPreserved=True,ownedProducerCleanupConfirmed=True)
    write(OUT/'after-replay-observation.json',value)
    print(json.dumps({'backendHealth':'200','sourceAndModelBytesUnchanged':True,
          'sourceOverlaysPreserved':True,'ownedProducerProcesses':0},indent=2))


if __name__=='__main__':main()
