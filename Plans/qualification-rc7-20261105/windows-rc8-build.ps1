$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false)
$s='D:\ModelMirrors\staging\qualification-rc7-20261105'
$src=$s+'\Mirrors'
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
$env:MIRRORCPP_PREFIX=$s+'\cpp-prefix-windows-fix'
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
$git='C:\Program Files\Git\cmd\git.exe'
$src=$s
Run 'rc8-source-clone' $git @('-c','core.longpaths=true','-c','core.autocrlf=false','clone','--no-hardlinks',($s+'\mirrors-rc8-f328e32.bundle'),($s+'\Mirrors-rc8-f328e32'))
$src=$s+'\Mirrors-rc8-f328e32'
Run 'rc8-source-longpaths' $git @('config','core.longpaths','true')
Run 'rc8-source-line-endings' $git @('config','core.autocrlf','false')
$freeze=Get-Content -Raw -LiteralPath ($s+'\rc8-freeze-manifest.json')|ConvertFrom-Json
Run 'rc8-source-origin' $git @('remote','set-url','origin',$freeze.validatedLiveSourceRef.repository)
if((& $git -C $src rev-parse HEAD) -ne $freeze.freezeRevision){throw 'source revision mismatch'}
$cpp=$s+'\MirrorCPP-rc8-c95f0e1'
Run 'rc8-cpp-source-clone' $git @('-c','core.longpaths=true','-c','core.autocrlf=false','clone','--no-hardlinks',($src+'\third_party\mirrorcpp\mirrorcpp-windows-v0.1.1.bundle'),$cpp)
& $git -C $cpp config core.longpaths true
& $git -C $cpp config core.autocrlf false
if((& $git -C $cpp rev-parse HEAD) -ne 'c95f0e185436f145af9fad8895430e899bc479a3'){throw 'SDK source revision mismatch'}
$deps=($s+'\cpp-prefix').Replace('\','/')
$prefix=($s+'\cpp-prefix-rc8').Replace('\','/')
$build=$s+'\cpp-build-rc8'
Run 'rc8-cpp-configure' 'C:\Program Files\CMake\bin\cmake.exe' @('-S',$cpp,'-B',$build,'-G','Ninja','-DCMAKE_CXX_COMPILER=D:/Programs/Perl/c/bin/g++.exe','-DCMAKE_C_COMPILER=D:/Programs/Perl/c/bin/gcc.exe','-DMIRRORCPP_WITH_TLS=ON','-DMIRRORCPP_BUILD_TESTS=OFF','-DMIRRORCPP_BUILD_EXAMPLES=OFF','-DMIRRORCPP_BUILD_CLI=OFF','-DMIRRORCPP_BUILD_PORTABILITY_TESTS=ON','-DFETCHCONTENT_FULLY_DISCONNECTED=ON',('-DBoost_INCLUDE_DIR='+$deps+'/include'),('-Dnlohmann_json_DIR='+$deps+'/share/cmake/nlohmann_json'),'-DOPENSSL_ROOT_DIR=D:/Programs/msys2/ucrt64',('-DCMAKE_INSTALL_PREFIX='+$prefix))
Run 'rc8-cpp-build' 'C:\Program Files\CMake\bin\cmake.exe' @('--build',$build,'-j','2')
Run 'rc8-cpp-portability' 'C:\Program Files\CMake\bin\ctest.exe' @('--test-dir',$build,'--output-on-failure')
Run 'rc8-cpp-install' 'C:\Program Files\CMake\bin\cmake.exe' @('--install',$build)
$env:MIRRORCPP_PREFIX=$s+'\cpp-prefix-rc8';$env:CMAKE_PREFIX_PATH=$env:MIRRORCPP_PREFIX
# Source dependency is obtained only from its exact tracked offline carrier.
Run 'rc8-batteries-clone' $git @('-c','core.longpaths=true','-c','core.autocrlf=false','clone','--no-hardlinks',($src+'\third_party\batteries\batteries-v4.33.0.bundle'),($src+'\.lake\packages\batteries'))
Run 'rc8-batteries-checkout' $git @('-C',($src+'\.lake\packages\batteries'),'checkout','--detach','4488d40d070b9700d4d5a6aa342f0d40c31b2a2d')
Run 'rc8-batteries-origin' $git @('-C',($src+'\.lake\packages\batteries'),'remote','set-url','origin','https://github.com/leanprover-community/batteries')
Run 'rc8-source-build' ($lean+'\lake.exe') @('build')
Run 'rc8-version' ($src+'\.lake\build\bin\mirror.exe') @('--version')
if((& $git -C $src status --porcelain)){throw 'source changed during build'}
if((& $git -C $cpp status --porcelain)){throw 'SDK source changed during build'}
