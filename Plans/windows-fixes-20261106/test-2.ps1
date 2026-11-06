$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false)
$s='D:\ModelMirrors\staging\qualification-rc7-20261105'
$src='D:\ModelMirrors\staging\windows-fixes-20261106\Mirrors'
$lean='C:\Users\win10\.elan\toolchains\leanprover--lean4---v4.33.0\bin'
$env:PATH="$lean;D:\Programs\Python310;D:\Programs\Perl\c\bin;D:\Programs\msys2\ucrt64\bin;D:\Programs\jdk-25.0.4+7\bin;C:\Program Files\CMake\bin;C:\Program Files\Git\cmd;C:\Program Files\Git\usr\bin;"+$env:PATH
$env:CC='D:/Programs/Perl/c/bin/gcc.exe'
$env:CXX='D:/Programs/Perl/c/bin/g++.exe'
$env:CMAKE_GENERATOR='Ninja'
$env:OSSL_INC='D:/Programs/msys2/ucrt64/include'
$env:OSSL_LIB='D:/Programs/msys2/ucrt64/lib'
$env:JAVA_HOME='D:\Programs\jdk-25.0.4+7'
$env:TEMP=$s+'\tmp';$env:TMP=$env:TEMP;$env:TMPDIR=$env:TEMP
$env:OPENSSL_ROOT_DIR='D:/Programs/msys2/ucrt64'
$env:MIRRORCPP_PREFIX=$s+'\cpp-prefix-rc8'
$env:CMAKE_PREFIX_PATH=$env:MIRRORCPP_PREFIX
$env:RUST_REPO=$s+'\MirrorRust'
$env:APALACHE_MC=$s+'\runtime-inputs\apalache-qualify.exe'
$env:APALACHE_JAR=$s+'\runtime-inputs\apalache.jar'
$env:TLA2TOOLS_JAR=$s+'\tla2tools-1.8.0.jar'
function Run([string]$Name,[string]$Exe,[string[]]$Arguments) {
 $log=$s+'\logs\'+$Name+'.log'
 if(Test-Path -LiteralPath $log){throw 'retain existing log'}
 $line='"'+$Exe+'" '+(($Arguments|ForEach-Object{'"'+$_+'"'}) -join ' ')+' > "'+$log+'" 2>&1'
 Push-Location -LiteralPath $src
 try{& cmd.exe /d /s /c $line;$code=$LASTEXITCODE}finally{Pop-Location}
 [ordered]@{name=$Name;exitCode=$code;argv=@($Exe)+$Arguments;log=$log;sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $log).Hash.ToLower()}|ConvertTo-Json -Depth 5|Set-Content -Encoding UTF8 -LiteralPath ($s+'\logs\'+$Name+'.json')
 Write-Output ($Name+' EXIT '+$code)
 if($code -ne 0){exit $code}
}
$env:PATH='D:\Programs\msys2\ucrt64\bin;'+$env:PATH
$env:OPENSSL_CONF=$s+'\openssl-fixture.cnf'
$env:PYTHONUTF8='1'
$env:PYTHONIOENCODING='utf-8'



& 'C:\Windows\System32\tar.exe' -xf ($s+'\20261106-fixes-overlay-2.tar') -C $src
if($LASTEXITCODE -ne 0){throw 'overlay failed'}
Run '20261106-fixes-launcher-build-2' ($lean+'\lake.exe') @('build','mirrors_dpm')
foreach($f in @(Get-ChildItem -LiteralPath ($src+'\.lake\build\bin') -Filter '*.exe' -File)){Copy-Item -Force -LiteralPath $f.FullName -Destination (Join-Path $f.DirectoryName $f.BaseName)}
Run '20261106-fixes-dpm-2' ($s+'\runtime-inputs\native-test-job.exe') @('D:\Programs\Python310\python.exe','-m','unittest','discover','-s','tools/deterministic-scheduling/tests')
