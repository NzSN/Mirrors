$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$Stage = 'D:\ModelMirrors\staging\qualification-rc7-20261105'
$Source = Join-Path $Stage 'Mirrors'
$Logs = Join-Path $Stage 'logs'
if(Test-Path -LiteralPath $Logs){throw 'retain existing attempt'}
New-Item -ItemType Directory -Path $Logs | Out-Null
$lean = 'C:\Users\win10\.elan\toolchains\leanprover--lean4---v4.33.0\bin'
$java = 'D:\Programs\jdk-25.0.4+7\bin'
$env:PATH = "$lean;D:\Programs\Python310;D:\Programs\Perl\c\bin;D:\Programs\msys2\ucrt64\bin;$java;C:\Program Files\CMake\bin;C:\Program Files\Git\cmd;C:\Program Files\Git\usr\bin;" + $env:PATH
$env:CC = 'D:/Programs/Perl/c/bin/gcc.exe'
$env:OSSL_INC = 'D:/Programs/msys2/ucrt64/include'
$env:OSSL_LIB = 'D:/Programs/msys2/ucrt64/lib'
$env:JAVA_HOME = 'D:\Programs\jdk-25.0.4+7'
$env:TEMP = Join-Path $Stage 'tmp'
$env:TMP = $env:TEMP
$env:TMPDIR = $env:TEMP
$env:OPENSSL_ROOT_DIR = 'D:/Programs/msys2/ucrt64'
$env:CMAKE_PREFIX_PATH = (Join-Path $Stage 'cpp-prefix')
$env:MIRRORCPP_PREFIX = $env:CMAKE_PREFIX_PATH
$env:RUST_REPO = Join-Path $Stage 'MirrorRust'
$env:APALACHE_MC = 'D:\ModelMirrors\bin\apalache-mc.exe'
$env:APALACHE_JAR = 'D:\Programs\apalache\lib\apalache.jar'
$env:TLA2TOOLS_JAR = Join-Path $Stage 'tla2tools-1.8.0.jar'
function Run([string]$Name,[string]$Exe,[string[]]$Arguments,[string]$Cwd) {
  $log = Join-Path $Logs ($Name + '.log')
  if(Test-Path -LiteralPath $log){throw 'command log exists'}
  $line = '"' + $Exe + '" ' + (($Arguments | ForEach-Object { '"' + $_ + '"' }) -join ' ') + ' > "' + $log + '" 2>&1'
  Push-Location -LiteralPath $Cwd
  try { & cmd.exe /d /s /c $line; $code=$LASTEXITCODE } finally { Pop-Location }
  [ordered]@{name=$Name;exitCode=$code;argv=@($Exe)+$Arguments;log=$log;sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $log).Hash.ToLower()} | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $Logs ($Name+'.json'))
  Write-Output ($Name + ' EXIT ' + $code)
  if($code -ne 0){exit $code}
}
$cmake = 'C:\Program Files\CMake\bin\cmake.exe'
$cppSource = Join-Path $Stage 'MirrorCPP'
$cppBuild = Join-Path $Stage 'cpp-build'
$prefix = (Join-Path $Stage 'cpp-prefix').Replace('\','/')
Run 'cpp-configure' $cmake @('-S',$cppSource,'-B',$cppBuild,'-G','Ninja','-DCMAKE_CXX_COMPILER=D:/Programs/Perl/c/bin/g++.exe','-DCMAKE_C_COMPILER=D:/Programs/Perl/c/bin/gcc.exe','-DMIRRORCPP_WITH_TLS=ON','-DMIRRORCPP_BUILD_TESTS=OFF','-DMIRRORCPP_BUILD_EXAMPLES=OFF','-DMIRRORCPP_BUILD_CLI=OFF','-DFETCHCONTENT_FULLY_DISCONNECTED=ON',('-DBoost_INCLUDE_DIR='+$prefix+'/include'),('-Dnlohmann_json_DIR='+$prefix+'/share/cmake/nlohmann_json'),'-DOPENSSL_ROOT_DIR=D:/Programs/msys2/ucrt64',('-DCMAKE_INSTALL_PREFIX='+$prefix)) $Stage
Run 'cpp-build' $cmake @('--build',$cppBuild,'-j','2') $Stage
Run 'cpp-install' $cmake @('--install',$cppBuild) $Stage
Run 'source-build' (Join-Path $lean 'lake.exe') @('build') $Source
# Python helpers and the test driver use extensionless executable paths. These
# task-local aliases retain the exact PE bytes and do not change tracked source.
foreach($file in @(Get-ChildItem -LiteralPath (Join-Path $Source '.lake/build/bin') -Filter '*.exe' -File)) {
  $alias=Join-Path $file.DirectoryName $file.BaseName
  if(Test-Path -LiteralPath $alias){throw 'executable alias exists'}
  Copy-Item -LiteralPath $file.FullName -Destination $alias
}
Run 'full-lake-test' (Join-Path $lean 'lake.exe') @('test') $Source
