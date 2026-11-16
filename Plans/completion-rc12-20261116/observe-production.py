"""Read-only production baseline and public certificate renewal prerequisites."""
from common import *


def main():
    script = r'''
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
$sha=[Security.Cryptography.SHA256]::Create()
$certificates=@()
foreach($name in @('ca.crt','server.crt','client.crt')) {
 $path='D:\ModelMirrors\certs\'+$name
 if(Test-Path -LiteralPath $path) {
  $cert=New-Object Security.Cryptography.X509Certificates.X509Certificate2($path)
  $san=@($cert.Extensions | Where-Object {$_.Oid.Value -eq '2.5.29.17'} | ForEach-Object {$_.Format($false)})
  $certificates+=@(@{name=$name;subject=$cert.Subject;issuer=$cert.Issuer;sha256=([BitConverter]::ToString($sha.ComputeHash($cert.RawData))).Replace('-','').ToLower();notBeforeUtc=$cert.NotBefore.ToUniversalTime().ToString('o');notAfterUtc=$cert.NotAfter.ToUniversalTime().ToString('o');validNow=($cert.NotBefore.ToUniversalTime() -le [DateTime]::UtcNow -and $cert.NotAfter.ToUniversalTime() -gt [DateTime]::UtcNow);subjectAlternativeNames=$san})
 }
}
$values=Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\ModelMirrors\Parameters'
$configuration=@{}
foreach($name in @('Application','AppDirectory','AppParameters','AppEnvironmentExtra','AppEnvironment','AppStdout','AppStderr')) {
 if($null -ne $values.$name){$raw=$values.$name|ConvertTo-Json -Compress;$configuration[$name]=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($raw)))).Replace('-','').ToLower()}
}
$binary=(Get-FileHash -Algorithm SHA256 -LiteralPath 'D:\ModelMirrors\bin\ModelMirrors.exe').Hash.ToLower()
if($binary -ne '5bfb5248a7ab74bfbe6c86361146daa20b0e5e864699c820269279747ef81fd4'){throw 'production baseline changed'}
$service=Get-CimInstance Win32_Service -Filter "Name='ModelMirrors'"
[ordered]@{observedAt=[DateTime]::UtcNow.ToString('o');productionBinarySha256=$binary;service=@{name=$service.Name;state=$service.State;startMode=$service.StartMode;pid=$service.ProcessId};configurationHashes=$configuration;publicCertificates=$certificates;caSigningKeyPresent=(Test-Path -LiteralPath 'D:\ModelMirrors\certs\ca.key' -PathType Leaf);privateKeyBytesReadOrExported=$false;productionModified=$false}|ConvertTo-Json -Depth 7
'''
    value = json.loads(remote('production-renewal-readonly-observation', script))
    write(PLAN / 'production-renewal-prerequisites.json', value)
    print(json.dumps(value, indent=2), flush=True)


if __name__ == '__main__':
    main()
