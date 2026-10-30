$Stage='D:/ModelMirrors/staging/s3-windows-20261030-d737aa0'
foreach($p in @((Join-Path $Stage 'candidate-v0.2.0-rc.1'),(Join-Path $Stage 'mirrors-v0.2.0-rc.1-windows-x86_64.zip'),(Join-Path $Stage 'mirrors-v0.2.0-rc.1-windows-x86_64-repeat.zip'))){
  if(Test-Path -LiteralPath $p){ Remove-Item -LiteralPath $p -Recurse -Force }
}
Write-Output CLEANED
