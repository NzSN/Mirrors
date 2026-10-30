param([string]$Stage='D:/ModelMirrors/staging/s3-windows-20261030-d737aa0',[string]$ExpectedArchiveSha,[string]$ExpectedTreeDigest,[int]$ExpectedFileCount)
$ErrorActionPreference='Stop'
$archive=Join-Path $Stage 'mirrors-v0.2.0-rc.1-source.tar.gz'
$manifestPath=Join-Path $Stage 'mirrors-v0.2.0-rc.1-source-manifest.json'
$source=Join-Path $Stage 'mirrors-d737aa0'
$sha=(Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash.ToLower()
if($sha -ne $ExpectedArchiveSha){throw "archive transfer hash differs: $sha"}
if(-not (Test-Path -LiteralPath $source)){
 & "$env:SystemRoot\System32\tar.exe" -xzf $archive -C $Stage
 if($LASTEXITCODE -ne 0){throw "tar extraction failed: $LASTEXITCODE"}
}
if(-not (Test-Path -LiteralPath $source)){throw 'extracted source directory missing'}
if(Test-Path -LiteralPath (Join-Path $source '.git')){throw 'extracted source unexpectedly contains .git'}
$files=Get-ChildItem -LiteralPath $source -Recurse -File
$rel=[string[]]@($files | ForEach-Object { $_.FullName.Substring($source.Length+1).Replace('\','/') })
$byRel=@{}
foreach($f in $files){ $byRel[$f.FullName.Substring($source.Length+1).Replace('\','/')]=$f }
[Array]::Sort($rel,[System.StringComparer]::Ordinal)
$sb=New-Object System.Text.StringBuilder
foreach($p in $rel){ $h=(Get-FileHash -Algorithm SHA256 -LiteralPath $byRel[$p].FullName).Hash.ToLower(); [void]$sb.Append("$p`t$($byRel[$p].Length)`t$h`n") }
$utf8=New-Object System.Text.UTF8Encoding($false)
$bytes=$utf8.GetBytes($sb.ToString())
$shaObj=[System.Security.Cryptography.SHA256]::Create()
$treeDigest=([BitConverter]::ToString($shaObj.ComputeHash($bytes))).Replace('-','').ToLower()
if($rel.Count -ne $ExpectedFileCount){throw "file count differs: $($rel.Count) != $ExpectedFileCount"}
if($treeDigest -ne $ExpectedTreeDigest){throw "content tree digest differs: $treeDigest"}
$version=(Get-Content -Raw -LiteralPath (Join-Path $source 'Shell/Version.lean'))
if($version -notmatch 'def version : String := "0\.2\.0-rc\.1"'){throw 'embedded version mismatch'}
$record=ConvertFrom-Json (Get-Content -Raw -LiteralPath $manifestPath)
if($record.contentTreeDigest -ne $ExpectedTreeDigest -or $record.archiveSha256 -ne $ExpectedArchiveSha){throw 'manifest self-check failed'}
[ordered]@{schema='mirrors.s3.windows-source-verification/v1';stagingDirectory=$Stage;archive=$record.archive;archiveSha256=$sha;archiveBytes=(Get-Item -LiteralPath $archive).Length;extractedDirectory=$source;fileCount=$rel.Count;contentTreeDigest=$treeDigest;embeddedVersion='0.2.0-rc.1';gitDirectoryPresent=$false;extractedAt=(Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $Stage 'source-verification.json') -Encoding UTF8
Write-Output "SOURCE VERIFIED $sha $treeDigest $($rel.Count)"
