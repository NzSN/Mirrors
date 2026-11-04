$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$Stage = 'D:\ModelMirrors\staging\s3-rc7-20261104-f525c63'
function Sha([string]$p) {
  if (Test-Path -LiteralPath $p) {
    (Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToLower()
  } else { $null }
}
function First-Line([string]$path, [string]$arg) {
  $info = New-Object System.Diagnostics.ProcessStartInfo
  $info.FileName = $path
  $info.Arguments = $arg
  $info.UseShellExecute = $false
  $info.RedirectStandardInput = $true
  $info.RedirectStandardOutput = $true
  $info.RedirectStandardError = $true
  $info.CreateNoWindow = $true
  $proc = New-Object System.Diagnostics.Process
  $proc.StartInfo = $info
  [void]$proc.Start()
  $proc.StandardInput.Close()
  $out = $proc.StandardOutput.ReadToEnd()
  $err = $proc.StandardError.ReadToEnd()
  $proc.WaitForExit()
  $text = ($out + $err).Trim()
  if ($text.Length -eq 0) { return '' }
  return $text.Split([char]10)[0].Trim()
}
$utc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
Write-Output ('PROBE_UTC ' + $utc)
Write-Output ('HOST ' + $env:COMPUTERNAME)
Write-Output ('USER ' + $env:USERNAME)
Write-Output ('OS ' + [Environment]::OSVersion.VersionString)
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
Write-Output ('PRODUCT ' + $cv.ProductName + ' ' + $cv.DisplayVersion + ' build ' + $cv.CurrentBuild + '.' + $cv.UBR)
Write-Output ('PS ' + $PSVersionTable.PSVersion.ToString())
Write-Output ('PS_EDITION ' + $PSVersionTable.PSEdition)
foreach ($d in @('C:','D:')) {
  $v = Get-CimInstance Win32_LogicalDisk -Filter ('DeviceID=' + [char]39 + $d + [char]39)
  if ($v) { Write-Output ('VOL ' + $d + ' free=' + $v.FreeSpace + ' size=' + $v.Size + ' fs=' + $v.FileSystem) }
}
$leanbin = 'C:\Users\win10\.elan\toolchains\leanprover--lean4---v4.33.0\bin'
$tools = @(
  @('lake', ($leanbin + '\lake.exe')),
  @('lean', ($leanbin + '\lean.exe')),
  @('gcc', 'D:\Programs\Perl\c\bin\gcc.exe'),
  @('git', 'C:\Program Files\Git\cmd\git.exe')
)
foreach ($t in $tools) {
  $exists = Test-Path -LiteralPath $t[1]
  $line = ''
  if ($exists) {
    $ErrorActionPreference = 'Continue'
    $line = First-Line $t[1] '--version'
    $ErrorActionPreference = 'Stop'
  }
  Write-Output ('TOOL' + [char]9 + $t[0] + [char]9 + 'present=' + $exists + [char]9 + 'path=' + $t[1] + [char]9 + 'version=' + $line + [char]9 + 'sha=' + (Sha $t[1]))
}
$openssl = 'D:\Programs\msys2\ucrt64\bin\openssl.exe'
$opensslPresent = Test-Path -LiteralPath $openssl
$opensslLine = ''
if ($opensslPresent) {
  $ErrorActionPreference = 'Continue'
  $opensslLine = First-Line $openssl 'version'
  $ErrorActionPreference = 'Stop'
}
Write-Output ('TOOL' + [char]9 + 'openssl' + [char]9 + 'present=' + $opensslPresent + [char]9 + 'path=' + $openssl + [char]9 + 'version=' + $opensslLine + [char]9 + 'sha=' + (Sha $openssl))
Write-Output ('DLL libcrypto ' + (Sha 'D:\Programs\msys2\ucrt64\bin\libcrypto-3-x64.dll'))
Write-Output ('DLL libssl ' + (Sha 'D:\Programs\msys2\ucrt64\bin\libssl-3-x64.dll'))
$stageParent = 'D:\ModelMirrors\staging'
Write-Output ('STAGE_PARENT_EXISTS ' + (Test-Path -LiteralPath $stageParent))
Write-Output ('STAGE ' + $Stage)
Write-Output ('STAGE_EXISTS ' + (Test-Path -LiteralPath $Stage))
if (Test-Path -LiteralPath $stageParent) {
  $names = (Get-ChildItem -LiteralPath $stageParent -Name | Out-String).Trim().Replace([string]([char]13 + [char]10), ' | ')
  Write-Output ('STAGING_ENTRIES ' + $names)
}
Write-Output ('PROD_SHA ' + (Sha 'D:\ModelMirrors\bin\ModelMirrors.exe'))
$svc = Get-Service -Name 'ModelMirrors' -ErrorAction SilentlyContinue
$svcState = 'absent'
if ($svc) { $svcState = [string]$svc.Status + '/' + [string]$svc.StartType }
Write-Output ('SERVICE ' + $svcState)
$procs = Get-Process -Name 'ModelMirrors' -ErrorAction SilentlyContinue
if ($procs) {
  foreach ($p in @($procs)) { Write-Output ('PROCPID ' + $p.Id + ' ' + $p.Path) }
}
Write-Output 'PROBE_DONE'
