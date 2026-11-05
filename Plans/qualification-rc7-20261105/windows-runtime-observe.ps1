$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
function Identity([string]$p) {
  if (Test-Path -LiteralPath $p -PathType Leaf) {
    $f = Get-Item -LiteralPath $p
    return [ordered]@{path=$p; bytes=$f.Length; sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToLower()}
  }
  return [ordered]@{path=$p; present=$false}
}
$selected = [ordered]@{}
$parameters = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\ModelMirrors\Parameters' -ErrorAction SilentlyContinue
foreach ($line in @($parameters.AppEnvironmentExtra) + @($parameters.AppEnvironment)) {
  if ($line -match '^(APALACHE_MC|JAVA_HOME)=(.*)$') { $selected[$matches[1]]=$matches[2] }
}
$candidates = @()
foreach ($base in @('D:\Programs','D:\ModelMirrors','C:\Users\win10\Downloads')) {
  if (Test-Path -LiteralPath $base) {
    $candidates += @(Get-ChildItem -LiteralPath $base -File | Where-Object {$_.Name -match '(apalache|openjdk|microsoft-jdk|java|jdk).*(tgz|zip|tar.gz)$'} | ForEach-Object { Identity $_.FullName })
  }
}
$layout = @()
foreach ($dir in @(Get-ChildItem -LiteralPath 'D:\Programs' -Directory | Where-Object {$_.Name -match 'apalache|java|jdk|openjdk'})) {
  $files = @(Get-ChildItem -LiteralPath $dir.FullName -File -Recurse -Depth 3 | Where-Object {$_.Name -match '^(java.exe|apalache.jar|apalache-mc|apalache-mc.bat|apalache-mc.cmd)$' -or $_.Name -match '(apalache|openjdk|microsoft-jdk).*(tgz|zip|tar.gz)$'})
  $layout += [ordered]@{root=$dir.FullName; inputs=@($files | ForEach-Object { Identity $_.FullName })}
}
$procs = @(Get-CimInstance Win32_Process -Filter "Name='ModelMirrors.exe'" | Select-Object ProcessId,ExecutablePath,CreationDate)
$ports = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object {$_.LocalPort -in @(8999,19099,19199)} | Select-Object LocalAddress,LocalPort,OwningProcess)
[ordered]@{schema='mirrors.rc7.qualification-runtime-observation/v1'; at=(Get-Date).ToUniversalTime().ToString('o'); host=$env:COMPUTERNAME; selectedRuntimePaths=$selected; currentJavaHome=$env:JAVA_HOME; archiveCandidates=$candidates; runtimeLayout=$layout; production=$procs; listeners=$ports} | ConvertTo-Json -Depth 9
