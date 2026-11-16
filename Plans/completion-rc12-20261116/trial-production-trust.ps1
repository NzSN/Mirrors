$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
$stage='D:\ModelMirrors\staging\completion-rc12-20261116'
$python='D:\ModelMirrors\staging\windows-fixes-20261106\python312-completion\python3.exe'
$job='D:\ModelMirrors\staging\qualification-rc7-20261105\runtime-inputs\native-test-job-detached.exe'
$log=$stage+'\production-renewal\trial-driver.log'
if(Test-Path -LiteralPath $log){throw 'retain prior trust trial'}
$env:PYTHONUTF8='1';$env:PYTHONIOENCODING='utf-8'
$line='"'+$job+'" "'+$python+'" -I -S -B "'+$stage+'\trial-production-trust.py" > "'+$log+'" 2>&1'
& cmd.exe /d /s /c $line
if($LASTEXITCODE -ne 0){throw 'trust trial failed; bounded native Job and logs retained'}
[IO.File]::ReadAllText($log)
