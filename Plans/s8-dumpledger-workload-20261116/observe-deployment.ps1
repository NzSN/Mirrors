$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
$app='D:\Services\dump-ledger'
$runtime='D:\Services\dump-ledger-runtime'
$git='C:\Program Files\Git\cmd\git.exe'
function FileIdentity([string]$path){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){return @{path=$path;exists=$false}};$file=Get-Item -LiteralPath $path;return @{path=$path;exists=$true;bytes=$file.Length;lastWriteUtc=$file.LastWriteTimeUtc.ToString('o');sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLower()}}
$revision=$null;$status=@()
if(Test-Path -LiteralPath ($app+'\.git')){$revision=(& $git -C $app rev-parse HEAD|Out-String).Trim();if($LASTEXITCODE -ne 0){throw 'app source observation failed'};$status=@(& $git -C $app status --porcelain)}
$files=@()
foreach($relative in @('package.json','dist\src\main.js','specs\DumpLedger.tla','specs\DumpLedgerTransfer.tla','dist\src\mbt\harness.js','dist\src\mbt\transfer-harness.js')){$files+=@(FileIdentity ($app+'\'+$relative))}
$databases=@()
foreach($path in @($runtime+'\data\ledger.sqlite',$runtime+'\ledger.sqlite',$app+'\data\ledger.sqlite')) {if(Test-Path -LiteralPath $path -PathType Leaf){$file=Get-Item -LiteralPath $path;$databases+=@(@{path=$path;bytes=$file.Length;lastWriteUtc=$file.LastWriteTimeUtc.ToString('o');walExists=(Test-Path -LiteralPath ($path+'-wal'))})}}
$listeners=@(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue|Where-Object{$_.LocalPort -in @(4080,4081,4082)}|Select-Object LocalAddress,LocalPort,OwningProcess)
$processes=@(Get-CimInstance Win32_Process|Where-Object{$_.Name -eq 'node.exe' -and $_.CommandLine -match 'dump-ledger|tls-proxy'}|Select-Object ProcessId,ParentProcessId,ExecutablePath,CreationDate)
$health=@()
foreach($entry in @(@{name='backend';url='http://127.0.0.1:4081/health'},@{name='proxy';url='https://127.0.0.1:4080/health'})) {
 $reply=& C:\Windows\System32\curl.exe --silent --insecure --max-time 4 --output NUL --write-out '%{http_code}' $entry.url
 $health+=@(@{name=$entry.name;httpStatus=([string]$reply);exitCode=$LASTEXITCODE;scope='loopback status only; proxy certificate not authenticated'})
}
$directories=@();if(Test-Path -LiteralPath $runtime){$directories=@(Get-ChildItem -LiteralPath $runtime -Directory|Select-Object -ExpandProperty Name)}
[ordered]@{schema='mirrors.s8.dumpledger-deployment-intake/v1';observedAtUtc=[DateTime]::UtcNow.ToString('o');host=$env:COMPUTERNAME;appPath=$app;runtimePath=$runtime;sourceRevision=$revision;sourceStatus=$status;files=$files;ledgerCandidates=$databases;listeners=$listeners;nodeProcesses=$processes;health=$health;runtimeDirectories=$directories;envOrAuthDatabaseRead=$false;dumpBytesRead=$false;serviceOrDataMutated=$false}|ConvertTo-Json -Depth 8
