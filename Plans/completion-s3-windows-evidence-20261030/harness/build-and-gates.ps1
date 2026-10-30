param([string]$Stage='D:/ModelMirrors/staging/s3-windows-20261030-d737aa0')
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false)
$source=Join-Path $Stage 'mirrors-d737aa0'
$logs=Join-Path $Stage 'logs'
New-Item -ItemType Directory -Force -Path $logs | Out-Null
$leanbin='C:\Users\win10\.elan\toolchains\leanprover--lean4---v4.33.0\bin'
$tmp='D:\ModelMirrors\tmp\s3-windows-20261030'
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$env:CC='D:/Programs/Perl/c/bin/gcc.exe'
$env:OSSL_INC='D:/Programs/msys2/ucrt64/include'
$env:OSSL_LIB='D:/Programs/msys2/ucrt64/lib'
$env:TEMP=$tmp
$env:TMP=$tmp
$env:TMPDIR=$tmp
$env:PATH="$leanbin;D:\Programs\Perl\c\bin;"+$env:PATH
foreach($name in @('APALACHE_MC','APALACHE_JAR','TLA2TOOLS_JAR')){Remove-Item -LiteralPath ("Env:"+$name) -ErrorAction SilentlyContinue}
function Sha([string]$p){ if(Test-Path -LiteralPath $p){ (Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToLower() } else { $null } }
function ToolRecord([string]$label,[string]$exe,[string[]]$toolArgs){
  if(-not (Test-Path -LiteralPath $exe)){ return [ordered]@{label=$label;path=$exe;present=$false} }
  $ErrorActionPreference='Continue'
  $out=(& $exe @toolArgs 2>&1 | Out-String).Trim()
  $ErrorActionPreference='Stop'
  $first=($out -split "`r?`n")[0]
  [ordered]@{label=$label;path=$exe;present=$true;version=$first;outputSha256=([System.BitConverter]::ToString(([System.Security.Cryptography.SHA256]::Create()).ComputeHash((New-Object System.Text.UTF8Encoding($false)).GetBytes($out)))).Replace('-','').ToLower();sha256=(Sha $exe)}
}
$prodFiles=[ordered]@{}
foreach($p in @('D:\ModelMirrors\bin\ModelMirrors.exe','D:\ModelMirrors\bin\libcrypto-3-x64.dll','D:\ModelMirrors\bin\libssl-3-x64.dll','D:\ModelMirrors\bin\zlib1.dll','D:\ModelMirrors\certs\server.crt','D:\ModelMirrors\certs\ca.crt','D:\ModelMirrors\certs\server.key')){
  $exists=Test-Path -LiteralPath $p
  $bytes=$null
  $lastWrite=$null
  if($exists){ $item=Get-Item -LiteralPath $p; $bytes=$item.Length; $lastWrite=$item.LastWriteTimeUtc.ToString('yyyy-MM-ddTHH:mm:ssZ') }
  $prodFiles[$p]=[ordered]@{sha256=(Sha $p);bytes=$bytes;lastWriteUtc=$lastWrite;hashOnly=($p -like '*.key')}
}
$service=Get-CimInstance Win32_Service -Filter "Name='ModelMirrors'" -ErrorAction SilentlyContinue
$envRecord=[ordered]@{
 schema='mirrors.s3.windows-build-environment/v1'
 host=$env:COMPUTERNAME
 os=[Environment]::OSVersion.VersionString
 powershell=$PSVersionTable.PSVersion.ToString()
 stagingDirectory=$Stage
 sourceDirectory=$source
 capturedAtUtc=(Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
 tools=@(
   (ToolRecord 'lake' "$leanbin\lake.exe" @('--version')),
   (ToolRecord 'lean' "$leanbin\lean.exe" @('--version')),
   (ToolRecord 'gcc' 'D:\Programs\Perl\c\bin\gcc.exe' @('--version')),
   (ToolRecord 'python' 'D:\Programs\Python310\python.exe' @('--version')),
   (ToolRecord 'git' 'C:\Program Files\Git\cmd\git.exe' @('--version'))
 )
 openssl=[ordered]@{version=((& 'D:\Programs\msys2\ucrt64\bin\openssl.exe' version 2>&1 | Out-String).Trim());includeDir=$env:OSSL_INC;libraryDir=$env:OSSL_LIB;libcrypto=(Sha 'D:\Programs\msys2\ucrt64\bin\libcrypto-3-x64.dll');libssl=(Sha 'D:\Programs\msys2\ucrt64\bin\libssl-3-x64.dll');zlib1=(Sha 'D:\Programs\msys2\ucrt64\bin\zlib1.dll')}
 environment=[ordered]@{CC=$env:CC;OSSL_INC=$env:OSSL_INC;OSSL_LIB=$env:OSSL_LIB;TEMP=$env:TEMP;APALACHE_MC='unset';APALACHE_JAR='unset';TLA2TOOLS_JAR='unset'}
 productionBefore=[ordered]@{serviceStatus=($(if($service){$service.State}else{$null}));processes=@(Get-CimInstance Win32_Process -Filter "Name='ModelMirrors.exe'" | ForEach-Object { [ordered]@{pid=$_.ProcessId;path=$_.ExecutablePath;created=$_.CreationDate;commandLine=$_.CommandLine} });files=$prodFiles}
}
$envRecord | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $Stage 'build-environment.json') -Encoding UTF8
Write-Output "ENV CAPTURED"
$targets=@('mirror','model_interface_gen','fixtures_replay','diff_cross','model_interface_spec','stdio_smoke','transport_spec','jobstore_spec','async_resource_spec','dpm_sync_spec')
$buildlog=Join-Path $logs 'build.log'
$started=(Get-Date)
$cmdLine='"'+$leanbin+'\lake.exe" build '+($targets -join ' ')+' > "'+$buildlog+'" 2>&1'
Push-Location -LiteralPath $source
try { & cmd.exe /d /s /c $cmdLine; $buildExit=$LASTEXITCODE } finally { Pop-Location }
$finished=(Get-Date)
$buildLogBytes=if(Test-Path -LiteralPath $buildlog){(Get-Item -LiteralPath $buildlog).Length}else{$null}
$buildRecord=[ordered]@{schema='mirrors.s3.windows-build/v1';command=("lake build "+($targets -join ' '));cwd=$source;exit=$buildExit;startedUtc=$started.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ');finishedUtc=$finished.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ');seconds=[math]::Round(($finished-$started).TotalSeconds,1);log='logs/build.log';logBytes=$buildLogBytes;logSha256=(Sha $buildlog);binaries=[ordered]@{}}
foreach($b in @('mirror','model_interface_gen')){ $p=Join-Path $source (".lake/build/bin/"+$b+".exe"); $bbytes=$null; if(Test-Path -LiteralPath $p){$bbytes=(Get-Item -LiteralPath $p).Length}; $buildRecord.binaries[$b]=[ordered]@{path=$p;sha256=(Sha $p);bytes=$bbytes} }
$buildRecord | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $Stage 'build.json') -Encoding UTF8
Write-Output ("BUILD EXIT " + $buildExit)
if($buildExit -ne 0){ Get-Content -LiteralPath $buildlog -Tail 40; exit $buildExit }
$gateRecords=@()
foreach($gate in @('fixtures_replay','diff_cross','model_interface_spec','stdio_smoke','transport_spec','jobstore_spec','async_resource_spec','dpm_sync_spec')){
  $exe=Join-Path $source (".lake/build/bin/"+$gate+".exe")
  $log=Join-Path $logs ($gate+'.log')
  $s=(Get-Date)
  $line='"'+$exe+'" > "'+$log+'" 2>&1'
  Push-Location -LiteralPath $source
  try { & cmd.exe /d /s /c $line; $code=$LASTEXITCODE } finally { Pop-Location }
  $f=(Get-Date)
  $logBytes=$null; if(Test-Path -LiteralPath $log){$logBytes=(Get-Item -LiteralPath $log).Length}
  $gateRecords += [ordered]@{gate=$gate;command=(".lake/build/bin/"+$gate+".exe");cwd=$source;exit=$code;startedUtc=$s.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ');finishedUtc=$f.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ');seconds=[math]::Round(($f-$s).TotalSeconds,1);log=('logs/'+$gate+'.log');logBytes=$logBytes;logSha256=(Sha $log)}
  Write-Output ("GATE " + $gate + " EXIT " + $code)
}
$gateRecords | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $Stage 'gates.json') -Encoding UTF8
$failed=@($gateRecords | Where-Object { $_.exit -ne 0 }).Count
Write-Output ("GATES_FAILED " + $failed)
exit $(if($failed -gt 0){1}else{0})
