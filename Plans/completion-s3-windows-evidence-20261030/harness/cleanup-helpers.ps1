$names=@('s3win-findzlib.ps1','s3win-findzlib2.ps1','s3win-parse.ps1','s3win-probe.ps1','s3win-probe2.ps1','s3win-probe3.ps1','s3win-tooltest.ps1','s3win-whichtools.sh')
foreach($n in $names){ $p=Join-Path 'C:\Users\win10' $n; if(Test-Path -LiteralPath $p){ Remove-Item -LiteralPath $p -Force } }
Write-Output ('REMAINING ' + @(Get-ChildItem 'C:\Users\win10' -Filter 's3win-*' -File).Count)
