$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false)
function FileIdentity([string]$path) {
  if(-not (Test-Path -LiteralPath $path -PathType Leaf)){return @{path=$path;exists=$false}}
  $file=Get-Item -LiteralPath $path
  return @{path=$path;exists=$true;bytes=$file.Length;sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLower()}
}
$service=Get-CimInstance Win32_Service -Filter "Name='ModelMirrors'"
$os=Get-CimInstance Win32_OperatingSystem
$certificatePath='D:\ModelMirrors\certs\server.crt'
$certificate=$null
if(Test-Path -LiteralPath $certificatePath) {
  $cert=New-Object Security.Cryptography.X509Certificates.X509Certificate2($certificatePath)
  $sha=[Security.Cryptography.SHA256]::Create()
  $certificate=@{sha256=([BitConverter]::ToString($sha.ComputeHash($cert.RawData))).Replace('-','').ToLower();notBeforeUtc=$cert.NotBefore.ToUniversalTime().ToString('o');notAfterUtc=$cert.NotAfter.ToUniversalTime().ToString('o');validNow=($cert.NotBefore.ToUniversalTime() -le [DateTime]::UtcNow -and $cert.NotAfter.ToUniversalTime() -gt [DateTime]::UtcNow)}
}
$paths=@('D:\ModelMirrors\bin\ModelMirrors.exe','D:\Programs\apalache\lib\apalache.jar','D:\Programs\jdk-25.0.4+7\bin\java.exe','D:\ModelMirrors\staging\windows-fixes-20261106\python312-completion\python3.exe','D:\ModelMirrors\staging\qualification-rc7-20261105\runtime-inputs\native-test-job-detached.exe','D:\ModelMirrors\staging\qualification-rc7-20261105\runtime-inputs\apalache-qualify-job.exe','D:\ModelMirrors\staging\completion-rc11-20261106\source\.lake\build\bin\mirror.exe')
$files=@($paths | ForEach-Object {FileIdentity $_})
$drives=@(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | Select-Object DeviceID,Size,FreeSpace)
$listeners=@(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object {$_.LocalPort -in @(8999,19099)} | Select-Object LocalAddress,LocalPort,OwningProcess)
[ordered]@{schema='mirrors.rc12.windows-intake/v1';observedAt=[DateTime]::UtcNow.ToString('o');host=$env:COMPUTERNAME;os=$os.Caption;osVersion=$os.Version;lastBootUtc=$os.LastBootUpTime.ToUniversalTime().ToString('o');service=@{name=$service.Name;state=$service.State;startMode=$service.StartMode;pid=$service.ProcessId};files=$files;serverCertificate=$certificate;drives=$drives;listeners=$listeners;productionMutationPerformed=$false}|ConvertTo-Json -Depth 8
