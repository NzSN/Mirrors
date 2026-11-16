param([switch]$Apply)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
$stage='D:\ModelMirrors\staging\completion-rc12-20261116'
$work=$stage+'\production-renewal'
if(-not $Apply){throw 'explicit approved reboot application is required'}
if($env:COMPUTERNAME -ne 'DESKTOP-6DKB5JD'){throw 'approved reboot host differs'}
$deployed=Get-Content -Raw -LiteralPath ($work+'\deployment-result.json')|ConvertFrom-Json
if($deployed.status -ne 'renewed-trust-and-rc12-deployed-live-verified' -or $deployed.health.status -ne 'passed' -or -not $deployed.health.wrongPinRejected){throw 'deployment has not passed reboot admission'}
$observed=& ($stage+'\deploy-production.ps1') -Mode Observe|ConvertFrom-Json
if($observed.status -ne 'verified-running-auto-deployment' -or $observed.binary.sha256 -ne $deployed.newSha256){throw 'reboot observation differs from deployed identity'}
$path=$work+'\reboot-request.json'
if(Test-Path -LiteralPath $path){throw 'retain prior reboot request; do not issue another reboot blindly'}
$value=[ordered]@{schema='mirrors.rc12.reboot-request/v1';status='reboot-requested';userApproved=$true;requestedAtUtc=[DateTime]::UtcNow.ToString('o');host=$env:COMPUTERNAME;previousBootUpTimeUtc=$observed.lastBootUpTimeUtc;expectedBinarySha256=$observed.binary.sha256;serverCertificateSha256=$observed.certificates.server.sha256;configurationPreserved=$observed.configurationPreserved;privateKeysPreserved=$observed.privateKeysAndAclsPreserved}
[IO.File]::WriteAllText($path,($value|ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($false)))
Write-Output 'APPROVED RC12 REBOOT REQUESTED AFTER LIVE VERIFIED DEPLOYMENT'
& C:\Windows\System32\shutdown.exe /r /t 0 /d p:4:1 /c 'Approved Mirrors rc.12 renewed-trust deployment reboot verification'
if($LASTEXITCODE -ne 0){throw 'reboot request failed'}
