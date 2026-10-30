# Fixed helper for the task-owned Windows oracle. The request contains only
# public TLA+ sources, identity hashes and credential paths. Credential bytes
# remain in this host's existing pki-2 directory and are read only by Mirrors.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$stage = $PSScriptRoot
$binary = Join-Path $stage 'package\ModelMirrors.exe'
$clientBinary = Join-Path $stage 'client\ModelMirrors.exe'
$pki = Join-Path $stage 'pki-2'
$builder = New-Object Text.StringBuilder
Add-Content -LiteralPath (Join-Path $stage 'query-helper-phases.log') -Value 'bounded request read started'
while (($character = [Console]::In.Read()) -ge 0) {
  if ($character -eq 10) { break }
  if ($builder.Length -ge 131072) { throw 'bounded query request exceeded' }
  $null = $builder.Append([char]$character)
}
Add-Content -LiteralPath (Join-Path $stage 'query-helper-phases.log') -Value 'bounded request read completed'
$request = $builder.ToString() | ConvertFrom-Json
$fields = @('schema','requestId','modelSourceSha256','querySourceSha256','modelBase64','queryBase64','mirrorSha256','bound','credentialPaths')
if (@($request.PSObject.Properties).Count -ne $fields.Count) { throw 'query fields differ' }
foreach ($field in $request.PSObject.Properties.Name) { if ($field -notin $fields) { throw 'unknown query field' } }
if ($request.schema -ne 'mirrors.controlled-model-query/v1' -or $request.requestId -notmatch '^[a-f0-9]{32}$') { throw 'query schema or nonce differs' }
if (($request.bound -isnot [int] -and $request.bound -isnot [long]) -or $request.bound -lt 1 -or $request.bound -gt 33) { throw 'query bound differs' }
foreach ($name in @('modelSourceSha256','querySourceSha256','mirrorSha256')) {
  if ($request.$name -notmatch '^[a-f0-9]{64}$') { throw 'query digest is invalid' }
}
foreach ($pair in @(@('cert',"$pki\client.crt"),@('key',"$pki\client.key"),@('ca',"$pki\ca.crt"))) {
  if ($request.credentialPaths.($pair[0]) -ne $pair[1]) { throw 'credential selector is outside the owned fixture' }
}
function Sha-Bytes([byte[]]$Bytes) {
  $hasher = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($hasher.ComputeHash($Bytes))).Replace('-','').ToLower() }
  finally { $hasher.Dispose() }
}
$model = [Convert]::FromBase64String($request.modelBase64)
$query = [Convert]::FromBase64String($request.queryBase64)
if ($model.Length + $query.Length -gt 49152 -or (Sha-Bytes $model) -ne $request.modelSourceSha256 -or (Sha-Bytes $query) -ne $request.querySourceSha256) { throw 'query source identity differs' }
function Observe-Oracle {
  $observation = Get-Content -LiteralPath (Join-Path $stage 'oracle-observation.json') -Raw | ConvertFrom-Json
  $process = Get-Process -Id $observation.processId
  $handle = $process.Handle
  if ($process.HasExited -or $process.Path -ne $binary -or (Get-FileHash -Algorithm SHA256 -LiteralPath $binary).Hash.ToLower() -ne $observation.serverExecutableSha256) { throw 'owned oracle process or binary differs' }
  $listener = Get-NetTCPConnection -LocalPort 19129 -State Listen -ErrorAction Stop
  if ($listener.OwningProcess -ne $process.Id) { throw 'oracle listener identity differs' }
  if ((Get-FileHash -Algorithm SHA256 -LiteralPath $clientBinary).Hash.ToLower() -ne $request.mirrorSha256 -or $observation.port -ne 19129 -or $observation.host -ne 'localhost') { throw 'validator client or oracle endpoint identity differs' }
  if ((Get-FileHash -Algorithm SHA256 -LiteralPath 'D:\Programs\apalache\lib\apalache.jar').Hash.ToLower() -ne $observation.apalacheJarSha256) { throw 'oracle JAR changed' }
  if ((Get-FileHash -Algorithm SHA256 -LiteralPath 'D:\Programs\jdk-25.0.4+7\bin\java.exe').Hash.ToLower() -ne $observation.javaExecutableSha256) { throw 'oracle Java changed' }
  if ([DateTimeOffset]::Parse($observation.certificateNotAfterUtc) -le [DateTimeOffset]::UtcNow) { throw 'oracle certificate expired' }
  $observation.observedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
  return $observation
}
$observed = Observe-Oracle
Add-Content -LiteralPath (Join-Path $stage 'query-helper-phases.log') -Value ("oracle admitted for " + $request.requestId)
$directory = Join-Path $stage ('query-' + $request.requestId)
if (Test-Path -LiteralPath $directory) { throw 'query identity was already used' }
New-Item -ItemType Directory -Path $directory | Out-Null
[IO.File]::WriteAllBytes((Join-Path $directory 'ControlledMutexFifo.tla'),$model)
[IO.File]::WriteAllBytes((Join-Path $directory 'ControlledWitnessCase.tla'),$query)
$stdout = Join-Path $directory 'stdout.log'
$stderr = Join-Path $directory 'stderr.log'
$env:PATH = 'D:\Programs\msys2\ucrt64\bin;' + $env:PATH
$parameters = @{
  FilePath = $clientBinary; WorkingDirectory = $directory; PassThru = $true; NoNewWindow = $true
  ArgumentList = @('validate','--host','localhost','--port','19129','--tls','--pin',$observed.serverCertificateSha256,
    '--cert',"$pki\client.crt",'--key',"$pki\client.key",'--ca',"$pki\ca.crt",'--spec',(Join-Path $directory 'ControlledWitnessCase.tla'),
    '--cinit','ConstInit','--init','Init','--next','Next','--inv','Conforms','--bound',"$($request.bound)",'--async')
  RedirectStandardOutput = $stdout; RedirectStandardError = $stderr
}
$process = Start-Process @parameters
$ownedHandle = $process.Handle
$deadline = [DateTimeOffset]::UtcNow.AddSeconds(90)
$observedJava = @{}
try {
  while (!$process.WaitForExit(200)) {
    $snapshot = @(Get-CimInstance Win32_Process -Property ProcessId,ParentProcessId,Name,ExecutablePath)
    $descendants = @{}
    $descendants[[int]$observed.processId] = $true
    for ($generation = 0; $generation -lt 8; $generation++) {
      foreach ($candidate in $snapshot) {
        if ($descendants.ContainsKey([int]$candidate.ParentProcessId)) { $descendants[[int]$candidate.ProcessId] = $true }
      }
    }
    foreach ($java in $snapshot) {
      if ($java.Name -eq 'java.exe' -and $java.ExecutablePath -and $descendants.ContainsKey([int]$java.ProcessId)) {
        $digest = (Get-FileHash -Algorithm SHA256 -LiteralPath $java.ExecutablePath).Hash.ToLower()
        $observedJava[$digest] = $true
      }
    }
    $size = 0
    foreach ($path in @($stdout,$stderr)) { if(Test-Path -LiteralPath $path){ $size += (Get-Item -LiteralPath $path).Length } }
    if ($size -gt 262144 -or [DateTimeOffset]::UtcNow -gt $deadline) { throw 'validator deadline or output budget exceeded' }
  }
} finally {
  if (!$process.HasExited) { $process.Kill(); $process.WaitForExit() }
}
$process.WaitForExit(); $process.Refresh()
if ($null -eq $process.ExitCode -or $process.ExitCode -notin @(0,1)) { throw "model validation did not return a verdict: $($process.ExitCode)" }
if ((Get-Item -LiteralPath $stdout).Length + (Get-Item -LiteralPath $stderr).Length -gt 262144) { throw 'validator output budget exceeded' }
$observed = Observe-Oracle
if ($observedJava.Count -ne 1 -or !$observedJava.ContainsKey($observed.javaExecutableSha256)) { throw 'actual backend Java was not observed at the selected identity' }
$children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$($observed.processId)")
if ($children.Count -ne 0) { throw 'oracle child cleanup is not confirmed' }
$result = [ordered]@{
  schema = 'mirrors.controlled-model-query-result/v1'; requestId = $request.requestId
  modelSourceSha256 = $request.modelSourceSha256; querySourceSha256 = $request.querySourceSha256
  mirrorSha256 = $request.mirrorSha256; exitCode = $process.ExitCode; cleanup = 'confirmed'
  javaExecutableSha256 = $observed.javaExecutableSha256
  stdoutBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($stdout))
  stderrBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($stderr))
  observation = $observed
}
$result | ConvertTo-Json -Compress -Depth 8
