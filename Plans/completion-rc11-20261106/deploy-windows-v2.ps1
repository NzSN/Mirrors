param([switch]$Apply)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false)
$stage='D:\ModelMirrors\staging\completion-rc11-20261106'
$active='D:\ModelMirrors\bin\ModelMirrors.exe'
$candidate=$stage+'\mirrors-v0.2.0-rc.11-windows-x86_64\bin\ModelMirrors.exe'
$rollback=$stage+'\rollback'
$expectedOld='8173ddea65f78a88b1a303f8a233dd7113b28e7dc8aefd8916a5add25a3687cc'
$expectedNew='5bfb5248a7ab74bfbe6c86361146daa20b0e5e864699c820269279747ef81fd4'
function Hash([string]$path){return (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLower()}
function Config {
 $values=Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\ModelMirrors\Parameters'
 $sha=[Security.Cryptography.SHA256]::Create();$out=[ordered]@{}
 foreach($name in @('Application','AppDirectory','AppParameters','AppEnvironmentExtra','AppEnvironment','AppStdout','AppStderr')){if($null -ne $values.$name){$raw=$values.$name|ConvertTo-Json -Compress;$out[$name]=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($raw)))).Replace('-','').ToLower()}}
 return ($out|ConvertTo-Json -Compress)
}
function Save([string]$path,$value){if(Test-Path -LiteralPath $path){throw 'retain existing operation receipt'};[IO.File]::WriteAllText($path,($value|ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($false)))}
function Healthy([string]$label){& 'D:\ModelMirrors\staging\windows-fixes-20261106\python312-completion\python3.exe' -I -S -B ($stage+'\production-health-v2.py') $label;if($LASTEXITCODE -ne 0){throw ('production health failed: '+$label)}}
if((Hash $active) -ne $expectedOld -or (Hash $candidate) -ne $expectedNew){throw 'old/new binary precondition differs'}
$base=Get-Content -Raw -LiteralPath ($stage+'\production-health-baseline-admitted\result.json')|ConvertFrom-Json
if($base.status -ne 'passed'){throw 'baseline health is not accepted'}
foreach($file in @('libcrypto-3-x64.dll','libssl-3-x64.dll','zlib1.dll')){if((Hash ('D:\ModelMirrors\bin\'+$file)) -ne (Hash ((Split-Path $candidate)+'\'+$file))){throw 'DLL migration is not part of this operation'}}
foreach($file in @('server.crt','client.crt','ca.crt')){$cert=New-Object Security.Cryptography.X509Certificates.X509Certificate2('D:\ModelMirrors\certs\'+$file);if($cert.NotBefore.ToUniversalTime() -gt [DateTime]::UtcNow -or $cert.NotAfter.ToUniversalTime() -le [DateTime]::UtcNow){throw 'production certificate is not currently valid'}}
$config=Config
if(-not $Apply){
 if(Test-Path -LiteralPath $rollback){throw 'rollback directory already exists'}
 New-Item -ItemType Directory -Path $rollback|Out-Null
 Copy-Item -LiteralPath $active -Destination ($rollback+'\ModelMirrors.exe')
 if((Hash ($rollback+'\ModelMirrors.exe')) -ne $expectedOld -or (Hash $active) -ne $expectedOld){throw 'rollback copy drifted'}
 Save ($stage+'\deployment-prepared.json') ([ordered]@{status='prepared';oldSha256=$expectedOld;newSha256=$expectedNew;configurationHashes=$config;rollbackPath=$rollback+'\ModelMirrors.exe';binaryOnly=$true;productionModified=$false;rebootApproved=$false})
 Write-Output 'DEPLOYMENT PREPARED; APPLY NOT REQUESTED';exit 0
}
$prepared=Get-Content -Raw -LiteralPath ($stage+'\deployment-prepared.json')|ConvertFrom-Json
if($prepared.configurationHashes -ne $config -or (Hash ($rollback+'\ModelMirrors.exe')) -ne $expectedOld){throw 'reviewed configuration or rollback bytes changed'}
foreach($name in @('atomic-previous.exe','rejected-candidate.exe')){if(Test-Path -LiteralPath ($rollback+'\'+$name)){throw 'retain previous atomic backup'}}
$staged='D:\ModelMirrors\bin\.ModelMirrors-rc11-staged-v2.exe'
if(Test-Path -LiteralPath $staged){throw 'previous staged operation exists'}
Copy-Item -LiteralPath $candidate -Destination $staged
if((Hash $staged) -ne $expectedNew){throw 'staged candidate hash differs'}
$replacementStarted=$false
try {
 $replacementStarted=$true
 Stop-Service -Name ModelMirrors
 (Get-Service ModelMirrors).WaitForStatus('Stopped',[TimeSpan]::FromSeconds(30))
 if((Hash $active) -ne $expectedOld -or (Config) -ne $config){throw 'production changed before replacement'}
 [IO.File]::Replace($staged,$active,($rollback+'\atomic-previous.exe'))
 if((Hash ($rollback+'\atomic-previous.exe')) -ne $expectedOld){throw 'atomic backup differs from prior binary'}
 Start-Service -Name ModelMirrors
 (Get-Service ModelMirrors).WaitForStatus('Running',[TimeSpan]::FromSeconds(30))
 if((Hash $active) -ne $expectedNew -or (Config) -ne $config){throw 'deployed identity/configuration differs'}
 Healthy 'deployed'
 Save ($stage+'\deployment-result-v2.json') ([ordered]@{status='deployed-and-live-verified';completedAtUtc=[DateTime]::UtcNow.ToString('o');oldSha256=$expectedOld;newSha256=$expectedNew;configurationPreserved=$true;rollbackRetained=$true;rebootPerformed=$false})
} catch {
 $failure=$_.Exception.Message
 if($replacementStarted){
  Stop-Service -Name ModelMirrors -ErrorAction SilentlyContinue
  (Get-Service ModelMirrors).WaitForStatus('Stopped',[TimeSpan]::FromSeconds(30))
  $restore='D:\ModelMirrors\bin\.ModelMirrors-rc11-rollback-v2.exe'
  if(Test-Path -LiteralPath $restore){throw 'rollback staging conflict'}
  Copy-Item -LiteralPath ($rollback+'\ModelMirrors.exe') -Destination $restore
  if((Hash $restore) -ne $expectedOld){throw 'rollback bytes changed'}
  [IO.File]::Replace($restore,$active,($rollback+'\rejected-candidate.exe'))
  Start-Service -Name ModelMirrors
  (Get-Service ModelMirrors).WaitForStatus('Running',[TimeSpan]::FromSeconds(30))
  Healthy 'rollback-v2'
  Save ($stage+'\deployment-rollback-v2.json') ([ordered]@{status='failed-and-rolled-back';completedAtUtc=[DateTime]::UtcNow.ToString('o');failure=$failure;restoredSha256=(Hash $active);healthVerified=$true;rebootPerformed=$false})
 }
 throw
}
