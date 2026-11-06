$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false)
$s='D:\ModelMirrors\staging\qualification-rc7-20261105'
$processes=Get-CimInstance Win32_Process
$processes | Where-Object { $_.ExecutablePath -like ($s+'\*') -or $_.Name -in @('lake.exe','lean.exe','leanc.exe','clang.exe','gcc.exe','java.exe','cmake.exe') } | Select-Object ProcessId,ParentProcessId,Name,CreationDate
Get-Content -LiteralPath ($s+'\logs\20261106-full-lake-test.log') -Tail 20
