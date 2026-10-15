$ErrorActionPreference = 'Stop'
$all = @(Get-CimInstance Win32_Process)
$parents = @($all | Where-Object { $_.Name -eq 'bash.exe' -and $_.CommandLine -match 'bash(?:\.exe)?"? /d/Desktop/Workspaces/Mirrors-client-fixes-20261015/download-toolchains\.sh(?:"?)$' })
if ($parents.Count -lt 1) { throw 'No verified task-owned download shell' }
$children = @($all | Where-Object { $_.Name -eq 'curl.exe' -and $_.ParentProcessId -in $parents.ProcessId -and $_.CommandLine -match 'downloads\.haskell\.org/.+ghc/9\.14\.1/ghc-9\.14\.1-x86_64-deb11-linux\.tar\.xz' })
if ($children.Count -ne 1) { $children | Select-Object ProcessId, CommandLine | ConvertTo-Json; throw 'Expected exactly one verified owned GHC curl' }
$record = @{parents=@($parents | Select-Object ProcessId,ParentProcessId,CommandLine); child=($children[0] | Select-Object ProcessId,ParentProcessId,CommandLine); preservePartial=$true}
foreach ($parent in ($parents | Sort-Object ParentProcessId -Descending)) { if (Get-Process -Id $parent.ProcessId -ErrorAction SilentlyContinue) { Stop-Process -Id $parent.ProcessId -Force } }
if (Get-Process -Id $children[0].ProcessId -ErrorAction SilentlyContinue) { Stop-Process -Id $children[0].ProcessId -Force }
$record | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 D:/Desktop/Workspaces/Mirrors-client-fixes-20261015/tool-download-stop.json
$record | ConvertTo-Json -Depth 5
