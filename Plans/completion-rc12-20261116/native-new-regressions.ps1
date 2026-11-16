$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
$stage='D:\ModelMirrors\staging\completion-rc12-20261116'
$source=$stage+'\source'
$python='D:\ModelMirrors\staging\windows-fixes-20261106\python312-completion\python3.exe'
$job='D:\ModelMirrors\staging\qualification-rc7-20261105\runtime-inputs\native-test-job-detached.exe'
$log=$stage+'\native-new-regressions-attempt2.log'
if(Test-Path -LiteralPath $log){throw 'retain previous regression log'}
$env:PATH='D:\Programs\msys2\ucrt64\bin;D:\Programs\Perl\c\bin;'+$env:PATH
$env:OPENSSL_CONF='D:\ModelMirrors\staging\qualification-rc7-20261105\openssl-fixture.cnf'
$env:PYTHONUTF8='1';$env:PYTHONIOENCODING='utf-8'
$env:TEMP=$stage+'\tmp';$env:TMP=$env:TEMP
Push-Location -LiteralPath $source
try {
 $line='"'+$job+'" "'+$python+'" -I -S -B "'+$stage+'\native-new-regressions.py" > "'+$log+'" 2>&1'
 & cmd.exe /d /s /c $line
 $code=$LASTEXITCODE
} finally {Pop-Location}
if($code -ne 0){throw 'native regressions failed; bounded log retained'}
[IO.File]::ReadAllText($log)
