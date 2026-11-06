$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false)
$old='D:\ModelMirrors\staging\qualification-rc7-20261105'
$stage='D:\ModelMirrors\staging\completion-rc10-20261106'
$source=$stage+'\source'
$git='C:\Program Files\Git\cmd\git.exe'
$lean='C:\Users\win10\.elan\toolchains\leanprover--lean4---v4.33.0\bin'
$python='D:\ModelMirrors\staging\windows-fixes-20261106\python312-completion'
$env:PATH="$python;$lean;D:\Programs\msys2\ucrt64\bin;D:\Programs\Perl\c\bin;D:\Programs\jdk-25.0.4+7\bin;C:\Program Files\CMake\bin;C:\Program Files\Git\cmd;C:\Program Files\Git\usr\bin;"+$env:PATH
$env:CC='D:/Programs/Perl/c/bin/gcc.exe';$env:CXX='D:/Programs/Perl/c/bin/g++.exe';$env:CMAKE_GENERATOR='Ninja'
$env:OSSL_INC='D:/Programs/msys2/ucrt64/include';$env:OSSL_LIB='D:/Programs/msys2/ucrt64/lib'
$env:JAVA_HOME='D:\Programs\jdk-25.0.4+7'
$env:TEMP=$stage+'\tmp';$env:TMP=$env:TEMP;$env:TMPDIR=$env:TEMP
$env:MIRRORS_DPM_PYTHON=$python+'\python3.exe'
$env:MIRRORCPP_PREFIX=$old+'\cpp-prefix-rc8';$env:CMAKE_PREFIX_PATH=$env:MIRRORCPP_PREFIX
$env:OPENSSL_ROOT_DIR='D:/Programs/msys2/ucrt64';$env:OPENSSL_CONF=$old+'\openssl-fixture.cnf'
$env:RUST_REPO=$old+'\MirrorRust'
$env:APALACHE_MC=$old+'\runtime-inputs\apalache-qualify-job.exe';$env:APALACHE_JAR=$old+'\runtime-inputs\apalache.jar'
$env:TLA2TOOLS_JAR=$old+'\tla2tools-1.8.0.jar'
$env:PYTHONUTF8='1';$env:PYTHONIOENCODING='utf-8'
function Run([string]$Name,[string]$Exe,[string[]]$Arguments) {
 $log=$stage+'\'+$Name+'.log'
 if(Test-Path -LiteralPath $log){throw 'retain previous command log'}
 $start=(Get-Date).ToUniversalTime().ToString('o')
 $line='"'+$Exe+'" '+(($Arguments|ForEach-Object{'"'+$_+'"'}) -join ' ')+' > "'+$log+'" 2>&1'
 Push-Location -LiteralPath $source
 try{& cmd.exe /d /s /c $line;$code=$LASTEXITCODE}finally{Pop-Location}
 [ordered]@{name=$Name;exitCode=$code;startedAt=$start;finishedAt=(Get-Date).ToUniversalTime().ToString('o');argv=@($Exe)+$Arguments;log=$log;sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $log).Hash.ToLower()}|ConvertTo-Json -Depth 5|Set-Content -Encoding UTF8 -LiteralPath ($stage+'\'+$Name+'.json')
 Write-Output ($Name+' EXIT '+$code)
 if($code -ne 0){exit $code}
}

$env:PATH='C:\Program Files\Git\bin;C:\Users\win10\.cargo\bin;'+$env:PATH
if(-not(Test-Path -LiteralPath ($env:RUST_REPO+'\Cargo.toml'))){throw 'Rust SDK missing'}
if((& $git -C $env:RUST_REPO rev-parse HEAD).Trim() -ne '6b9480ab81717b76ca7f74b41fc554578b70c890'){throw 'Rust SDK revision differs'}
Run 'rc10-rust-explicit' ($old+'\runtime-inputs\native-test-job-detached.exe') @('C:\Program Files\Git\bin\bash.exe','tools/model-interface-rust/check.sh')
Run 'rc10-clean-full-test-admitted' ($old+'\runtime-inputs\native-test-job-detached.exe') @(($lean+'\lake.exe'),'test')
if((& $git -C $source status --porcelain)){throw 'source changed'}
$log=Get-Content -Raw -LiteralPath ($stage+'\rc10-clean-full-test-admitted.log')
if($log -match 'SKIP Rust generated binding execution' -or $log -notmatch 'NATIVE RUST GENERATED BINDING EXECUTION GREEN'){throw 'Rust gate did not execute in full test'}
Write-Output 'RC10 FULL WINDOWS WITH RUST EXECUTION CONFIRMED'
