$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false)
$s='D:\ModelMirrors\staging\qualification-rc7-20261105'
$state=Get-Content -Raw -LiteralPath ($s+'\oracle-state-attempt2.json')|ConvertFrom-Json
$p=Get-CimInstance Win32_Process -Filter ('ProcessId='+$state.pid)
if(-not $p -or $p.ExecutablePath -ne $state.executable){throw 'fixture process identity changed'}
$listen=Get-NetTCPConnection -State Listen -LocalPort 19099
if($listen.OwningProcess -ne $state.pid -or $listen.LocalAddress -ne '127.0.0.1'){throw 'fixture listener differs'}
$cert=New-Object Security.Cryptography.X509Certificates.X509Certificate2($s+'\private-pki\server.crt')
$h=[Security.Cryptography.SHA256]::Create()
$fp=([BitConverter]::ToString($h.ComputeHash($cert.RawData))).Replace('-','').ToLower()
$java=Get-Content -Raw -LiteralPath ($s+'\java-observations.json')|ConvertFrom-Json
if(-not(@($java)|Where-Object{$_.path -eq 'D:\Programs\jdk-25.0.4+7\bin\java.exe' -and $_.sha256 -eq '58df5c13e5d6e68f242ad9b724479122828523008ef0907d3f2a02f54afaff23'})){throw 'selected Java execution not observed'}
$record=[ordered]@{schema='mirrors.controlled-model-observation/v1';host='127.0.0.1';port=19099;serverCertificateSha256=$fp;serverExecutableSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $p.ExecutablePath).Hash.ToLower();sourceCommit=$state.sourceRevision;apalacheJarSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath ($s+'\runtime-inputs\apalache.jar')).Hash.ToLower();javaExecutableSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath 'D:\Programs\jdk-25.0.4+7\bin\java.exe').Hash.ToLower();javaVersion='25.0.4+7-LTS';processId=[int]$state.pid;observedAtUtc=(Get-Date).ToUniversalTime().ToString('o');certificateNotAfterUtc=$cert.NotAfter.ToUniversalTime().ToString('o')}

function File([string]$path){$f=Get-Item -LiteralPath $path;return [ordered]@{path=$path;bytes=$f.Length;sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLower()}}
$runtime=[ordered]@{apalacheArchive=(File ($s+'\runtime-inputs\apalache-0.62.2.tgz'));jar=(File ($s+'\runtime-inputs\apalache.jar'));javaArchive=(File ($s+'\runtime-inputs\microsoft-jdk-25.0.4-windows-x64.zip'));java=(File 'D:\Programs\jdk-25.0.4+7\bin\java.exe');adapter=(File ($s+'\runtime-inputs\apalache-qualify.exe'))}
$fixtures=[ordered]@{'Counter.tla'=(Get-FileHash -Algorithm SHA256 -LiteralPath ($s+'\Counter.tla')).Hash.ToLower();'violation.itf.json'=(Get-FileHash -Algorithm SHA256 -LiteralPath ($s+'\violation.itf.json')).Hash.ToLower()}
[ordered]@{observation=$record;state=$state;processCreatedAt=$p.CreationDate.ToUniversalTime().ToString('o');runtimeFiles=$runtime;interopFixtures=@{root=$s;files=$fixtures}}|ConvertTo-Json -Depth 8
