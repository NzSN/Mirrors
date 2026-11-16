$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false)
$stage='D:\ModelMirrors\staging\completion-rc12-20261116'
$state=Get-Content -Raw -LiteralPath ($stage+'\oracle-state-rc12.json')|ConvertFrom-Json
$children=@()
$p=Get-CimInstance Win32_Process -Filter ('ProcessId='+$state.pid)
if($p){
 if($p.ExecutablePath -ne $state.executable -or (Get-FileHash -Algorithm SHA256 -LiteralPath $p.ExecutablePath).Hash.ToLower() -ne $state.binarySha256){throw 'owned oracle identity changed'}
 if([Math]::Abs(($p.CreationDate.ToUniversalTime()-[DateTime]::Parse($state.createdAt).ToUniversalTime()).TotalMilliseconds) -gt 1){throw 'owned process creation identity changed'}
 $all=@(Get-CimInstance Win32_Process);$owned=@{};$owned[[int]$state.pid]=$true
 for($i=0;$i -lt 8;$i++){foreach($child in $all){if($owned.ContainsKey([int]$child.ParentProcessId)){$owned[[int]$child.ProcessId]=$true}}}
 $children=@($all|Where-Object{$_.ProcessId -ne $state.pid -and $owned.ContainsKey([int]$_.ProcessId)})
 if(@($children|Where-Object{$_.Name -ne 'conhost.exe' -or $_.ExecutablePath -ne 'C:\Windows\system32\conhost.exe' -or $_.ParentProcessId -ne $state.pid}).Count -ne 0){throw 'owned model children remain before oracle stop'}
 Stop-Process -Id $state.pid -ErrorAction Stop
}
Start-Sleep -Milliseconds 600
$consoleRemaining=@();foreach($child in $children){$now=Get-CimInstance Win32_Process -Filter ('ProcessId='+$child.ProcessId);if($now -and $now.CreationDate -eq $child.CreationDate){$consoleRemaining+=@($now)}}
if($consoleRemaining.Count -ne 0){throw 'owned console child remains after oracle stop'}
$remaining=@(Get-CimInstance Win32_Process|Where-Object{$_.ExecutablePath -eq $state.executable}|Select-Object ProcessId,ExecutablePath)
$listeners=@(Get-NetTCPConnection -State Listen -LocalPort 19099 -ErrorAction SilentlyContinue|Select-Object LocalAddress,OwningProcess)
$prod=(Get-FileHash -Algorithm SHA256 -LiteralPath 'D:\ModelMirrors\bin\ModelMirrors.exe').Hash.ToLower()
if($remaining.Count -ne 0 -or $listeners.Count -ne 0){throw 'owned oracle did not cleanly stop'}
if($prod -ne '5bfb5248a7ab74bfbe6c86361146daa20b0e5e864699c820269279747ef81fd4'){throw 'production binary changed independently'}
[ordered]@{status='owned-rc12-oracle-stopped';pid=$state.pid;sourceRevision=$state.sourceRevision;binarySha256=$state.binarySha256;ownedModelChildrenBeforeStop=0;ownedConsoleChildrenBeforeStop=$children.Count;ownedConsoleChildrenAfterStop=$consoleRemaining.Count;ownedRemaining=$remaining;ownedListeners=$listeners;productionBinarySha256=$prod;productionStatus=(Get-Service ModelMirrors).Status.ToString();productionModified=$false}|ConvertTo-Json -Depth 6
