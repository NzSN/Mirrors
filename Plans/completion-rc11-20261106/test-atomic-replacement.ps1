$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false)
$root='D:\ModelMirrors\staging\completion-rc11-20261106\atomic-replacement-probe'
if(Test-Path -LiteralPath $root){throw 'retain previous probe'}
New-Item -ItemType Directory -Path $root|Out-Null
$old=$root+'\active';$new=$root+'\candidate';$backup=$root+'\previous'
[IO.File]::WriteAllText($old,'old');[IO.File]::WriteAllText($new,'new')
[IO.File]::Replace($new,$old,$backup)
if([IO.File]::ReadAllText($old) -ne 'new' -or [IO.File]::ReadAllText($backup) -ne 'old' -or (Test-Path -LiteralPath $new)){throw 'replacement invariant failed'}
$restore=$root+'\restore';[IO.File]::Copy($backup,$restore)
[IO.File]::Replace($restore,$old,($root+'\rejected'))
if([IO.File]::ReadAllText($old) -ne 'old' -or [IO.File]::ReadAllText($root+'\rejected') -ne 'new'){throw 'rollback invariant failed'}
Write-Output 'ATOMIC REPLACEMENT AND ROLLBACK WITH EXPLICIT BACKUP PATHS PASSED'
