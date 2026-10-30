$ErrorActionPreference='Stop'
$Stage='D:/ModelMirrors/staging/s3-windows-20261030-d737aa0'
$source=Join-Path $Stage 'mirrors-d737aa0'
$src='D:/ModelMirrors/releases/20261029-completion-7e9a27d/source/.lake/packages/batteries'
$destDir=Join-Path $source '.lake/packages'
$dest=Join-Path $destDir 'batteries'
if(Test-Path -LiteralPath $dest){throw 'batteries destination already exists'}
New-Item -ItemType Directory -Force -Path $destDir | Out-Null
Copy-Item -LiteralPath $src -Destination $dest -Recurse
$files=Get-ChildItem -LiteralPath $dest -Recurse -File
$rel=[string[]]@($files | ForEach-Object { $_.FullName.Substring($dest.Length+1).Replace('\','/') })
$byRel=@{}
foreach($f in $files){ $byRel[$f.FullName.Substring($dest.Length+1).Replace('\','/')]=$f }
[Array]::Sort($rel,[System.StringComparer]::Ordinal)
$sb=New-Object System.Text.StringBuilder
foreach($p in $rel){ $h=(Get-FileHash -Algorithm SHA256 -LiteralPath $byRel[$p].FullName).Hash.ToLower(); [void]$sb.Append("$p`t$($byRel[$p].Length)`t$h`n") }
$shaObj=[System.Security.Cryptography.SHA256]::Create()
$digest=([BitConverter]::ToString($shaObj.ComputeHash((New-Object System.Text.UTF8Encoding($false)).GetBytes($sb.ToString())))).Replace('-','').ToLower()
$manifest=ConvertFrom-Json (Get-Content -Raw -LiteralPath (Join-Path $source 'lake-manifest.json'))
$batteries=@($manifest.packages | Where-Object { $_.name -eq 'batteries' })[0]
$record=[ordered]@{schema='mirrors.s3.windows-offline-dependency/v1';name='batteries';retainedSourcePath=$src;capturedPath=$dest;manifestRev=$batteries.rev;manifestInputRev=$batteries.inputRev;fileCount=$rel.Count;contentTreeDigest=$digest;lakefileSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $dest 'lakefile.toml')).Hash.ToLower();leanToolchain=(Get-Content -Raw -LiteralPath (Join-Path $dest 'lean-toolchain')).Trim();note='offline copy of the batteries package used by the 2026-10-29 staging tree; bound by content digest because the copy has no VCS metadata'}
$record | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $Stage 'offline-dependency.json') -Encoding UTF8
Write-Output ("DEPENDENCY COPIED " + $rel.Count + " " + $digest + " rev=" + $batteries.rev)
