$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false)
$stage='D:\ModelMirrors\staging\completion-rc11-20261106'
$state=Get-Content -Raw -LiteralPath ($stage+'\oracle-state-rc11-attempt2.json')|ConvertFrom-Json
$p=Get-CimInstance Win32_Process -Filter ('ProcessId='+$state.pid)
if($p){
 if($p.ExecutablePath -ne $state.executable -or (Get-FileHash -Algorithm SHA256 -LiteralPath $p.ExecutablePath).Hash.ToLower() -ne $state.binarySha256){throw 'owned oracle identity changed'}
 if([Math]::Abs(($p.CreationDate.ToUniversalTime()-[DateTime]::Parse($state.createdAt).ToUniversalTime()).TotalMilliseconds) -gt 1){throw 'owned process creation identity changed'}
 $all=@(Get-CimInstance Win32_Process);$owned=@{};$owned[[int]$state.pid]=$true
 for($i=0;$i -lt 8;$i++){foreach($child in $all){if($owned.ContainsKey([int]$child.ParentProcessId)){$owned[[int]$child.ProcessId]=$true}}}
 $children=@($all|Where-Object{$_.ProcessId -ne $state.pid -and $owned.ContainsKey([int]$_.ProcessId)})
 $children|Select-Object ProcessId,ParentProcessId,Name,ExecutablePath,CreationDate|ConvertTo-Json -Depth 5
}
