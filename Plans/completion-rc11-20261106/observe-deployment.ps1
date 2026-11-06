$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false)
$stage='D:\ModelMirrors\staging\completion-rc11-20261106'
$prepared=Get-Content -Raw -LiteralPath ($stage+'\deployment-prepared.json')|ConvertFrom-Json
$service=Get-CimInstance Win32_Service -Filter "Name='ModelMirrors'"
$operatingSystem=Get-CimInstance Win32_OperatingSystem
$active='D:\ModelMirrors\bin\ModelMirrors.exe'
$sha=[Security.Cryptography.SHA256]::Create()
function Hash([string]$path){return (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLower()}
function File([string]$path){$f=Get-Item -LiteralPath $path;return [ordered]@{path=$path;bytes=$f.Length;sha256=(Hash $path)}}
$values=Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\ModelMirrors\Parameters'
$config=[ordered]@{}
foreach($name in @('Application','AppDirectory','AppParameters','AppEnvironmentExtra','AppEnvironment','AppStdout','AppStderr')){if($null -ne $values.$name){$raw=$values.$name|ConvertTo-Json -Compress;$config[$name]=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($raw)))).Replace('-','').ToLower()}}
if(($config|ConvertTo-Json -Compress) -ne $prepared.configurationHashes){throw 'production configuration drifted'}
if((Hash $active) -ne $prepared.newSha256){throw 'deployed executable differs'}
if($service.State -ne 'Running' -or $service.StartMode -ne 'Auto'){throw 'service is not Running/Auto'}
$processes=@(Get-CimInstance Win32_Process|Where-Object{$_.ExecutablePath -eq $active}|Select-Object ProcessId,ParentProcessId,ExecutablePath,CreationDate)
if($processes.Count -ne 1){throw 'expected exactly one production server'}
$listeners=@(Get-NetTCPConnection -State Listen -LocalPort 8999 -ErrorAction Stop|Select-Object LocalAddress,LocalPort,OwningProcess)
if(@($listeners|Where-Object{$_.OwningProcess -ne $processes[0].ProcessId}).Count -ne 0){throw 'listener ownership differs'}
$cert=New-Object Security.Cryptography.X509Certificates.X509Certificate2('D:\ModelMirrors\certs\server.crt')
$pin=([BitConverter]::ToString($sha.ComputeHash($cert.RawData))).Replace('-','').ToLower()
if($pin -ne 'b2fc7265145cf2b89a1a248b0932885df8d300121b47f7854317ece4bac9ce67' -or $cert.NotAfter.ToUniversalTime() -le [DateTime]::UtcNow){throw 'certificate identity/validity differs'}
$dlls=@();foreach($name in @('libcrypto-3-x64.dll','libssl-3-x64.dll','zlib1.dll')){$path='D:\ModelMirrors\bin\'+$name;if((Hash $path) -ne (Hash ($stage+'\mirrors-v0.2.0-rc.11-windows-x86_64\bin\'+$name))){throw 'DLL identity differs'};$dlls+=@(File $path)}
$runtime=@(File 'D:\Programs\apalache\lib\apalache.jar';File 'D:\Programs\jdk-25.0.4+7\bin\java.exe';File 'D:\ModelMirrors\bin\apalache-mc.exe')
if($runtime[0].sha256 -ne '079b6c2320252469dcf79afec6886b8255d3dd1b34a9484433c88986752efaa8' -or $runtime[1].sha256 -ne '58df5c13e5d6e68f242ad9b724479122828523008ef0907d3f2a02f54afaff23'){throw 'runtime pins differ'}
[ordered]@{status='verified-running-auto-deployment';observedAt=[DateTime]::UtcNow.ToString('o');lastBootUpTimeUtc=$operatingSystem.LastBootUpTime.ToUniversalTime().ToString('o');service=@{name=$service.Name;state=$service.State;startMode=$service.StartMode;pid=$service.ProcessId};binary=(File $active);dlls=$dlls;runtime=$runtime;serverCertificateSha256=$pin;certificateNotAfterUtc=$cert.NotAfter.ToUniversalTime().ToString('o');configurationPreserved=$true;processes=$processes;listeners=$listeners}|ConvertTo-Json -Depth 8
