$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
$stage='D:\ModelMirrors\staging\s8-dumpledger-workload-20261116'
$log=$stage+'\private\observation-producer-v2.log'
if(Test-Path -LiteralPath $log){throw 'retain previous producer attempt'}
$job='D:\ModelMirrors\staging\qualification-rc7-20261105\runtime-inputs\native-test-job-detached.exe'
$node='D:\Services\node24\node.exe'
foreach($name in @('NODE_OPTIONS','NODE_PATH','NODE_COMPILE_CACHE')){Remove-Item -LiteralPath ('Env:'+ $name) -ErrorAction SilentlyContinue}
$line='"'+$job+'" "'+$node+'" "'+$stage+'\produce-observations-v2.mjs" > "'+$log+'" 2>&1'
& cmd.exe /d /s /c $line
if($LASTEXITCODE -ne 0){throw 'isolated observation producer failed; owned Job cleanup and private logs retained'}
if([IO.File]::ReadAllText($log) -notmatch 'TASK JOB CLEANUP active=0'){throw 'producer cleanup not confirmed'}
[IO.File]::ReadAllText($stage+'\private\observations-v2\receipt.json')
