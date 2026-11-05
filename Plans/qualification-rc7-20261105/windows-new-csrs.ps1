$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false)
$pki='D:\ModelMirrors\staging\qualification-rc7-20261105\private-pki'
if(Test-Path -LiteralPath $pki){throw 'retain previous credentials'}
New-Item -ItemType Directory -Path $pki | Out-Null
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
& icacls.exe $pki /inheritance:r /grant:r ('*'+$sid+':(OI)(CI)F') '*S-1-5-18:(OI)(CI)F' | Out-Null
if($LASTEXITCODE -ne 0){throw 'task credential ACL failed'}
$openssl='D:\Programs\msys2\ucrt64\bin\openssl.exe'
foreach($name in @('server','windows-client')) {
  $ErrorActionPreference='Continue'
  & $openssl req -newkey rsa:2048 -nodes -subj ('/CN=qualification-'+$name) -keyout (Join-Path $pki ($name+'.key')) -out (Join-Path $pki ($name+'.csr')) 2> (Join-Path $pki ($name+'-generation.log'))
  $code=$LASTEXITCODE
  $ErrorActionPreference='Stop'
  if($code -ne 0){throw ('CSR generation failed: '+$name)}
}
Write-Output 'NEW HOST-LOCAL PRIVATE KEYS AND PUBLIC CSRS PREPARED'
