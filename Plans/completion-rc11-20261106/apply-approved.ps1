$ErrorActionPreference='Stop'
$script='D:\ModelMirrors\staging\completion-rc11-20261106\deploy-windows.ps1'
if((Get-FileHash -Algorithm SHA256 -LiteralPath $script).Hash.ToLower() -ne 'dddb56794c209ce3edc1c35061aafd10e37141ff875801a1095ec787c4ad193d'){throw 'reviewed deployment script differs'}
& $script -Apply
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
