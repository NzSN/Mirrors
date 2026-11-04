$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$Stage = 'D:\ModelMirrors\staging\s3-rc7-20261104-f525c63'
$source = Join-Path $Stage 'mirrors-v0.2.0-rc.7'
$logs = Join-Path $Stage 'logs'
if (Test-Path -LiteralPath $logs) { throw 'logs directory already exists' }
New-Item -ItemType Directory -Path $logs | Out-Null
$leanbin = 'C:\Users\win10\.elan\toolchains\leanprover--lean4---v4.33.0\bin'
$tmp = 'D:\ModelMirrors\tmp\s3-rc7-20261104-f525c63'
if (-not (Test-Path -LiteralPath $tmp)) { throw 'task temp directory missing' }
$env:CC = 'D:/Programs/Perl/c/bin/gcc.exe'
$env:OSSL_INC = 'D:/Programs/msys2/ucrt64/include'
$env:OSSL_LIB = 'D:/Programs/msys2/ucrt64/lib'
$env:TEMP = $tmp
$env:TMP = $tmp
$env:TMPDIR = $tmp
$env:PATH = "$leanbin;D:\Programs\msys2\ucrt64\bin;D:\Programs\Perl\c\bin;" + $env:PATH
foreach ($name in @('APALACHE_MC', 'APALACHE_JAR', 'TLA2TOOLS_JAR')) {
    Remove-Item -LiteralPath ("Env:" + $name) -ErrorAction SilentlyContinue
}
function Sha([string]$p) {
    if (Test-Path -LiteralPath $p) { (Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToLower() } else { $null }
}
function ToolRecord([string]$label, [string]$exe, [string[]]$toolArgs) {
    if (-not (Test-Path -LiteralPath $exe)) { return [ordered]@{label = $label; path = $exe; present = $false} }
    $ErrorActionPreference = 'Continue'
    $out = (& $exe @toolArgs 2>&1 | Out-String).Trim()
    $ErrorActionPreference = 'Stop'
    $first = ($out -split "`r?`n")[0]
    [ordered]@{
        label = $label; path = $exe; present = $true; version = $first
        sha256 = (Sha $exe)
    }
}
$prodPaths = @(
    'D:\ModelMirrors\bin\ModelMirrors.exe',
    'D:\ModelMirrors\bin\libcrypto-3-x64.dll',
    'D:\ModelMirrors\bin\libssl-3-x64.dll',
    'D:\ModelMirrors\bin\zlib1.dll',
    'D:\ModelMirrors\certs\server.crt',
    'D:\ModelMirrors\certs\ca.crt'
)
$prodFiles = [ordered]@{}
foreach ($p in $prodPaths) {
    $exists = Test-Path -LiteralPath $p
    $bytes = $null
    $lastWrite = $null
    if ($exists) {
        $item = Get-Item -LiteralPath $p
        $bytes = $item.Length
        $lastWrite = $item.LastWriteTimeUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')
    }
    $prodFiles[$p] = [ordered]@{sha256 = (Sha $p); bytes = $bytes; lastWriteUtc = $lastWrite; hashOnly = ($p -like '*.key')}
}
$service = Get-CimInstance Win32_Service -Filter "Name='ModelMirrors'" -ErrorAction SilentlyContinue
$envRecord = [ordered]@{
    schema = 'mirrors.s3-rc7.windows-build-environment/v1'
    published = $false
    deployed = $false
    host = $env:COMPUTERNAME
    os = [Environment]::OSVersion.VersionString
    powershell = $PSVersionTable.PSVersion.ToString()
    stagingDirectory = $Stage
    sourceDirectory = $source
    capturedAtUtc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    tools = @(
        (ToolRecord 'lake' "$leanbin\lake.exe" @('--version')),
        (ToolRecord 'lean' "$leanbin\lean.exe" @('--version')),
        (ToolRecord 'gcc' 'D:\Programs\Perl\c\bin\gcc.exe' @('--version')),
        (ToolRecord 'python' 'D:\Programs\Python310\python.exe' @('--version')),
        (ToolRecord 'git' 'C:\Program Files\Git\cmd\git.exe' @('--version')),
        (ToolRecord 'openssl' 'D:\Programs\msys2\ucrt64\bin\openssl.exe' @('version'))
    )
    openssl = [ordered]@{
        includeDir = $env:OSSL_INC
        libraryDir = $env:OSSL_LIB
        libcrypto = (Sha 'D:\Programs\msys2\ucrt64\bin\libcrypto-3-x64.dll')
        libssl = (Sha 'D:\Programs\msys2\ucrt64\bin\libssl-3-x64.dll')
        zlib1 = (Sha 'D:\ModelMirrors\releases\20261029-completion-7e9a27d\candidate-v0.2.0-rc.1\bin\zlib1.dll')
    }
    environment = [ordered]@{CC = $env:CC; OSSL_INC = $env:OSSL_INC; OSSL_LIB = $env:OSSL_LIB; TEMP = $env:TEMP; APALACHE_MC = 'unset'; APALACHE_JAR = 'unset'; TLA2TOOLS_JAR = 'unset'}
    productionBefore = [ordered]@{
        serviceStatus = $(if ($service) { $service.State } else { $null })
        processes = @(Get-CimInstance Win32_Process -Filter "Name='ModelMirrors.exe'" | ForEach-Object { [ordered]@{pid = $_.ProcessId; path = $_.ExecutablePath; created = $_.CreationDate} })
        files = $prodFiles
    }
}
[IO.File]::WriteAllText((Join-Path $Stage 'windows-build-environment.json'), ($envRecord | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
Write-Output 'ENV CAPTURED'
$targets = @('mirror', 'model_interface_gen', 'fixtures_replay', 'diff_cross', 'model_interface_spec', 'stdio_smoke', 'transport_spec', 'jobstore_spec', 'async_resource_spec', 'dpm_sync_spec')
$buildlog = Join-Path $logs 'build.log'
$started = Get-Date
$cmdLine = '"' + $leanbin + '\lake.exe" build ' + ($targets -join ' ') + ' > "' + $buildlog + '" 2>&1'
Push-Location -LiteralPath $source
try { & cmd.exe /d /s /c $cmdLine; $buildExit = $LASTEXITCODE } finally { Pop-Location }
$finished = Get-Date
$buildLogBytes = $null
if (Test-Path -LiteralPath $buildlog) { $buildLogBytes = (Get-Item -LiteralPath $buildlog).Length }
$buildRecord = [ordered]@{
    schema = 'mirrors.s3-rc7.windows-build/v1'
    published = $false
    deployed = $false
    command = ('lake build ' + ($targets -join ' '))
    cwd = $source
    exit = $buildExit
    startedUtc = $started.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    finishedUtc = $finished.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    seconds = [math]::Round(($finished - $started).TotalSeconds, 1)
    log = 'logs/build.log'
    logBytes = $buildLogBytes
    logSha256 = (Sha $buildlog)
    fullLakeTest = $false
    binaries = [ordered]@{}
}
foreach ($b in @('mirror', 'model_interface_gen', 'fixtures_replay', 'diff_cross', 'model_interface_spec', 'stdio_smoke', 'transport_spec', 'jobstore_spec', 'async_resource_spec', 'dpm_sync_spec')) {
    $p = Join-Path $source ('.lake/build/bin/' + $b + '.exe')
    $bbytes = $null
    if (Test-Path -LiteralPath $p) { $bbytes = (Get-Item -LiteralPath $p).Length }
    $buildRecord.binaries[$b] = [ordered]@{path = $p; sha256 = (Sha $p); bytes = $bbytes}
}
[IO.File]::WriteAllText((Join-Path $Stage 'windows-build-record.json'), ($buildRecord | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
Write-Output ("BUILD EXIT " + $buildExit)
if ($buildExit -ne 0) { exit $buildExit }
$opensslCli = ((& where.exe openssl 2>&1 | Out-String).Trim())
$gateRecords = @()
foreach ($gate in @('fixtures_replay', 'diff_cross', 'model_interface_spec', 'stdio_smoke', 'transport_spec', 'jobstore_spec', 'async_resource_spec', 'dpm_sync_spec')) {
    $exe = Join-Path $source ('.lake/build/bin/' + $gate + '.exe')
    $log = Join-Path $logs ($gate + '.log')
    $s = Get-Date
    $line = '"' + $exe + '" > "' + $log + '" 2>&1'
    Push-Location -LiteralPath $source
    try { & cmd.exe /d /s /c $line; $code = $LASTEXITCODE } finally { Pop-Location }
    $f = Get-Date
    $logBytes = $null
    if (Test-Path -LiteralPath $log) { $logBytes = (Get-Item -LiteralPath $log).Length }
    $gateRecords += [ordered]@{
        gate = $gate
        command = ('.lake/build/bin/' + $gate + '.exe')
        cwd = $source
        exit = $code
        startedUtc = $s.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        finishedUtc = $f.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        seconds = [math]::Round(($f - $s).TotalSeconds, 1)
        log = ('logs/' + $gate + '.log')
        logBytes = $logBytes
        logSha256 = (Sha $log)
    }
    Write-Output ("GATE " + $gate + " EXIT " + $code)
}
$gateDoc = [ordered]@{
    schema = 'mirrors.s3-rc7.windows-gates/v1'
    published = $false
    deployed = $false
    fullLakeTest = $false
    cwd = $source
    environment = [ordered]@{
        pathPrepend = $leanbin + ';D:\Programs\msys2\ucrt64\bin;D:\Programs\Perl\c\bin'
        opensslCli = $opensslCli
        APALACHE_MC = 'unset'
        APALACHE_JAR = 'unset'
        TLA2TOOLS_JAR = 'unset'
    }
    gates = $gateRecords
}
[IO.File]::WriteAllText((Join-Path $Stage 'windows-gates.json'), ($gateDoc | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
$failed = @($gateRecords | Where-Object { $_.exit -ne 0 }).Count
Write-Output ("GATES_FAILED " + $failed)
exit $(if ($failed -gt 0) { 1 } else { 0 })
