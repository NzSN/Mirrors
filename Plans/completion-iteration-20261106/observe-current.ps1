$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false)
$prefixes=@('D:\ModelMirrors\staging\windows-fixes-20261106\','D:\ModelMirrors\staging\qualification-rc7-20261105\')
$all=Get-CimInstance Win32_Process
$ids=[System.Collections.Generic.HashSet[int]]::new()
foreach($p in $all){foreach($prefix in $prefixes){if($p.ExecutablePath -and $p.ExecutablePath.StartsWith($prefix,[System.StringComparison]::OrdinalIgnoreCase)){[void]$ids.Add($p.ProcessId)}}}
do{$changed=$false;foreach($p in $all){if($ids.Contains($p.ParentProcessId) -and -not $ids.Contains($p.ProcessId)){[void]$ids.Add($p.ProcessId);$changed=$true}}}while($changed)
$all|Where-Object{$ids.Contains($_.ProcessId)}|Select-Object ProcessId,ParentProcessId,Name,CreationDate
Get-Content -LiteralPath 'D:\ModelMirrors\staging\qualification-rc7-20261105\logs\20261106-iteration-full-lake-test-20.log' -Tail 12
