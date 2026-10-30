$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false)
$stage=$PSScriptRoot
$source=Join-Path $stage 'source'
$manifest=Get-Content -Raw -LiteralPath (Join-Path $stage 'current-source-overlay.json')|ConvertFrom-Json
foreach($entry in $manifest.files){
  $path=Join-Path $source $entry.path
  if((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLower() -ne $entry.after){throw "source drift: $($entry.path)"}
}
$package=Join-Path $stage 'candidate-v0.2.0-rc.1'
if(Test-Path -LiteralPath $package){throw 'candidate package already exists'}
$bin=Join-Path $package 'bin'
New-Item -ItemType Directory -Path $bin|Out-Null
Copy-Item -LiteralPath (Join-Path $source '.lake\build\bin\mirror.exe') -Destination (Join-Path $bin 'ModelMirrors.exe')
Copy-Item -LiteralPath (Join-Path $source '.lake\build\bin\model_interface_gen.exe') -Destination (Join-Path $bin 'model_interface_gen.exe')
foreach($dll in (Get-ChildItem -LiteralPath (Join-Path $stage 'package') -Filter '*.dll')){Copy-Item -LiteralPath $dll.FullName -Destination (Join-Path $bin $dll.Name)}
$version=& (Join-Path $bin 'ModelMirrors.exe') --version
if($LASTEXITCODE -ne 0 -or $version -ne 'v0.2.0-rc.1'){throw 'packaged version failed'}
$files=[ordered]@{}
foreach($file in (Get-ChildItem -LiteralPath $bin -File|Sort-Object Name)){$files['bin/'+$file.Name]=(Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash.ToLower()}
$production=Get-Process -Id 9920
if($production.Path -ne 'D:\ModelMirrors\bin\ModelMirrors.exe'){throw 'production identity changed'}
$productionSha=(Get-FileHash -Algorithm SHA256 -LiteralPath $production.Path).Hash.ToLower()
if($productionSha -ne '8173ddea65f78a88b1a303f8a233dd7113b28e7dc8aefd8916a5add25a3687cc'){throw 'production binary changed'}
$record=[ordered]@{
 schema='mirrors.windows-candidate-package/v1';version='0.2.0-rc.1';published=$false;deployed=$false
 sourceBase=$manifest.base;sourceOverlaySha256=(Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $stage 'current-source-overlay.json')).Hash.ToLower()
 sourceOverlayVerifiedAfterGates=$true;files=$files
 gates=@('fixtures_replay','diff_cross','model_interface_spec','stdio_smoke','transport_spec','jobstore_spec','async_resource_spec','dpm_sync_spec')
 scope='native build and eight selected non-model runtime suites; no full lake test, M5 matrix, production service lifecycle or reboot qualification'
 production=[ordered]@{pid=$production.Id;sha256=$productionSha;modified=$false}
}
[IO.File]::WriteAllText((Join-Path $package 'BUILD.json'),($record|ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllText((Join-Path $package 'README.txt'),"Mirrors v0.2.0-rc.1 native Windows candidate. Not published or deployed.`nSee BUILD.json for exact artifact and qualification scope. DPM installed acceptance is Linux-only in this campaign.`n",(New-Object Text.UTF8Encoding($false)))
& 'D:\Programs\Python310\python.exe' -I -S -B (Join-Path $stage 'zip-windows-candidate.py')
if($LASTEXITCODE -ne 0){throw 'deterministic candidate ZIP failed'}
$record|ConvertTo-Json -Depth 8
