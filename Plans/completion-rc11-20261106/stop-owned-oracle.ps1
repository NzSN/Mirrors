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
 if($children.Count -ne 0){throw 'owned model children remain before oracle stop'}
 Stop-Process -Id $state.pid -ErrorAction Stop
}
Start-Sleep -Milliseconds 600
$remaining=@(Get-CimInstance Win32_Process|Where-Object{$_.ExecutablePath -eq $state.executable}|Select-Object ProcessId,ExecutablePath)
$listeners=@(Get-NetTCPConnection -State Listen -LocalPort 19099 -ErrorAction SilentlyContinue|Select-Object LocalAddress,OwningProcess)
$prod=(Get-FileHash -Algorithm SHA256 -LiteralPath 'D:\ModelMirrors\bin\ModelMirrors.exe').Hash.ToLower()
if($remaining.Count -ne 0 -or $listeners.Count -ne 0){throw 'owned oracle did not cleanly stop'}
if($prod -ne '8173ddea65f78a88b1a303f8a233dd7113b28e7dc8aefd8916a5add25a3687cc'){throw 'production binary changed independently'}
[ordered]@{status='owned-rc11-oracle-stopped';pid=$state.pid;sourceRevision=$state.sourceRevision;binarySha256=$state.binarySha256;ownedModelChildrenBeforeStop=0;ownedRemaining=$remaining;ownedListeners=$listeners;productionBinarySha256=$prod;productionStatus=(Get-Service ModelMirrors).Status.ToString();productionModified=$false}|ConvertTo-Json -Depth 6
