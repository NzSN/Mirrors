$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$Stage = 'D:\ModelMirrors\staging\s3-rc7-20261104-f525c63'
function Sha([string]$p) {
    if (Test-Path -LiteralPath $p) { (Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToLower() } else { $null }
}
function Baseline([string]$key) {
    foreach ($prop in $buildEnv.productionBefore.files.PSObject.Properties) {
        if ($prop.Name -eq $key) { return $prop.Value }
    }
    throw "baseline entry missing: $key"
}
$buildEnv = Get-Content -Raw -LiteralPath (Join-Path $Stage 'windows-build-environment.json') | ConvertFrom-Json
$fileKeys = @(
    'D:\ModelMirrors\bin\ModelMirrors.exe',
    'D:\ModelMirrors\bin\libcrypto-3-x64.dll',
    'D:\ModelMirrors\bin\libssl-3-x64.dll',
    'D:\ModelMirrors\bin\zlib1.dll',
    'D:\ModelMirrors\certs\server.crt',
    'D:\ModelMirrors\certs\ca.crt'
)
$comparisons = [ordered]@{}
$allFilesUnchanged = $true
foreach ($k in $fileKeys) {
    $base = Baseline $k
    $now = Sha $k
    $same = ($now -eq $base.sha256)
    if (-not $same) { $allFilesUnchanged = $false }
    $comparisons[$k] = [ordered]@{baselineSha256 = $base.sha256; observedSha256 = $now; unchanged = $same}
}
$service = Get-CimInstance Win32_Service -Filter "Name='ModelMirrors'" -ErrorAction SilentlyContinue
$procs = @(Get-CimInstance Win32_Process -Filter "Name='ModelMirrors.exe'" | ForEach-Object { [ordered]@{pid = $_.ProcessId; path = $_.ExecutablePath} })
$baselineProcs = @($buildEnv.productionBefore.processes)
$prodPidUnchanged = (@($procs).Count -eq @($baselineProcs).Count -and @($procs).Count -eq 1 -and @($procs)[0].pid -eq @($baselineProcs)[0].pid)
$record = [ordered]@{
    schema = 'mirrors.s3-rc7.windows-observation/v1'
    published = $false
    deployed = $false
    capturedAtUtc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    serviceStatus = $(if ($service) { $service.State } else { $null })
    production = @($procs)
    productionExecutableUnchanged = $comparisons['D:\ModelMirrors\bin\ModelMirrors.exe'].unchanged
    productionPidUnchanged = $prodPidUnchanged
    configurationUnchanged = ($comparisons['D:\ModelMirrors\certs\server.crt'].unchanged -and $comparisons['D:\ModelMirrors\certs\ca.crt'].unchanged)
    allBaselineFilesUnchanged = $allFilesUnchanged
    fileComparisons = $comparisons
    serviceLifecycleChanged = $false
    reboot = $false
}
[IO.File]::WriteAllText((Join-Path $Stage 'windows-final-observation.json'), ($record | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
Write-Output ("OBSERVE exeUnchanged=" + $record.productionExecutableUnchanged + " pidUnchanged=" + $prodPidUnchanged + " filesUnchanged=" + $allFilesUnchanged)
if (-not $allFilesUnchanged -or -not $prodPidUnchanged) { exit 1 }
