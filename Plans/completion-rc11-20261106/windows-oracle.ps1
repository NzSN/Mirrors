$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false)
$stage='D:\ModelMirrors\staging\completion-rc11-20261106'
$inputs='D:\ModelMirrors\staging\qualification-rc7-20261105'
$pki=$inputs+'\private-pki'
$env:APALACHE_MC=$inputs+'\runtime-inputs\apalache-qualify-job.exe'
$env:JAVA_HOME='D:\Programs\jdk-25.0.4+7'
$env:PATH='D:\Programs\jdk-25.0.4+7\bin;D:\Programs\msys2\ucrt64\bin;'+$env:PATH
$env:TEMP=$stage+'\tmp\oracle-rc11'
$env:TMP=$env:TEMP
if(-not(Test-Path -LiteralPath $env:TEMP)){New-Item -ItemType Directory -Path $env:TEMP|Out-Null}
$exe=$stage+'\mirrors-v0.2.0-rc.11-windows-x86_64\bin\ModelMirrors.exe'
if(Get-NetTCPConnection -State Listen -LocalPort 19099 -ErrorAction SilentlyContinue){throw 'qualification port already occupied'}
$local=Get-Content -Raw -LiteralPath ($inputs+'\local-public-credentials.json')|ConvertFrom-Json
$windows=Get-Content -Raw -LiteralPath ($inputs+'\windows-public-credentials.json')|ConvertFrom-Json
$arguments=@('--server','19099','--bind','127.0.0.1','--tls','--cert',($pki+'\server.crt'),'--key',($pki+'\server.key'),'--ca',($pki+'\ca.crt'),'--jobs','4','--model-interface-allow-client',($local.clientLeafSha256+','+$windows.windowsClientLeafSha256))
New-Item -ItemType Directory -Path ($stage+'\logs') -ErrorAction Stop|Out-Null
$out=$stage+'\logs\oracle-server-rc11-attempt2.stdout'
$err=$stage+'\logs\oracle-server-rc11-attempt2.stderr'
if((Test-Path $out) -or (Test-Path $err)){throw 'retain previous oracle logs'}
if((Get-FileHash -Algorithm SHA256 -LiteralPath $exe).Hash.ToLower() -ne '5bfb5248a7ab74bfbe6c86361146daa20b0e5e864699c820269279747ef81fd4'){throw 'candidate binary changed'}
$certificate=New-Object Security.Cryptography.X509Certificates.X509Certificate2($pki+'\server.crt')
if($certificate.NotBefore.ToUniversalTime() -gt [DateTime]::UtcNow -or $certificate.NotAfter.ToUniversalTime() -lt [DateTime]::UtcNow){throw 'task certificate expired'}
$process=Start-Process -FilePath $exe -ArgumentList $arguments -WorkingDirectory $stage -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
$record=[ordered]@{pid=$process.Id;createdAt=$process.StartTime.ToUniversalTime().ToString('o');executable=$exe;binarySha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $exe).Hash.ToLower();port=19099;sourceRevision='19c31bf09b58e27c2942ca123a2017c30b638216';productionServiceUsed=$false}
[IO.File]::WriteAllText(($stage+'\oracle-state-rc11-attempt2.json'),($record|ConvertTo-Json -Depth 4),(New-Object Text.UTF8Encoding($false)))
$seen=@{}
while(-not $process.HasExited) {
  $all=@(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
  $owned=@{};$owned[[int]$process.Id]=$true
  for($iteration=0;$iteration -lt 4;$iteration++){foreach($child in $all){if($owned.ContainsKey([int]$child.ParentProcessId)){$owned[[int]$child.ProcessId]=$true}}}
  foreach($child in $all){if($owned.ContainsKey([int]$child.ProcessId) -and $child.Name -eq 'java.exe' -and -not $seen.ContainsKey([int]$child.ProcessId)){$seen[[int]$child.ProcessId]=[ordered]@{pid=$child.ProcessId;path=$child.ExecutablePath;sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $child.ExecutablePath).Hash.ToLower()};[IO.File]::WriteAllText(($stage+'\java-observations-rc11.json'),(@($seen.Values)|ConvertTo-Json -Depth 4),(New-Object Text.UTF8Encoding($false)))}}
  Start-Sleep -Milliseconds 500
  $process.Refresh()
}
Write-Output ('QUALIFICATION ORACLE EXIT '+$process.ExitCode)
