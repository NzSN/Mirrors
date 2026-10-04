param(
  [Parameter(Mandatory=$true)][string]$SourceRoot,
  [Parameter(Mandatory=$true)][string]$JsonInclude,
  [Parameter(Mandatory=$true)][string]$OutputRoot,
  [ValidateSet('','duplicate-sink-call','skip-hit-release')][string]$SourceMutation=''
)
$ErrorActionPreference='Stop'
$dpmAllowed='C:\Users\ayden\Desktop\Workspace\MirrorsRemote\'
$dpmOut=[IO.Path]::GetFullPath($OutputRoot)
if(-not $dpmOut.StartsWith($dpmAllowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Output must be a new owned MirrorsRemote child'}
if(Test-Path -LiteralPath $dpmOut){throw 'Never overwrite native evidence or builds'}
$dpmAncestor=Split-Path $dpmOut
while($dpmAncestor -and (Test-Path -LiteralPath $dpmAncestor)){
  if((Get-Item -LiteralPath $dpmAncestor).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Output ancestry must not contain reparse points'}
  $dpmAncestor=Split-Path $dpmAncestor
}
$dpmInput=Get-Content -Raw -LiteralPath (Join-Path $SourceRoot 'source-manifest.json')|ConvertFrom-Json
if($dpmInput.schema -ne 'mirrors.dpm3-native-inputs/v1'){throw 'Wrong native input manifest'}
$dpmStage=Join-Path $dpmOut 'source';$dpmBuild=Join-Path $dpmOut 'build';$dpmTemp=Join-Path $dpmOut 'temp'
New-Item -ItemType Directory -Force $dpmStage,$dpmBuild,$dpmTemp|Out-Null
foreach($property in $dpmInput.sourceHashes.PSObject.Properties){
  $relative=$property.Name
  if($relative -match '(^[\\/]|\.\.|:)'){throw 'Unsafe source path'}
  $from=Join-Path (Join-Path $SourceRoot 'source') $relative
  $to=Join-Path $dpmStage $relative
  if((Get-FileHash -LiteralPath $from).Hash.ToLowerInvariant() -ne $property.Value){throw 'Frozen source changed'}
  New-Item -ItemType Directory -Force (Split-Path $to)|Out-Null
  Copy-Item -LiteralPath $from -Destination $to
  if((Get-FileHash -LiteralPath $to).Hash.ToLowerInvariant() -ne $property.Value){throw 'Staged source hash differs'}
}
$dpmWrapper=Join-Path (Join-Path $SourceRoot 'source') 'tests/mbt/dpm_worker.cpp'
if((Get-FileHash -LiteralPath $dpmWrapper).Hash.ToLowerInvariant() -ne $dpmInput.wrapperSha256){throw 'Native wrapper changed'}
Copy-Item -LiteralPath $dpmWrapper -Destination (Join-Path $dpmStage 'tests/mbt/dpm_worker.cpp')
if($SourceMutation){
  $path=Join-Path $dpmStage 'src/veh.cpp';$text=[IO.File]::ReadAllText($path)
  if($SourceMutation -eq 'duplicate-sink-call'){$old='        sink(hit);';$new='        sink(hit); sink(hit);'}
  else{$old="    live.in_flight.fetch_sub(1, std::memory_order_seq_cst);`n    ctx->Dr6 &= ~(1ull << slot);";$new='    ctx->Dr6 &= ~(1ull << slot);'}
  if(([regex]::Matches($text,[regex]::Escape($old))).Count -ne 1){throw 'Mutation site must match exactly once'}
  [IO.File]::WriteAllText($path,$text.Replace($old,$new),[Text.UTF8Encoding]::new($false))
}
$dpmJson=Join-Path $dpmStage 'jsoninclude';New-Item -ItemType Directory -Force $dpmJson|Out-Null
Copy-Item -LiteralPath (Join-Path $JsonInclude 'nlohmann') -Destination $dpmJson -Recurse
$dpmBatch=Join-Path $dpmBuild 'build.cmd'
$dpmFlags='/nologo /std:c++20 /O2 /W4 /EHsc /MD /DWIN32_LEAN_AND_MEAN /DNOMINMAX /DWRITESENTRY_MBT_PHASES '+
  '/I "'+$dpmStage+'\include" /I "'+$dpmStage+'\src" /I "'+$dpmStage+'\tests\mbt" /I "'+$dpmJson+'" '
$dpmLines=@('@echo off','call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat" >nul',
  'if errorlevel 1 exit /b 1',('set TEMP='+$dpmTemp),('set TMP='+$dpmTemp),('cd /d "'+$dpmBuild+'"'),
  ('ml64.exe /nologo /c /Fo writers.obj "'+$dpmStage+'\tests\mbt\runtime_writers.asm"'),'if errorlevel 1 exit /b 1',
  ('cl.exe '+$dpmFlags+'"'+$dpmStage+'\tests\mbt\dpm_worker.cpp" "'+$dpmStage+'\src\self_watch.cpp" "'+$dpmStage+'\src\veh.cpp" writers.obj bcrypt.lib /Fe:dpm_native_worker.exe'),
  'exit /b %errorlevel%')
[IO.File]::WriteAllLines($dpmBatch,$dpmLines,[Text.ASCIIEncoding]::new())
Set-Location -LiteralPath $dpmBuild
& $env:ComSpec /d /c $dpmBatch 2>&1|Tee-Object -FilePath (Join-Path $dpmOut 'build.log')
if($LASTEXITCODE -ne 0){throw 'Native DPM worker build failed'}
$dpmExe=Join-Path $dpmBuild 'dpm_native_worker.exe'
$dpmReceipt=[ordered]@{schema='mirrors.dpm3-native-build/v1';observedAt=[DateTime]::UtcNow.ToString('o');
  sourceBaseRevision=$dpmInput.sourceBaseRevision;sourceHashes=$dpmInput.sourceHashes;wrapperSha256=$dpmInput.wrapperSha256;
  sourceMutation=$SourceMutation;stagedVehSha256=(Get-FileHash (Join-Path $dpmStage 'src/veh.cpp')).Hash.ToLowerInvariant();
  executableSha256=(Get-FileHash $dpmExe).Hash.ToLowerInvariant();executable=$dpmExe;compilerFlags=$dpmFlags;
  phaseHooks=$true;profile='dpm-writesentry-two-operation/v1'}
[IO.File]::WriteAllText((Join-Path $dpmOut 'build-receipt.json'),($dpmReceipt|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
$dpmReceipt|ConvertTo-Json -Depth 8 -Compress
