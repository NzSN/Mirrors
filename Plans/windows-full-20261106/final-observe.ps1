$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false)
$s='D:\ModelMirrors\staging\qualification-rc7-20261105'
$src=$s+'\Mirrors-rc8-f328e32'
$git='C:\Program Files\Git\cmd\git.exe'
$sourceRevision=(& $git -C $src rev-parse HEAD)
$sourceStatus=@(& $git -C $src status --porcelain)
if($LASTEXITCODE -ne 0){throw 'git status failed'}
$owned=@(Get-CimInstance Win32_Process | Where-Object {$_.ExecutablePath -like ($s+'\*')} | Select-Object ProcessId,ParentProcessId,Name)
[ordered]@{observedAt=(Get-Date).ToUniversalTime().ToString('o');host=$env:COMPUTERNAME;sourceRevision=$sourceRevision;sourceStatus=$sourceStatus;remainingStageProcesses=$owned;pythonVersion=(& 'D:\Programs\Python310\python.exe' --version);leanVersion=(& 'C:\Users\win10\.elan\toolchains\leanprover--lean4---v4.33.0\bin\lean.exe' --version)} | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 -LiteralPath ($s+'\logs\20261106-full-lake-final-observation.json')
