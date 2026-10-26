$ErrorActionPreference='Continue'
$stage='D:\ModelMirrors\staging\windows-fix-20261026-81b1f76'
Set-Location -LiteralPath $stage
$env:CC='D:/Programs/Perl/c/bin/gcc.exe'
$env:OSSL_INC='D:/Programs/msys2/ucrt64/include'
$env:OSSL_LIB='D:/Programs/msys2/ucrt64/lib'
$env:TEMP='D:\ModelMirrors\tmp\'
$env:TMP=$env:TEMP
$env:TMPDIR=$env:TEMP
$env:PATH='C:\Users\win10\.elan\toolchains\leanprover--lean4---v4.33.0\bin;D:\Programs\Perl\c\bin;'+$env:PATH
& lake.exe build model_interface_gen model_interface_spec trace_generation_transport_repro_spec apalache_cli_spec *> "$stage\build-fixes.log"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& "$stage\.lake\build\bin\model_interface_spec.exe" *> "$stage\model-interface-fixes.log"
$modelExit=$LASTEXITCODE
Get-Content -LiteralPath "$stage\model-interface-fixes.log"
if ($modelExit -ne 0) { exit $modelExit }
Remove-Item Env:APALACHE_MC -ErrorAction SilentlyContinue
& "$stage\.lake\build\bin\apalache_cli_spec.exe" *> "$stage\apalache-cli-fixes.log"
$cliExit=$LASTEXITCODE
Get-Content -LiteralPath "$stage\apalache-cli-fixes.log"
exit $cliExit
