$ErrorActionPreference='Continue'
$stage='D:\ModelMirrors\staging\windows-fix-20261026-81b1f76'
Set-Location -LiteralPath $stage
$env:TEMP='D:\ModelMirrors\tmp\'
$env:TMP=$env:TEMP
$env:TMPDIR=$env:TEMP
for ($i=1; $i -le 3; $i++) {
  & "$stage\.lake\build\bin\model_interface_spec.exe" *> "$stage\model-interface-fixes-repeat-$i.log"
  if ($LASTEXITCODE -ne 0) {
    Get-Content -LiteralPath "$stage\model-interface-fixes-repeat-$i.log"
    exit $LASTEXITCODE
  }
  Write-Output "Windows model_interface_spec run ${i}: PASS"
}
