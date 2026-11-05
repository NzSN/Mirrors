$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false)
$stage='D:\ModelMirrors\staging\qualification-rc7-20261105'
$pki=$stage+'\private-pki'
$env:APALACHE_MC=$stage+'\runtime-inputs\apalache-qualify-job.exe'
$env:JAVA_HOME='D:\Programs\jdk-25.0.4+7'
$env:PATH='D:\Programs\jdk-25.0.4+7\bin;D:\Programs\msys2\ucrt64\bin;'+$env:PATH
$env:TEMP=$stage+'\tmp\oracle-rc8'
$env:TMP=$env:TEMP
if(-not(Test-Path -LiteralPath $env:TEMP)){New-Item -ItemType Directory -Path $env:TEMP|Out-Null}
$exe=$stage+'\Mirrors-rc8-f328e32\.lake\build\bin\mirror.exe'
if(Get-NetTCPConnection -State Listen -LocalPort 19099 -ErrorAction SilentlyContinue){throw 'qualification port already occupied'}
$local=Get-Content -Raw -LiteralPath ($stage+'\local-public-credentials.json')|ConvertFrom-Json
$windows=Get-Content -Raw -LiteralPath ($stage+'\windows-public-credentials.json')|ConvertFrom-Json
$arguments=@('--server','19099','--bind','127.0.0.1','--tls','--cert',($pki+'\server.crt'),'--key',($pki+'\server.key'),'--ca',($pki+'\ca.crt'),'--jobs','4','--model-interface-allow-client',($local.clientLeafSha256+','+$windows.windowsClientLeafSha256))
$out=$stage+'\logs\oracle-server-rc8.stdout'
$err=$stage+'\logs\oracle-server-rc8.stderr'
if((Test-Path $out) -or (Test-Path $err)){throw 'retain previous oracle logs'}
$process=Start-Process -FilePath $exe -ArgumentList $arguments -WorkingDirectory $stage -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
$record=[ordered]@{pid=$process.Id;createdAt=$process.StartTime.ToUniversalTime().ToString('o');executable=$exe;binarySha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $exe).Hash.ToLower();port=19099;sourceRevision='f328e328d6f961b49ccffefc0a6d0250bec2fb3c';productionServiceUsed=$false}
[IO.File]::WriteAllText(($stage+'\oracle-state-rc8.json'),($record|ConvertTo-Json -Depth 4),(New-Object Text.UTF8Encoding($false)))
$seen=@{}
while(-not $process.HasExited) {
  $all=@(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
  $owned=@{};$owned[[int]$process.Id]=$true
  for($iteration=0;$iteration -lt 4;$iteration++){foreach($child in $all){if($owned.ContainsKey([int]$child.ParentProcessId)){$owned[[int]$child.ProcessId]=$true}}}
  foreach($child in $all){if($owned.ContainsKey([int]$child.ProcessId) -and $child.Name -eq 'java.exe' -and -not $seen.ContainsKey([int]$child.ProcessId)){$seen[[int]$child.ProcessId]=[ordered]@{pid=$child.ProcessId;path=$child.ExecutablePath;sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $child.ExecutablePath).Hash.ToLower()};[IO.File]::WriteAllText(($stage+'\java-observations-rc8.json'),(@($seen.Values)|ConvertTo-Json -Depth 4),(New-Object Text.UTF8Encoding($false)))}}
  Start-Sleep -Milliseconds 500
  $process.Refresh()
}
Write-Output ('QUALIFICATION ORACLE EXIT '+$process.ExitCode)
