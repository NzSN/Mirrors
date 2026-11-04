$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
function Identity([string]$Path) {
  if (Test-Path -LiteralPath $Path -PathType Leaf) {
    $f = Get-Item -LiteralPath $Path
    return [ordered]@{path=$Path; bytes=$f.Length; sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLower()}
  }
  return [ordered]@{path=$Path; present=$false}
}
$processes = @(Get-CimInstance Win32_Process -Filter "Name='ModelMirrors.exe'")
$processRows = @()
$certRows = @()
$openssl = 'D:\Programs\msys2\ucrt64\bin\openssl.exe'
foreach ($p in $processes) {
  $listeners = @(Get-NetTCPConnection -State Listen -OwningProcess $p.ProcessId -ErrorAction SilentlyContinue |
    Select-Object LocalAddress,LocalPort)
  $processRows += [ordered]@{pid=$p.ProcessId; createdAt=$p.CreationDate.ToUniversalTime().ToString('o');
    executable=(Identity $p.ExecutablePath); listeners=$listeners}
  # Return only selected TLS path arguments, never the complete command line.
  foreach ($flag in @('cert','ca','key')) {
    $match = [regex]::Match($p.CommandLine, ('--' + $flag + '\s+(?:"([^"]+)"|([^\s]+))'))
    if ($match.Success) {
      $path = $match.Groups[1].Value
      if (!$path) { $path = $match.Groups[2].Value }
      if ($flag -eq 'key') {
        $item = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
        $certRows += [ordered]@{pid=$p.ProcessId; role=$flag; path=$path; present=($null -ne $item); bytes=$item.Length}
      } elseif ((Test-Path -LiteralPath $path) -and (Test-Path -LiteralPath $openssl)) {
        $ErrorActionPreference = 'Continue'
        $public = @(& $openssl x509 -in $path -noout -dates -fingerprint -sha256 -subject -ext subjectAltName 2>&1 | ForEach-Object { [string]$_ })
        $opensslExit = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        $certRows += [ordered]@{pid=$p.ProcessId; role=$flag; file=(Identity $path); x509=$public; exitCode=$opensslExit}
      }
    }
  }
}
$svc = Get-Service -Name ModelMirrors -ErrorAction SilentlyContinue
$roots = @('D:\ModelMirrors','D:\ModelMirrors\runtime','D:\ModelMirrors\tools',
  'D:\ModelMirrors\certs','D:\ModelMirrors\pki','D:\ModelMirrors\config',
  'D:\ModelMirrors\staging','D:\Codebase\Mirrors\.golden-build\batteries-repin-20261031')
$layout = @()
foreach ($root in $roots) {
  if (Test-Path -LiteralPath $root) {
    $layout += [ordered]@{path=$root; entries=@(Get-ChildItem -LiteralPath $root | Select-Object Name,Length,PSIsContainer)}
  }
}
[ordered]@{schema='mirrors.s5a-rc6.windows-readonly-probe/v1'; observedAt=(Get-Date).ToUniversalTime().ToString('o');
  host=$env:COMPUTERNAME; serviceStatus=[string]$svc.Status; serviceStartType=[string]$svc.StartType;
  processes=$processRows; certificates=$certRows; layout=$layout; s5aAccepted=$false} | ConvertTo-Json -Depth 9
