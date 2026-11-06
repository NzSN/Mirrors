$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false)
$stage='D:\ModelMirrors\staging\completion-rc11-20261106'
if($env:COMPUTERNAME -ne 'DESKTOP-6DKB5JD'){throw 'approved reboot host differs'}
$observation=& ($stage+'\observe-deployment.ps1')|ConvertFrom-Json
if($observation.status -ne 'verified-running-auto-deployment'){throw 'deployment has not passed reboot admission'}
$receipt=$stage+'\reboot-request.json'
if(Test-Path -LiteralPath $receipt){throw 'retain prior reboot request'}
$value=[ordered]@{status='reboot-requested';userApproved=$true;requestedAtUtc=[DateTime]::UtcNow.ToString('o');host=$env:COMPUTERNAME;previousBootUpTimeUtc=$observation.lastBootUpTimeUtc;expectedBinarySha256=$observation.binary.sha256;configurationPreserved=$observation.configurationPreserved}
[IO.File]::WriteAllText($receipt,($value|ConvertTo-Json -Depth 5),(New-Object Text.UTF8Encoding($false)))
Write-Output 'APPROVED REBOOT REQUESTED AFTER VERIFIED DEPLOYMENT'
& C:\Windows\System32\shutdown.exe /r /t 0 /d p:4:1 /c 'Approved Mirrors rc.11 post-deployment reboot verification'
if($LASTEXITCODE -ne 0){throw 'reboot request failed'}
