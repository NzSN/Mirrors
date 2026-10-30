$ErrorActionPreference='Stop'
$Stage='D:/ModelMirrors/staging/s3-windows-20261030-d737aa0'
$source=Join-Path $Stage 'mirrors-d737aa0'
$manifest=Get-Content -Raw -LiteralPath (Join-Path $Stage 'mirrors-v0.2.0-rc.1-source-manifest.json') | ConvertFrom-Json
function Sha([string]$p){ (Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToLower() }
$bad=@()
$lines=New-Object System.Text.StringBuilder
foreach($entry in $manifest.files){
  $p=Join-Path $source $entry.path
  if(-not (Test-Path -LiteralPath $p)){ $bad += ('missing '+$entry.path); continue }
  $h=Sha $p; $len=(Get-Item -LiteralPath $p).Length
  if($len -ne $entry.bytes -or $h -ne $entry.sha256){ $bad += ('changed '+$entry.path) }
}
$files=Get-ChildItem -LiteralPath $source -Recurse -File
$extra=@($files | Where-Object { $rel=$_.FullName.Substring($source.Length+1).Replace('\','/'); -not ($rel.StartsWith('.lake/') -or $rel.StartsWith('.golden-build/')) })
$extraRel=@($extra | ForEach-Object { $_.FullName.Substring($source.Length+1).Replace('\','/') })
$known=@{}; foreach($e in $manifest.files){ $known[$e.path]=$true }
$extraOutsideLake=@($extraRel | Where-Object { -not $known.ContainsKey($_) })
$record=[ordered]@{schema='mirrors.s3.windows-post-build-source-check/v1';checkedFiles=$manifest.fileCount;changedOrMissing=@($bad);extraFilesOutsideLake=$extraOutsideLake;buildDirectoryEntries=($files.Count-$extra.Count);note='extracted source files rehashed after build, gates and packaging; .lake build/dependency outputs and .golden-build generated test outputs are expected additions and are excluded'}
$record | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $Stage 'post-source-check.json') -Encoding UTF8
Write-Output ("POST_SOURCE_CHECK changed=" + $bad.Count + " extraOutsideLake=" + $extraOutsideLake.Count + " checked=" + $manifest.fileCount)
if($bad.Count -gt 0){ $bad | Select-Object -First 10 | ForEach-Object { Write-Output $_ } }
if($extraOutsideLake.Count -gt 0){ $extraOutsideLake | Select-Object -First 10 | ForEach-Object { Write-Output $_ } }
exit $(if($bad.Count -gt 0 -or $extraOutsideLake.Count -gt 0){1}else{0})
