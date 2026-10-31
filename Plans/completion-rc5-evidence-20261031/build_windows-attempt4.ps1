param([Parameter(Mandatory=$true)][string]$InputRoot,
      [Parameter(Mandatory=$true)][string]$RecordRoot)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false)
$utf8=New-Object System.Text.UTF8Encoding($false)
$stage='D:\mr5-1031c'
$leanbin='C:\Users\ayden\.elan\toolchains\leanprover--lean4---v4.33.0\bin'
$nativebin='D:\Programs\msys2\ucrt64\bin'
$gitbin='D:\Programs\Git\cmd'
function Sha([string]$p){ (Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToLower() }
function WriteJson([string]$p,$value){[IO.File]::WriteAllText($p,($value | ConvertTo-Json -Depth 15),$utf8)}
if(Test-Path -LiteralPath $stage){throw "Refusing to overwrite stage $stage"}
foreach($p in @("$leanbin\lake.exe","$nativebin\gcc.exe","$nativebin\openssl.exe")){
  if(-not(Test-Path -LiteralPath $p)){throw "Required tool missing: $p"}
}
New-Item -ItemType Directory -Path $stage | Out-Null
$source=Join-Path $stage 'source'
$logs=Join-Path $stage 'logs'
$tmp=Join-Path $stage 'tmp'
New-Item -ItemType Directory -Path $logs,$tmp | Out-Null
$env:PATH="$leanbin;$nativebin;$gitbin;"+$env:PATH
$env:CC=($nativebin.Replace('\','/')+'/gcc.exe')
$env:OSSL_INC='D:/Programs/msys2/ucrt64/include'
$env:OSSL_LIB='D:/Programs/msys2/ucrt64/lib'
$env:TEMP=$tmp
$env:TMP=$tmp
$env:TMPDIR=$tmp
foreach($name in @('APALACHE_MC','APALACHE_JAR','TLA2TOOLS_JAR')){
  Remove-Item -LiteralPath ("Env:"+$name) -ErrorAction SilentlyContinue
}
$manifest=Get-Content -Raw -LiteralPath (Join-Path $RecordRoot 'windows-source-manifest.json') | ConvertFrom-Json
$result=[ordered]@{schema='mirrors.completion-windows-build/v1';host=$env:COMPUTERNAME;
  os=[Environment]::OSVersion.VersionString;stage=$stage;source=$source;tag=$manifest.tag;
  commit=$manifest.commit;tree=$manifest.tree;startedAt=(Get-Date).ToUniversalTime().ToString('o');
  tools=[ordered]@{};archives=[ordered]@{};gates=@();files=[ordered]@{};state='executing';
  published=$false;deployed=$false;modelCheckerStarted=$false}
try {
  foreach($entry in $manifest.archives.PSObject.Properties){
    $path=Join-Path $InputRoot $entry.Name
    if((Sha $path) -ne $entry.Value.sha256 -or (Get-Item $path).Length -ne $entry.Value.bytes){throw "Archive mismatch: $path"}
    $result.archives[$entry.Name]=$entry.Value
  }
  & tar.exe -xzf (Join-Path $InputRoot 'mirrors-v0.2.0-rc.5-source.tar.gz') -C $stage
  if($LASTEXITCODE -ne 0){throw 'Source extraction failed'}
  foreach($entry in $manifest.files){
    $path=Join-Path $source $entry.path
    if((Sha $path) -ne $entry.sha256 -or (Get-Item $path).Length -ne $entry.bytes){throw "Source mismatch: $($entry.path)"}
  }
  $result.sourceFilesVerified=@($manifest.files).Count
  $packages=Join-Path $source '.lake\packages'
  New-Item -ItemType Directory -Path $packages | Out-Null
  & "$gitbin\git.exe" -c core.symlinks=false clone (Join-Path $InputRoot 'batteries-4488d40d-release.bundle') (Join-Path $packages 'batteries')
  if($LASTEXITCODE -ne 0){throw 'Batteries clone failed'}
  & "$gitbin\git.exe" -C (Join-Path $packages 'batteries') remote set-url origin 'https://github.com/leanprover-community/batteries'
  if($LASTEXITCODE -ne 0){throw 'Batteries remote identity setup failed'}
  $dependencyRef=(& "$gitbin\git.exe" -C (Join-Path $packages 'batteries') rev-parse HEAD | Out-String).Trim()
  if($dependencyRef -ne '4488d40d070b9700d4d5a6aa342f0d40c31b2a2d'){throw 'Batteries revision mismatch'}
  $result.batteriesRevision=$dependencyRef
  foreach($tool in @(@('lean',"$leanbin\lean.exe"),@('lake',"$leanbin\lake.exe"),@('gcc',"$nativebin\gcc.exe"),@('openssl',"$nativebin\openssl.exe"))){
    $arg=if($tool[0] -eq 'openssl'){'version'}else{'--version'}
    $value=(& $tool[1] $arg | Out-String).Trim()
    if($LASTEXITCODE -ne 0){throw "Tool observation failed: $($tool[0])"}
    $result.tools[$tool[0]]=[ordered]@{path=$tool[1];sha256=(Sha $tool[1]);version=$value}
  }
  function RunLogged([string]$name,[string]$line){
    $log=Join-Path $logs ($name+'.log')
    $started=(Get-Date).ToUniversalTime().ToString('o')
    Push-Location -LiteralPath $source
    try { & cmd.exe /d /s /c ($line+' > "'+$log+'" 2>&1'); $code=$LASTEXITCODE }
    finally { Pop-Location }
    $receipt=[ordered]@{name=$name;command=$line;exitCode=$code;startedAt=$started;
      finishedAt=(Get-Date).ToUniversalTime().ToString('o');log=('logs/'+$name+'.log');
      logBytes=(Get-Item $log).Length;logSha256=(Sha $log)}
    Write-Output "$name exit=$code"
    return $receipt
  }
  $targets=@('mirror','model_interface_gen','fixtures_replay','diff_cross','model_interface_spec',
             'stdio_smoke','transport_spec','jobstore_spec','async_resource_spec','dpm_sync_spec')
  $build=@(RunLogged 'build' ('"'+$leanbin+'\lake.exe" build '+($targets -join ' ')))
  $result.build=$build[-1]
  if($result.build.exitCode -ne 0){throw 'Windows lake build failed'}
  foreach($gate in $targets[2..9]){
    $run=@(RunLogged $gate ('"'+(Join-Path $source ('.lake\build\bin\'+$gate+'.exe'))+'"'))
    $result.gates += $run[-1]
    if($run[-1].exitCode -ne 0){throw "Windows gate failed: $gate"}
  }
  foreach($entry in $manifest.files){
    if((Sha (Join-Path $source $entry.path)) -ne $entry.sha256){throw "Post-build source drift: $($entry.path)"}
  }
  $result.postBuildSourceStable=$true
  $output=Join-Path $RecordRoot 'windows-binaries'
  # Bulky binaries are retained in the ignored work root, never in public evidence.
  $output=Join-Path $InputRoot '..\windows-binaries'
  New-Item -ItemType Directory -Path $output | Out-Null
  foreach($pair in @(@((Join-Path $source '.lake\build\bin\mirror.exe'),'ModelMirrors.exe'),
                     @((Join-Path $source '.lake\build\bin\model_interface_gen.exe'),'model_interface_gen.exe'),
                     @("$nativebin\libssl-3-x64.dll",'libssl-3-x64.dll'),
                     @("$nativebin\libcrypto-3-x64.dll",'libcrypto-3-x64.dll'),
                     @("$nativebin\zlib1.dll",'zlib1.dll'))){
    Copy-Item -LiteralPath $pair[0] -Destination (Join-Path $output $pair[1])
    $result.files[$pair[1]]=[ordered]@{source=$pair[0];sha256=(Sha $pair[0]);bytes=(Get-Item $pair[0]).Length}
  }
  $version=(& (Join-Path $output 'ModelMirrors.exe') --version | Out-String).Trim()
  if($LASTEXITCODE -ne 0 -or $version -ne 'v0.2.0-rc.5'){throw "Wrong packaged version: $version"}
  $result.versionOutput=$version
  $result.state='passed'
} catch {
  $result.state='failed'
  $result.error=$_.Exception.Message
  Write-Output $_.Exception.Message
} finally {
  $result.finishedAt=(Get-Date).ToUniversalTime().ToString('o')
  WriteJson (Join-Path $RecordRoot 'windows-native.json') $result
  $destination=Join-Path $RecordRoot 'windows-logs-attempt4'
  New-Item -ItemType Directory -Force -Path $destination | Out-Null
  Get-ChildItem -LiteralPath $logs -File | Copy-Item -Destination $destination
  Write-Output ("WINDOWS STATE "+$result.state+" stage="+$stage)
}
if($result.state -ne 'passed'){exit 1}
