$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false)
$active='D:\ModelMirrors\bin\ModelMirrors.exe'
if((Get-FileHash -Algorithm SHA256 -LiteralPath $active).Hash.ToLower() -ne '8173ddea65f78a88b1a303f8a233dd7113b28e7dc8aefd8916a5add25a3687cc'){throw 'active bytes differ from expected retained binary'}
Start-Service -Name ModelMirrors
(Get-Service ModelMirrors).WaitForStatus('Running',[TimeSpan]::FromSeconds(30))
Write-Output 'RETAINED PRODUCTION BINARY RESTARTED'
& 'D:\ModelMirrors\staging\windows-fixes-20261106\python312-completion\python3.exe' -I -S -B 'D:\ModelMirrors\staging\completion-rc11-20261106\production-health-admitted.py' rollback
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
