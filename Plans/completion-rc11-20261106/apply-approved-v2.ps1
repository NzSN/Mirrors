$ErrorActionPreference='Stop'
$script='D:\ModelMirrors\staging\completion-rc11-20261106\deploy-windows-v2.ps1'
if((Get-FileHash -Algorithm SHA256 -LiteralPath $script).Hash.ToLower() -ne '52c693fd6af143d6e374e31e77f6648a22633a293d0ed8c2db4a97ff1c5d0e23'){throw 'corrected deployment script differs'}
& $script -Apply
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
