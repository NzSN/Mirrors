$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false)
$service=Get-CimInstance Win32_Service -Filter "Name='ModelMirrors'"
$sha=[Security.Cryptography.SHA256]::Create()
function Fingerprint([byte[]]$bytes){return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLower()}
function File([string]$path){$f=Get-Item -LiteralPath $path;return [ordered]@{path=$path;bytes=$f.Length;sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLower()}}
$files=@(Get-ChildItem -LiteralPath 'D:\ModelMirrors\bin' -File|Where-Object{$_.Extension -in @('.exe','.dll')}|ForEach-Object{File $_.FullName})
$parameters=Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\ModelMirrors\Parameters'
# Configuration contents stay on the host. Only selected property names and hashes are retained.
$config=@();foreach($name in @('Application','AppDirectory','AppParameters','AppEnvironmentExtra','AppEnvironment','AppStdout','AppStderr')){if($null -ne $parameters.$name){$raw=$parameters.$name|ConvertTo-Json -Compress;$config+=@{name=$name;sha256=(Fingerprint ([Text.Encoding]::UTF8.GetBytes($raw)))}}}
$certificates=@();foreach($path in @('D:\ModelMirrors\certs\server.crt','D:\ModelMirrors\certs\ca.crt')){$cert=New-Object Security.Cryptography.X509Certificates.X509Certificate2($path);$certificates+=@{path=$path;derSha256=(Fingerprint $cert.RawData);notBeforeUtc=$cert.NotBefore.ToUniversalTime().ToString('o');notAfterUtc=$cert.NotAfter.ToUniversalTime().ToString('o');currentlyValid=($cert.NotBefore.ToUniversalTime() -le [DateTime]::UtcNow -and $cert.NotAfter.ToUniversalTime() -gt [DateTime]::UtcNow)}}
$processes=@(Get-CimInstance Win32_Process|Where-Object{$_.ExecutablePath -eq 'D:\ModelMirrors\bin\ModelMirrors.exe'}|Select-Object ProcessId,ParentProcessId,ExecutablePath,CreationDate)
$listeners=@(Get-NetTCPConnection -State Listen -LocalPort 8999 -ErrorAction SilentlyContinue|Select-Object LocalAddress,LocalPort,OwningProcess)
[ordered]@{schema='mirrors.production-preparation-inventory/v1';observedAt=[DateTime]::UtcNow.ToString('o');host=$env:COMPUTERNAME;service=@{name=$service.Name;state=$service.State;startMode=$service.StartMode;processId=$service.ProcessId};binaries=$files;configurationHashes=$config;certificateMetadata=$certificates;processes=$processes;listeners=$listeners;productionModified=$false;credentialsExported=$false}|ConvertTo-Json -Depth 8
