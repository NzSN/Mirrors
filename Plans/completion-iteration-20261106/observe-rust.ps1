$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false)
Get-Command cargo,rustc -ErrorAction SilentlyContinue|Select-Object Name,Source
Get-ChildItem -LiteralPath 'D:\ModelMirrors\staging\qualification-rc7-20261105\MirrorRust' -Name
