$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false)
$old='D:\ModelMirrors\staging\qualification-rc7-20261105'
$stage='D:\ModelMirrors\staging\completion-rc11-20261106'
$source=$stage+'\source'
if(Test-Path -LiteralPath $stage){throw 'retain existing rc.11 stage'}
New-Item -ItemType Directory -Path $stage | Out-Null
$git='C:\Program Files\Git\cmd\git.exe'
if((Get-FileHash -Algorithm SHA256 -LiteralPath ($old+'\20261106-rc11-source.bundle')).Hash.ToLower() -ne '943a36f30d9a7c137ad8f08c8ac0edce07acb64efb802dec150176fb27506752'){throw 'source bundle hash mismatch'}
& $git -c core.longpaths=true -c core.autocrlf=false clone --no-hardlinks ($old+'\20261106-rc11-source.bundle') $source
if($LASTEXITCODE -ne 0){throw 'clone failed'}
& $git -C $source config core.longpaths true
& $git -C $source config core.autocrlf false
& $git -C $source config core.filemode false
& $git -C $source remote set-url origin 'https://github.com/NzSN/Mirrors.git'
& $git -C $source checkout --detach '19c31bf09b58e27c2942ca123a2017c30b638216'
if($LASTEXITCODE -ne 0){throw 'checkout failed'}
if((& $git -C $source status --porcelain)){throw 'source is dirty before build'}
Copy-Item -Recurse -LiteralPath 'D:\ModelMirrors\staging\windows-fixes-20261106\Mirrors\.lake' -Destination ($source+'\.lake')
New-Item -ItemType Directory -Path ($stage+'\tmp') | Out-Null
$lean='C:\Users\win10\.elan\toolchains\leanprover--lean4---v4.33.0\bin'
$python='D:\ModelMirrors\staging\windows-fixes-20261106\python312-completion'
$env:PATH="$python;$lean;C:\Users\win10\.cargo\bin;D:\Programs\msys2\ucrt64\bin;D:\Programs\Perl\c\bin;D:\Programs\jdk-25.0.4+7\bin;C:\Program Files\CMake\bin;C:\Program Files\Git\cmd;C:\Program Files\Git\usr\bin;"+$env:PATH
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
Run 'rc11-clean-build' ($lean+'\lake.exe') @('build')
foreach($file in @(Get-ChildItem -LiteralPath ($source+'\.lake\build\bin') -Filter '*.exe' -File)){Copy-Item -Force -LiteralPath $file.FullName -Destination (Join-Path $file.DirectoryName $file.BaseName)}
Run 'rc11-clean-full-test' ($old+'\runtime-inputs\native-test-job-detached.exe') @(($lean+'\lake.exe'),'test')
if((& $git -C $source status --porcelain)){throw 'source changed during build/test'}

$fullLog=Get-Content -Raw -LiteralPath ($stage+'\rc11-clean-full-test.log')
if($fullLog -match 'SKIP Rust generated binding execution' -or $fullLog -notmatch 'NATIVE RUST GENERATED BINDING EXECUTION GREEN'){throw 'native Rust tier did not execute'}
Write-Output 'RC11 FULL WINDOWS INCLUDING NATIVE RUST GREEN'
