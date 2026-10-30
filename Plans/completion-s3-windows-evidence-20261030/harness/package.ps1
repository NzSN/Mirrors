$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false)
$Stage='D:/ModelMirrors/staging/s3-windows-20261030-d737aa0'
$source=Join-Path $Stage 'mirrors-d737aa0'
$package=Join-Path $Stage 'candidate-v0.2.0-rc.1'
if(Test-Path -LiteralPath $package){throw 'candidate package already exists'}
$bin=Join-Path $package 'bin'
New-Item -ItemType Directory -Path $bin | Out-Null
Copy-Item -LiteralPath (Join-Path $source '.lake\build\bin\mirror.exe') -Destination (Join-Path $bin 'ModelMirrors.exe')
Copy-Item -LiteralPath (Join-Path $source '.lake\build\bin\model_interface_gen.exe') -Destination (Join-Path $bin 'model_interface_gen.exe')
$dllSources=[ordered]@{
 'libcrypto-3-x64.dll'=[ordered]@{path='D:\Programs\msys2\ucrt64\bin\libcrypto-3-x64.dll';sha256='7909ab97fd1226890af8448a43cb9acd0e9758bfd595298c46c125211c3e61c7'}
 'libssl-3-x64.dll'=[ordered]@{path='D:\Programs\msys2\ucrt64\bin\libssl-3-x64.dll';sha256='85377317f9fbc5a0b8264ba25c87670dbce2fe0988d186eb98d107460d8b416c'}
 'zlib1.dll'=[ordered]@{path='D:\ModelMirrors\releases\20261029-completion-7e9a27d\candidate-v0.2.0-rc.1\bin\zlib1.dll';sha256='93e9243a44c29200eeacaf9658efe2558581770e4b11ca4b500e18e424a6e3b5'}
}
function Sha([string]$p){ (Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToLower() }
foreach($name in $dllSources.Keys){ $d=$dllSources[$name]; if((Sha $d.path) -ne $d.sha256){throw "DLL source hash differs: $($d.path)"}; Copy-Item -LiteralPath $d.path -Destination (Join-Path $bin $name) }
$version=(& (Join-Path $bin 'ModelMirrors.exe') --version | Out-String).Trim()
if($LASTEXITCODE -ne 0 -or $version -ne 'v0.2.0-rc.1'){throw "packaged version failed: $version exit $LASTEXITCODE"}
$files=[ordered]@{}
foreach($file in (Get-ChildItem -LiteralPath $bin -File | Sort-Object Name)){ $files['bin/'+$file.Name]=[ordered]@{sha256=(Sha $file.FullName);bytes=$file.Length} }
$sourceManifest=ConvertFrom-Json (Get-Content -Raw -LiteralPath (Join-Path $Stage 'mirrors-v0.2.0-rc.1-source-manifest.json'))
$gateDoc=Get-Content -Raw -LiteralPath (Join-Path $Stage 'gates.json') | ConvertFrom-Json
$gates=@($gateDoc.gates)
$gateRows=@()
foreach($g in $gates){ $gateRows += [ordered]@{gate=$g.gate;exit=$g.exit;logSha256=$g.logSha256} }
$transportAttempt=Get-Content -Raw -LiteralPath (Join-Path $Stage 'transport-retry.json') | ConvertFrom-Json
$firstPass=@(Get-ChildItem -LiteralPath (Join-Path $Stage 'logs/first-pass') -File | ForEach-Object { [ordered]@{log=('logs/first-pass/'+$_.Name);bytes=$_.Length;sha256=(Sha $_.FullName)} })
$tools=ConvertFrom-Json (Get-Content -Raw -LiteralPath (Join-Path $Stage 'build-environment.json'))
$prodExe='D:\ModelMirrors\bin\ModelMirrors.exe'
$prodSha=Sha $prodExe
$prod=Get-CimInstance Win32_Process -Filter "Name='ModelMirrors.exe'"
$record=[ordered]@{
 schema='mirrors.s3.windows-package/v1'
 version='0.2.0-rc.1'
 tag='v0.2.0-rc.1'
 tagObject=$sourceManifest.tagObject
 sourceCommit=$sourceManifest.commit
 sourceTree=$sourceManifest.tree
 sourceArchive=$sourceManifest.archive
 sourceArchiveSha256=$sourceManifest.archiveSha256
 sourceArchiveBytes=$sourceManifest.archiveBytes
 sourceContentTreeDigest=$sourceManifest.contentTreeDigest
 sourceFileCount=$sourceManifest.fileCount
 sourceOverlay=$false
 dllSources=$dllSources
 published=$false
 deployed=$false
 files=$files
 gates=$gateRows
 gateEnvironment=$gateDoc.environment
 firstPassLogs=$firstPass
 transportInitialFailure=$transportAttempt.initialAttempt
 toolchain=[ordered]@{lean=$tools.tools[1].version;lake=$tools.tools[0].version;gcc=$tools.tools[2].version;openssl=$tools.openssl.version;opensslInclude=$tools.openssl.includeDir;opensslLibrary=$tools.openssl.libraryDir;python=$tools.tools[3].version}
 scope='native Windows build from the exact local v0.2.0-rc.1 tag and eight selected non-model runtime suites; no full lake test, M5 matrix, production service lifecycle, reboot, reproducible-compilation or release admission claim'
 production=[ordered]@{pid=$prod.ProcessId;path=$prodExecutablePath;sha256=$prodSha;modified=($prodSha -ne '8173ddea65f78a88b1a303f8a233dd7113b28e7dc8aefd8916a5add25a3687cc')}
}
$record.production.path=$prod.ExecutablePath
[IO.File]::WriteAllText((Join-Path $package 'BUILD.json'),($record|ConvertTo-Json -Depth 10),(New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllText((Join-Path $package 'README.txt'),"Mirrors v0.2.0-rc.1 native Windows package built from local tag v0.2.0-rc.1 ($($sourceManifest.commit)).`nNot published or deployed. See BUILD.json for exact artifact, toolchain and qualification scope.`n",(New-Object Text.UTF8Encoding($false)))
& 'D:\Programs\Python310\python.exe' -I -S -B (Join-Path $Stage 'zip-windows.py') $Stage
if($LASTEXITCODE -ne 0){throw 'deterministic package ZIP failed'}
$archive=ConvertFrom-Json (Get-Content -Raw -LiteralPath (Join-Path $Stage 'windows-package-archive.json'))
[ordered]@{schema='mirrors.s3.windows-package-receipt/v1';package=$package;versionOutput=$version;archive=$archive;externalBuildJson=[ordered]@{name='mirrors-v0.2.0-rc.1-windows-x86_64.build.json';sha256=(Sha (Join-Path $package 'BUILD.json'));bytes=(Get-Item (Join-Path $package 'BUILD.json')).Length};packageFiles=$files} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $Stage 'windows-package-receipt.json') -Encoding UTF8
Copy-Item -LiteralPath (Join-Path $package 'BUILD.json') -Destination (Join-Path $Stage 'mirrors-v0.2.0-rc.1-windows-x86_64.build.json')
Write-Output "PACKAGED $version"
