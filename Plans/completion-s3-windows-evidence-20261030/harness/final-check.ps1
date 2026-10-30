$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false)
$Stage='D:/ModelMirrors/staging/s3-windows-20261030-d737aa0'
function Sha([string]$p){ if(Test-Path -LiteralPath $p){ (Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToLower() } else { $null } }
$files=[ordered]@{}
foreach($p in @('D:\ModelMirrors\bin\ModelMirrors.exe','D:\ModelMirrors\bin\libcrypto-3-x64.dll','D:\ModelMirrors\bin\libssl-3-x64.dll','D:\ModelMirrors\bin\zlib1.dll','D:\ModelMirrors\certs\server.crt','D:\ModelMirrors\certs\ca.crt','D:\ModelMirrors\certs\server.key')){
  $exists=Test-Path -LiteralPath $p; $bytes=$null; $lw=$null
  if($exists){$i=Get-Item -LiteralPath $p; $bytes=$i.Length; $lw=$i.LastWriteTimeUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')}
  $files[$p]=[ordered]@{sha256=(Sha $p);bytes=$bytes;lastWriteUtc=$lw;hashOnly=($p -like '*.key')}
}
$service=Get-CimInstance Win32_Service -Filter "Name='ModelMirrors'" -ErrorAction SilentlyContinue
$procs=@(Get-CimInstance Win32_Process -Filter "Name='ModelMirrors.exe'" | ForEach-Object { [ordered]@{pid=$_.ProcessId;path=$_.ExecutablePath;created=$_.CreationDate;commandLine=$_.CommandLine} })
$ancestors=@()
$walk=$PID
for($i=0;$i -lt 10;$i++){ $cur=Get-CimInstance Win32_Process -Filter ("ProcessId="+$walk) -ErrorAction SilentlyContinue; if(-not $cur){break}; $ancestors+=$cur.ProcessId; $walk=$cur.ParentProcessId; if(-not $walk){break} }
$matched=@(Get-CimInstance Win32_Process | Where-Object { ($_.ExecutablePath -and $_.ExecutablePath.StartsWith('D:\ModelMirrors\staging\s3-windows-20261030-d737aa0',[System.StringComparison]::OrdinalIgnoreCase)) -or ($_.CommandLine -and $_.CommandLine.Contains('s3-windows-20261030-d737aa0')) })
$observer=@($matched | Where-Object { $ancestors -contains $_.ProcessId } | ForEach-Object { [ordered]@{pid=$_.ProcessId;name=$_.Name;commandLine=$_.CommandLine} })
$stageProcs=@($matched | Where-Object { -not ($ancestors -contains $_.ProcessId) } | ForEach-Object { [ordered]@{pid=$_.ProcessId;name=$_.Name;path=$_.ExecutablePath;commandLine=$_.CommandLine} })
$buildEnv=Get-Content -Raw -LiteralPath (Join-Path $Stage 'build-environment.json') | ConvertFrom-Json
$package=Get-Content -Raw -LiteralPath (Join-Path $Stage 'windows-package-receipt.json') | ConvertFrom-Json
$after=[ordered]@{
 schema='mirrors.s3.windows-observation/v1'
 capturedAtUtc=(Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
 production=@($procs)
 serviceStatus=($(if($service){$service.State}else{$null}))
 files=$files
 productionExecutableUnchanged=((Sha 'D:\ModelMirrors\bin\ModelMirrors.exe') -eq '8173ddea65f78a88b1a303f8a233dd7113b28e7dc8aefd8916a5add25a3687cc')
 productionPidUnchanged=(@($procs).Count -eq 1 -and @($procs)[0].pid -eq 9920)
 configurationHashes=[ordered]@{serverCrt=(Sha 'D:\ModelMirrors\certs\server.crt');caCrt=(Sha 'D:\ModelMirrors\certs\ca.crt');serverKeyHashOnly=(Sha 'D:\ModelMirrors\certs\server.key')}
 taskOwnedDescendants=$stageProcs
 observerProcesses=$observer
 taskOwnedDescendantCount=@($stageProcs).Count
 packageZipSha256=(Get-Content -Raw -LiteralPath (Join-Path $Stage 'windows-package-archive.json') | ConvertFrom-Json).sha256
 repeatedPackagingIdentical=($package.archive.repeatedPackagingIdentical)
}
$after | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $Stage 'final-observation.json') -Encoding UTF8
Write-Output ("PROD_SHA_UNCHANGED " + $after.productionExecutableUnchanged)
Write-Output ("PROD_PID_UNCHANGED " + $after.productionPidUnchanged)
Write-Output ("TASK_DESCENDANTS " + $after.taskOwnedDescendantCount)
Write-Output ("ZIP " + $after.packageZipSha256)
Write-Output ("REPEAT_IDENTICAL " + $after.repeatedPackagingIdentical)
