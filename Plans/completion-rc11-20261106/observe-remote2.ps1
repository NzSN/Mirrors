$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false)
$s='D:\ModelMirrors\staging\completion-rc11-20261106'
$i='D:\ModelMirrors\staging\qualification-rc7-20261105'
$state=Get-Content -Raw -LiteralPath ($s+'\oracle-state-rc11-attempt2.json')|ConvertFrom-Json
$p=Get-CimInstance Win32_Process -Filter ('ProcessId='+$state.pid)
if(-not $p -or $p.ExecutablePath -ne $state.executable){throw 'owned fixture process changed'}
$listener=Get-NetTCPConnection -State Listen -LocalPort 19099
if($listener.OwningProcess -ne $state.pid -or $listener.LocalAddress -ne '127.0.0.1'){throw 'owned listener differs'}
$cert=New-Object Security.Cryptography.X509Certificates.X509Certificate2($i+'\private-pki\server.crt')
if($cert.NotBefore.ToUniversalTime() -gt [DateTime]::UtcNow -or $cert.NotAfter.ToUniversalTime() -le [DateTime]::UtcNow){throw 'task certificate invalid'}
$h=[Security.Cryptography.SHA256]::Create();$fp=([BitConverter]::ToString($h.ComputeHash($cert.RawData))).Replace('-','').ToLower()
function File([string]$path){$f=Get-Item -LiteralPath $path;return [ordered]@{path=$path;bytes=$f.Length;sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLower()}}
$runtime=[ordered]@{apalacheArchive=(File ($i+'\runtime-inputs\apalache-0.62.2.tgz'));jar=(File ($i+'\runtime-inputs\apalache.jar'));javaArchive=(File ($i+'\runtime-inputs\microsoft-jdk-25.0.4-windows-x64.zip'));java=(File 'D:\Programs\jdk-25.0.4+7\bin\java.exe');adapter=(File ($i+'\runtime-inputs\apalache-qualify-job.exe'))}
$fixtures=[ordered]@{'Counter.tla'=(Get-FileHash -Algorithm SHA256 -LiteralPath ($i+'\Counter.tla')).Hash.ToLower();'violation.itf.json'=(Get-FileHash -Algorithm SHA256 -LiteralPath ($i+'\violation.itf.json')).Hash.ToLower()}
$service=Get-Service -Name ModelMirrors
$ErrorActionPreference='Continue'
$jv=(& 'D:\Programs\jdk-25.0.4+7\bin\java.exe' -version 2>&1|Out-String)
$ErrorActionPreference='Stop'
$record=[ordered]@{state=$state;processCreatedAt=$p.CreationDate.ToUniversalTime().ToString('o');binary=(File $p.ExecutablePath);runtimeFiles=$runtime;interopFixtures=@{root=$i;files=$fixtures};serverLeafSha256=$fp;certificateNotBefore=$cert.NotBefore.ToUniversalTime().ToString('o');certificateNotAfter=$cert.NotAfter.ToUniversalTime().ToString('o');observedAt=[DateTime]::UtcNow.ToString('o');productionServiceStatus=$service.Status.ToString();productionUsed=$false;javaVersion=$jv}
$record|ConvertTo-Json -Depth 8
