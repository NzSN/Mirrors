$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$Stage = 'D:\ModelMirrors\staging\s3-rc6-20261103-3c4a873'
$source = Join-Path $Stage 'mirrors-v0.2.0-rc.6'
$package = Join-Path $Stage 'mirrors-v0.2.0-rc.6-windows-x86_64'
if (Test-Path -LiteralPath $package) { throw 'candidate package already exists' }
$bin = Join-Path $package 'bin'
New-Item -ItemType Directory -Path $bin | Out-Null
Copy-Item -LiteralPath (Join-Path $source '.lake\build\bin\mirror.exe') -Destination (Join-Path $bin 'ModelMirrors.exe')
Copy-Item -LiteralPath (Join-Path $source '.lake\build\bin\model_interface_gen.exe') -Destination (Join-Path $bin 'model_interface_gen.exe')
$dllSources = [ordered]@{
    'libcrypto-3-x64.dll' = [ordered]@{path = 'D:\Programs\msys2\ucrt64\bin\libcrypto-3-x64.dll'; sha256 = '7909ab97fd1226890af8448a43cb9acd0e9758bfd595298c46c125211c3e61c7'}
    'libssl-3-x64.dll' = [ordered]@{path = 'D:\Programs\msys2\ucrt64\bin\libssl-3-x64.dll'; sha256 = '85377317f9fbc5a0b8264ba25c87670dbce2fe0988d186eb98d107460d8b416c'}
    'zlib1.dll' = [ordered]@{path = 'D:\ModelMirrors\releases\20261029-completion-7e9a27d\candidate-v0.2.0-rc.1\bin\zlib1.dll'; sha256 = '93e9243a44c29200eeacaf9658efe2558581770e4b11ca4b500e18e424a6e3b5'}
}
function Sha([string]$p) { (Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToLower() }
foreach ($name in $dllSources.Keys) {
    $d = $dllSources[$name]
    if (-not (Test-Path -LiteralPath $d.path)) { throw "DLL source missing: $($d.path)" }
    $actual = Sha $d.path
    if ($actual -ne $d.sha256) { throw "DLL source hash differs: $($d.path) $actual" }
    Copy-Item -LiteralPath $d.path -Destination (Join-Path $bin $name)
}
$version = (& (Join-Path $bin 'ModelMirrors.exe') --version | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $version -ne 'v0.2.0-rc.6') { throw "packaged version failed: $version exit $LASTEXITCODE" }
$files = [ordered]@{}
foreach ($file in (Get-ChildItem -LiteralPath $bin -File | Sort-Object Name)) {
    $files['bin/' + $file.Name] = [ordered]@{sha256 = (Sha $file.FullName); bytes = $file.Length}
}
$gateDoc = Get-Content -Raw -LiteralPath (Join-Path $Stage 'windows-gates.json') | ConvertFrom-Json
$gates = @($gateDoc.gates)
$gateRows = @()
foreach ($g in $gates) { $gateRows += [ordered]@{gate = $g.gate; exit = $g.exit; logSha256 = $g.logSha256} }
$tools = ConvertFrom-Json (Get-Content -Raw -LiteralPath (Join-Path $Stage 'windows-build-environment.json'))
$record = [ordered]@{
    schema = 'mirrors.s3-rc6.windows-package/v1'
    published = $false
    deployed = $false
    version = '0.2.0-rc.6'
    embeddedVersion = '0.2.0-rc.6'
    tag = 'v0.2.0-rc.6'
    tagObject = '5a2a6fd8728b610db7a6225b4a9d4c5d585344aa'
    sourceCommit = '3c4a87309cc3a81924660497207d7c295759bdc1'
    sourceTree = '5c15228e006f4d1b6efaa7e088488bc4b1fe619e'
    sourceArchive = 'mirrors-v0.2.0-rc.6-source.tar.gz'
    sourceArchiveSha256 = '87ab9dee6c1a247da0ef4f1a7028c941323997202721ccada2e6ef6c62371a62'
    sourceFileCount = 9833
    sourceOverlay = $false
    fullLakeTest = $false
    reproducibleCompilation = $false
    releaseAdmission = $false
    dllSources = $dllSources
    files = $files
    gates = $gateRows
    gateEnvironment = $gateDoc.environment
    toolchain = [ordered]@{
        lean = $tools.tools[1].version
        lake = $tools.tools[0].version
        gcc = $tools.tools[2].version
        openssl = $tools.tools[5].version
        opensslInclude = $tools.openssl.includeDir
        opensslLibrary = $tools.openssl.libraryDir
        python = $tools.tools[3].version
    }
    scope = 'native Windows build from the exact local v0.2.0-rc.6 source archive and eight selected non-model runtime suites; not full lake test, not reproducible compilation, not release admission'
}
[IO.File]::WriteAllText((Join-Path $package 'BUILD.json'), ($record | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllText((Join-Path $package 'README.txt'), "Mirrors v0.2.0-rc.6 native Windows package built from local tag v0.2.0-rc.6 (3c4a87309cc3a81924660497207d7c295759bdc1).`nNot published or deployed. Not full lake test, not reproducible compilation, and not release admission. See BUILD.json.`n", (New-Object Text.UTF8Encoding($false)))
& 'D:\Programs\Python310\python.exe' -I -S -B (Join-Path $Stage 'windows-zip.py')
if ($LASTEXITCODE -ne 0) { throw 'deterministic package ZIP failed' }
& 'D:\Programs\Python310\python.exe' -I -S -B (Join-Path $Stage 'windows-pe.py')
if ($LASTEXITCODE -ne 0) { throw 'PE import closure failed' }
Copy-Item -LiteralPath (Join-Path $package 'BUILD.json') -Destination (Join-Path $Stage 'mirrors-v0.2.0-rc.6-windows-x86_64.build.json')
Write-Output "PACKAGED $version"
