param([ValidateSet('Prepare','Apply','Observe')][string]$Mode='Prepare')
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
$stage='D:\ModelMirrors\staging\completion-rc12-20261116'
$work=$stage+'\production-renewal'
$bin='D:\ModelMirrors\bin'
$certs='D:\ModelMirrors\certs'
$active=$bin+'\ModelMirrors.exe'
$candidate=$stage+'\mirrors-v0.2.0-rc.12-windows-x86_64\bin\ModelMirrors.exe'
$rollback=$work+'\rollback'
$oldSha='5bfb5248a7ab74bfbe6c86361146daa20b0e5e864699c820269279747ef81fd4'
$newSha='5ebfb99399df6006b2dcae81a64525421ca0f4490ac19dcd3a9ed8f51676d5e9'
$baseline=Get-Content -Raw -LiteralPath ($work+'\private-baseline.json')|ConvertFrom-Json
$renewed=Get-Content -Raw -LiteralPath ($work+'\renewed-public.json')|ConvertFrom-Json
function Hash([string]$path){return (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLower()}
function Save([string]$path,$value){if(Test-Path -LiteralPath $path){throw 'retain prior operation receipt'};[IO.File]::WriteAllText($path,($value|ConvertTo-Json -Depth 14),(New-Object Text.UTF8Encoding($false)))}
function ConfigHashes {
 $values=Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\ModelMirrors\Parameters'
 $sha=[Security.Cryptography.SHA256]::Create();$result=[ordered]@{}
 foreach($name in @('Application','AppDirectory','AppParameters','AppEnvironmentExtra','AppEnvironment','AppStdout','AppStderr')){if($null -ne $values.$name){$raw=$values.$name|ConvertTo-Json -Compress;$result[$name]=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($raw)))).Replace('-','').ToLower()}}
 return $result
}
function Unchanged {
 $config=ConfigHashes
 if($config.Count -ne @($baseline.configurationHashes.PSObject.Properties).Count){throw 'configuration shape changed'}
 foreach($property in $baseline.configurationHashes.PSObject.Properties){if($config[$property.Name] -ne $property.Value){throw 'production configuration drifted'}}
 foreach($name in @('ca','server','client')) {
  if((Hash ($certs+'\'+$name+'.key')) -ne $baseline.privateKeyHashes.$name -or (Get-Acl -LiteralPath ($certs+'\'+$name+'.key')).Sddl -ne $baseline.privateKeyAcls.$name){throw 'private key or ACL drifted'}
 }
 foreach($property in $baseline.dllHashes.PSObject.Properties){if((Hash ($bin+'\'+$property.Name)) -ne $property.Value){throw 'production DLL changed'}}
 if((Hash 'D:\Programs\apalache\lib\apalache.jar') -ne '079b6c2320252469dcf79afec6886b8255d3dd1b34a9484433c88986752efaa8' -or (Hash 'D:\Programs\jdk-25.0.4+7\bin\java.exe') -ne '58df5c13e5d6e68f242ad9b724479122828523008ef0907d3f2a02f54afaff23'){throw 'configured runtime pins differ'}
}
function CertificatesNew {
 $sha=[Security.Cryptography.SHA256]::Create()
 foreach($name in @('ca','server','client')) {
  $path=$certs+'\'+$name+'.crt'
  if((Hash $path) -ne (Hash ($work+'\'+$name+'.crt'))){throw 'active certificate bytes differ from admitted renewal'}
  if((Get-Acl -LiteralPath $path).Sddl -ne $baseline.certificateAcls.$name){throw 'certificate ACL changed'}
  $cert=New-Object Security.Cryptography.X509Certificates.X509Certificate2($path)
  $pin=([BitConverter]::ToString($sha.ComputeHash($cert.RawData))).Replace('-','').ToLower()
  if($pin -ne $renewed.renewedCertificates.$name.sha256 -or $cert.NotBefore.ToUniversalTime() -gt [DateTime]::UtcNow -or $cert.NotAfter.ToUniversalTime() -le [DateTime]::UtcNow){throw 'renewed certificate identity or validity differs'}
 }
}
function StopActive {
 Stop-Service -Name ModelMirrors
 (Get-Service ModelMirrors).WaitForStatus('Stopped',[TimeSpan]::FromSeconds(30))
 for($attempt=0;$attempt -lt 40;$attempt++) {
  if(@(Get-CimInstance Win32_Process|Where-Object{$_.ExecutablePath -eq $active}).Count -eq 0){return}
  Start-Sleep -Milliseconds 250
 }
 throw 'owned production executable remains after service stop'
}
function StartActive {
 Start-Service -Name ModelMirrors
 (Get-Service ModelMirrors).WaitForStatus('Running',[TimeSpan]::FromSeconds(30))
}
function Healthy([string]$label) {
 $python='D:\ModelMirrors\staging\windows-fixes-20261106\python312-completion\python3.exe'
 $job='D:\ModelMirrors\staging\qualification-rc7-20261105\runtime-inputs\native-test-job-detached.exe'
 $log=$work+'\health-driver-'+$label+'.log'
 if(Test-Path -LiteralPath $log){throw 'retain previous production health attempt'}
 $env:PYTHONUTF8='1';$env:PYTHONIOENCODING='utf-8'
 $line='"'+$job+'" "'+$python+'" -I -S -B "'+$stage+'\production-health.py" "'+$label+'" > "'+$log+'" 2>&1'
 & cmd.exe /d /s /c $line
 if($LASTEXITCODE -ne 0){throw ('production health failed: '+$label)}
 $raw=[IO.File]::ReadAllText($log)
 if($raw -notmatch 'TASK JOB CLEANUP active=0'){throw 'health client job cleanup is not confirmed'}
 $health=Get-Content -Raw -LiteralPath ($stage+'\production-health-'+$label+'\result.json')|ConvertFrom-Json
 if($health.status -ne 'passed' -or $health.cases.Count -ne 4 -or -not $health.wrongPinRejected -or $health.clientSha256 -ne $newSha -or $health.serverCertificateSha256 -ne $renewed.renewedCertificates.server.sha256){throw 'health identity or case set differs'}
 return $health
}
function Observe {
 Unchanged
 CertificatesNew
 if((Hash $active) -ne $newSha){throw 'deployed executable differs'}
 $service=Get-CimInstance Win32_Service -Filter "Name='ModelMirrors'"
 if($service.State -ne 'Running' -or $service.StartMode -ne 'Auto'){throw 'service is not Running/Auto'}
 $processes=@(Get-CimInstance Win32_Process|Where-Object{$_.ExecutablePath -eq $active})
 if($processes.Count -ne 1){throw 'expected exactly one production executable'}
 $listeners=@(Get-NetTCPConnection -State Listen -LocalPort 8999 -ErrorAction Stop|Select-Object LocalAddress,LocalPort,OwningProcess)
 if($listeners.Count -lt 1 -or @($listeners|Where-Object{$_.OwningProcess -ne $processes[0].ProcessId}).Count -ne 0){throw 'listener ownership differs'}
 $os=Get-CimInstance Win32_OperatingSystem
 return [ordered]@{status='verified-running-auto-deployment';observedAtUtc=[DateTime]::UtcNow.ToString('o');lastBootUpTimeUtc=$os.LastBootUpTime.ToUniversalTime().ToString('o');service=@{name=$service.Name;state=$service.State;startMode=$service.StartMode;pid=$service.ProcessId};serverPid=$processes[0].ProcessId;serverCreatedAtUtc=$processes[0].CreationDate.ToUniversalTime().ToString('o');binary=@{path=$active;sha256=(Hash $active)};listeners=$listeners;configurationPreserved=$true;configurationHashes=(ConfigHashes);privateKeysAndAclsPreserved=$true;dllHashes=$baseline.dllHashes;certificates=$renewed.renewedCertificates;runtime=@{apalacheJarSha256=(Hash 'D:\Programs\apalache\lib\apalache.jar');javaExecutableSha256=(Hash 'D:\Programs\jdk-25.0.4+7\bin\java.exe');adapterSha256=(Hash ($bin+'\apalache-mc.exe'))};sourceCommit='6882d5b8b4787977e847e5a77467b30bfdac19a2'}
}
if($env:COMPUTERNAME -ne 'DESKTOP-6DKB5JD'){throw 'approved host differs'}
if($Mode -eq 'Observe'){Observe|ConvertTo-Json -Depth 14;exit 0}
Unchanged
if((Hash $active) -ne $oldSha -or (Hash $candidate) -ne $newSha -or (Hash ($rollback+'\ModelMirrors.exe')) -ne $oldSha){throw 'old/new/rollback binary precondition differs'}
$trial=Get-Content -Raw -LiteralPath ($stage+'\production-trust-trials.json')|ConvertFrom-Json
if($trial.status -ne 'candidate-and-rollback-renewed-chain-trials-passed' -or $trial.ownedJobCleanupActive -ne 0 -or $trial.cases.Count -ne 2){throw 'renewed-trust trial admission missing'}
foreach($case in $trial.cases){if($case.health.status -ne 'passed' -or -not $case.health.wrongPinRejected -or $case.health.cases.Count -ne 4){throw 'trial health membership differs'}}
foreach($name in @('ca','server','client')){if((Hash ($certs+'\'+$name+'.crt')) -ne $baseline.certificateFileHashes.$name -or (Get-Acl -LiteralPath ($certs+'\'+$name+'.crt')).Sddl -ne $baseline.certificateAcls.$name){throw 'active certificate baseline changed'}}
$stagedBinary=$bin+'\.ModelMirrors-rc12-staged.exe'
if($Mode -eq 'Prepare') {
 foreach($name in @('ca','server','client')) {
  $target=$certs+'\.mirrors-rc12-'+$name+'.crt'
  if(Test-Path -LiteralPath $target){throw 'retain previous certificate staging file'}
  Copy-Item -LiteralPath ($work+'\'+$name+'.crt') -Destination $target
  Set-Acl -LiteralPath $target -AclObject (Get-Acl -LiteralPath ($certs+'\'+$name+'.crt'))
  if((Hash $target) -ne (Hash ($work+'\'+$name+'.crt'))){throw 'staged certificate differs'}
 }
 if(Test-Path -LiteralPath $stagedBinary){throw 'retain previous staged executable'}
 Copy-Item -LiteralPath $candidate -Destination $stagedBinary
 $binaryAcl=(Get-Acl -LiteralPath $active).Sddl
 Set-Acl -LiteralPath $stagedBinary -AclObject (Get-Acl -LiteralPath $active)
 if((Hash $stagedBinary) -ne $newSha){throw 'staged executable differs'}
 Save ($work+'\deployment-prepared.json') ([ordered]@{status='prepared';oldSha256=$oldSha;newSha256=$newSha;binaryAcl=$binaryAcl;oldCertificatesRetained=$true;renewedTrustTrialsPassed=$true;activeProductionModified=$false})
 [ordered]@{status='prepared';oldSha256=$oldSha;newSha256=$newSha;activeProductionModified=$false}|ConvertTo-Json
 exit 0
}
$prepared=Get-Content -Raw -LiteralPath ($work+'\deployment-prepared.json')|ConvertFrom-Json
if((Hash $stagedBinary) -ne $newSha -or $prepared.newSha256 -ne $newSha){throw 'prepared executable changed'}
foreach($name in @('ca','server','client')){if((Hash ($certs+'\.mirrors-rc12-'+$name+'.crt')) -ne (Hash ($work+'\'+$name+'.crt'))){throw 'prepared public certificate changed'}}
foreach($name in @('atomic-old-binary.exe','rejected-candidate.exe','atomic-ca.crt','atomic-server.crt','atomic-client.crt')){if(Test-Path -LiteralPath ($rollback+'\'+$name)){throw 'retain previous atomic backup'}}
$trustAccepted=$false
try {
 StopActive
 Unchanged
 foreach($name in @('ca','server','client')) {
  $path=$certs+'\'+$name+'.crt'
  if((Hash $path) -ne $baseline.certificateFileHashes.$name){throw 'certificate changed before activation'}
  [IO.File]::Replace(($certs+'\.mirrors-rc12-'+$name+'.crt'),$path,($rollback+'\atomic-'+$name+'.crt'))
  if((Hash ($rollback+'\atomic-'+$name+'.crt')) -ne $baseline.certificateFileHashes.$name){throw 'retained original certificate differs'}
 }
 CertificatesNew
 StartActive
 $baselineHealth=Healthy 'trust-renewed-baseline'
 Unchanged
 if((Hash $active) -ne $oldSha){throw 'old binary changed during trust baseline'}
 $trustAccepted=$true
 Save ($work+'\trust-activation-result.json') ([ordered]@{status='renewed-chain-live-baseline-passed';completedAtUtc=[DateTime]::UtcNow.ToString('o');binarySha256=$oldSha;health=$baselineHealth;certificates=$renewed.renewedCertificates;existingKeysAndConfigurationPreserved=$true})
 StopActive
 Unchanged
 CertificatesNew
 if((Hash $active) -ne $oldSha -or (Hash $stagedBinary) -ne $newSha){throw 'binary changed before activation'}
 [IO.File]::Replace($stagedBinary,$active,($rollback+'\atomic-old-binary.exe'))
 if((Hash ($rollback+'\atomic-old-binary.exe')) -ne $oldSha -or (Hash $active) -ne $newSha){throw 'atomic executable replacement differs'}
 if((Get-Acl -LiteralPath $active).Sddl -ne $prepared.binaryAcl){throw 'executable ACL changed'}
 StartActive
 $deployedHealth=Healthy 'deployed'
 $observation=Observe
 $result=[ordered]@{schema='mirrors.rc12.production-deployment/v1';status='renewed-trust-and-rc12-deployed-live-verified';completedAtUtc=[DateTime]::UtcNow.ToString('o');oldSha256=$oldSha;newSha256=$newSha;trustBaselineHealth=$baselineHealth;health=$deployedHealth;observation=$observation;existingKeysAndAclsPreserved=$true;configurationAndDllsPreserved=$true;rollbackUnderRenewedPkiTested=$true;rollbackBytesRetained=$true;rebootPerformed=$false}
 Save ($work+'\deployment-result.json') $result
 $result|ConvertTo-Json -Depth 14
} catch {
 $failure=$_.Exception.Message
 Stop-Service -Name ModelMirrors -ErrorAction SilentlyContinue
 (Get-Service ModelMirrors).WaitForStatus('Stopped',[TimeSpan]::FromSeconds(30))
 $current=Hash $active
 if($current -ne $oldSha -and $current -ne $newSha){throw 'unrecognized executable after failure; refusing overwrite'}
 if($current -ne $oldSha) {
  $restore=$bin+'\.ModelMirrors-rc12-rollback.exe'
  if(Test-Path -LiteralPath $restore){throw 'retain rollback staging conflict'}
  Copy-Item -LiteralPath ($rollback+'\ModelMirrors.exe') -Destination $restore
  Set-Acl -LiteralPath $restore -AclObject (Get-Acl -LiteralPath $active)
  if((Hash $restore) -ne $oldSha){throw 'rollback copy differs'}
  [IO.File]::Replace($restore,$active,($rollback+'\rejected-candidate.exe'))
 }
 if(-not $trustAccepted) {
  foreach($name in @('ca','server','client')) {
   $path=$certs+'\'+$name+'.crt';$current=Hash $path
   if($current -ne $baseline.certificateFileHashes.$name) {
    if($current -ne (Hash ($work+'\'+$name+'.crt'))){throw 'unrecognized certificate after failure; refusing overwrite'}
    $restore=$certs+'\.mirrors-rc12-restore-'+$name+'.crt'
    Copy-Item -LiteralPath ($work+'\old-certificates\'+$name+'.crt') -Destination $restore
    Set-Acl -LiteralPath $restore -AclObject (Get-Acl -LiteralPath $path)
    [IO.File]::Replace($restore,$path,($rollback+'\rejected-'+$name+'.crt'))
   }
  }
 }
 Unchanged
 StartActive
 $recoveredHealth=$null
 if($trustAccepted){CertificatesNew;$recoveredHealth=Healthy 'rollback-after-failure'}
 Save ($work+'\deployment-failure.json') ([ordered]@{status=if($trustAccepted){'failed-and-old-binary-restored-with-valid-renewed-trust'}else{'failed-and-expired-original-baseline-restored'};failure=$failure;oldBinaryRestored=((Hash $active) -eq $oldSha);trustAccepted=$trustAccepted;health=$recoveredHealth;expiredBaselineIsNotHealthSuccess=(-not $trustAccepted)})
 throw
}
