$ErrorActionPreference = 'Stop'
$all = @(Get-CimInstance Win32_Process)
$known = @(46680,52548,38480,54880)
$parents = @($all | Where-Object { $_.ProcessId -in $known -and $_.Name -eq 'bash.exe' -and $_.CommandLine -match '/d/Desktop/Workspaces/Mirrors-client-fixes-20261015/download-toolchains\.sh' })
$children = @($all | Where-Object { $_.Name -eq 'curl.exe' -and $_.ParentProcessId -in $known -and $_.CommandLine -match 'downloads\.haskell\.org/.+ghc/9\.14\.1/ghc-9\.14\.1-x86_64-deb11-linux\.tar\.xz' })
if ($children.Count -gt 1) { throw 'Ambiguous owned curl' }
$record = @{previousVerifiedParents=$known; remainingParents=@($parents | Select-Object ProcessId,ParentProcessId,CommandLine); children=@($children | Select-Object ProcessId,ParentProcessId,CommandLine); preservePartial=$true}
foreach ($parent in $parents) { Stop-Process -Id $parent.ProcessId -Force -ErrorAction SilentlyContinue }
foreach ($child in $children) { Stop-Process -Id $child.ProcessId -Force -ErrorAction SilentlyContinue }
$record | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 D:/Desktop/Workspaces/Mirrors-client-fixes-20261015/tool-download-stop.json
$record | ConvertTo-Json -Depth 5
