$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false)
$stages=@('D:\ModelMirrors\staging\windows-fixes-20261106\','D:\ModelMirrors\staging\qualification-rc7-20261105\')
$processes=Get-CimInstance Win32_Process
$owned=@($processes | Where-Object { $file=$_.ExecutablePath; $file -and @($stages | Where-Object {$file.StartsWith($_,[System.StringComparison]::OrdinalIgnoreCase)}).Count -gt 0 } | Select-Object ProcessId,ParentProcessId,Name)
$os=Get-CimInstance Win32_OperatingSystem
[ordered]@{observedAt=(Get-Date).ToUniversalTime().ToString('o');host=$env:COMPUTERNAME;operatingSystem=$os.Caption;osVersion=$os.Version;remainingStageProcesses=$owned}|ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 -LiteralPath 'D:\ModelMirrors\staging\windows-fixes-20261106\final-observation.json'
if($owned.Count -ne 0){throw 'stage processes remain'}
