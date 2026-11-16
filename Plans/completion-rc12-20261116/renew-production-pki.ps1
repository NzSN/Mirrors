$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
$stage='D:\ModelMirrors\staging\completion-rc12-20261116'
$work=$stage+'\production-renewal'
$active='D:\ModelMirrors\certs'
$openssl='D:\Programs\msys2\ucrt64\bin\openssl.exe'
$expectedOld='5bfb5248a7ab74bfbe6c86361146daa20b0e5e864699c820269279747ef81fd4'
$expectedNew='5ebfb99399df6006b2dcae81a64525421ca0f4490ac19dcd3a9ed8f51676d5e9'
$candidate=$stage+'\mirrors-v0.2.0-rc.12-windows-x86_64\bin\ModelMirrors.exe'
function Hash([string]$path){return (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLower()}
function Save([string]$path,$value){if(Test-Path -LiteralPath $path){throw 'retain prior receipt'};[IO.File]::WriteAllText($path,($value|ConvertTo-Json -Depth 12),(New-Object Text.UTF8Encoding($false)))}
function Configuration {
 $values=Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\ModelMirrors\Parameters'
 $sha=[Security.Cryptography.SHA256]::Create();$result=[ordered]@{}
 foreach($name in @('Application','AppDirectory','AppParameters','AppEnvironmentExtra','AppEnvironment','AppStdout','AppStderr')){if($null -ne $values.$name){$raw=$values.$name|ConvertTo-Json -Compress;$result[$name]=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($raw)))).Replace('-','').ToLower()}}
 return $result
}
function Certificate([string]$path) {
 $cert=New-Object Security.Cryptography.X509Certificates.X509Certificate2($path)
 $sha=[Security.Cryptography.SHA256]::Create()
 return [ordered]@{subject=$cert.Subject;issuer=$cert.Issuer;sha256=([BitConverter]::ToString($sha.ComputeHash($cert.RawData))).Replace('-','').ToLower();notBeforeUtc=$cert.NotBefore.ToUniversalTime().ToString('o');notAfterUtc=$cert.NotAfter.ToUniversalTime().ToString('o');validNow=($cert.NotBefore.ToUniversalTime() -le [DateTime]::UtcNow -and $cert.NotAfter.ToUniversalTime() -gt [DateTime]::UtcNow)}
}
function OpenSsl([string]$label,[string[]]$arguments) {
 $out=$work+'\'+$label+'.stdout';$err=$work+'\'+$label+'.stderr'
 if((Test-Path -LiteralPath $out) -or (Test-Path -LiteralPath $err)){throw 'retain OpenSSL attempt'}
 $line='"'+$openssl+'" '+(($arguments|ForEach-Object{'"'+$_+'"'}) -join ' ')+' < NUL > "'+$out+'" 2> "'+$err+'"'
 & cmd.exe /d /s /c $line
 if($LASTEXITCODE -ne 0){throw ('OpenSSL failed: '+$label+'; private stage logs retained')}
}
function Serial {
 $bytes=New-Object byte[] 16
 $rng=[Security.Cryptography.RandomNumberGenerator]::Create();$rng.GetBytes($bytes);$rng.Dispose()
 $bytes[0]=$bytes[0] -band 127
 return '0x'+([BitConverter]::ToString($bytes)).Replace('-','')
}
if($env:COMPUTERNAME -ne 'DESKTOP-6DKB5JD'){throw 'approved host differs'}
if(Test-Path -LiteralPath $work){throw 'retain existing production-renewal stage'}
if((Hash 'D:\ModelMirrors\bin\ModelMirrors.exe') -ne $expectedOld -or (Hash $candidate) -ne $expectedNew){throw 'old/candidate binary identity differs'}
$values=Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\ModelMirrors\Parameters'
if($values.AppParameters -match '--model-interface-allow-client'){throw 'explicit client allowlist migration requires a bound identity mapping'}
$known=Get-Content -Raw -LiteralPath ($stage+'\production-renewal-prerequisites.json')|ConvertFrom-Json
$config=Configuration
foreach($property in $known.configurationHashes.PSObject.Properties){if($config[$property.Name] -ne $property.Value){throw 'service configuration changed before renewal'}}
New-Item -ItemType Directory -Path $work|Out-Null
$acl=New-Object Security.AccessControl.DirectorySecurity
$acl.SetAccessRuleProtection($true,$false)
foreach($sid in @([Security.Principal.WindowsIdentity]::GetCurrent().User.Value,'S-1-5-18','S-1-5-32-544')) {
 $rule=New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier($sid)),'FullControl','ContainerInherit,ObjectInherit','None','Allow');$acl.AddAccessRule($rule)
}
Set-Acl -LiteralPath $work -AclObject $acl
New-Item -ItemType Directory -Path ($work+'\old-certificates'),($work+'\rollback')|Out-Null
$old=[ordered]@{};$privateKeys=[ordered]@{};$keyAcls=[ordered]@{};$certificateFiles=[ordered]@{};$certificateAcls=[ordered]@{}
foreach($name in @('ca','server','client')) {
 $old[$name]=Certificate ($active+'\'+$name+'.crt')
 $selected=@($known.publicCertificates|Where-Object{$_.name -eq $name+'.crt'})
 if($selected.Count -ne 1 -or $old[$name].sha256 -ne $selected[0].sha256){throw 'production certificate changed before renewal'}
 $privateKeys[$name]=Hash ($active+'\'+$name+'.key')
 $keyAcls[$name]=(Get-Acl -LiteralPath ($active+'\'+$name+'.key')).Sddl
 $certificateFiles[$name]=Hash ($active+'\'+$name+'.crt')
 $certificateAcls[$name]=(Get-Acl -LiteralPath ($active+'\'+$name+'.crt')).Sddl
 Copy-Item -LiteralPath ($active+'\'+$name+'.crt') -Destination ($work+'\old-certificates\'+$name+'.crt')
}
if($old.ca.subject -ne 'CN=ModelMirrors CA' -or $old.server.subject -ne 'CN=192.168.150.219' -or $old.client.subject -ne 'CN=modelmirrors-client'){throw 'production subjects differ from reviewed identities'}
$dlls=[ordered]@{}
foreach($name in @('libcrypto-3-x64.dll','libssl-3-x64.dll','zlib1.dll')) {
 $dlls[$name]=Hash ('D:\ModelMirrors\bin\'+$name)
 if($dlls[$name] -ne (Hash ((Split-Path $candidate)+'\'+$name))){throw 'DLL change is not selected'}
}
Copy-Item -LiteralPath 'D:\ModelMirrors\bin\ModelMirrors.exe' -Destination ($work+'\rollback\ModelMirrors.exe')
if((Hash ($work+'\rollback\ModelMirrors.exe')) -ne $expectedOld){throw 'rollback copy differs'}
Save ($work+'\private-baseline.json') ([ordered]@{oldBinarySha256=$expectedOld;newBinarySha256=$expectedNew;privateKeyHashes=$privateKeys;privateKeyAcls=$keyAcls;certificateFileHashes=$certificateFiles;certificateAcls=$certificateAcls;configurationHashes=$config;dllHashes=$dlls})
$configText=@'
[req]
distinguished_name=dn
prompt=no
[dn]
CN=ModelMirrors CA
[ca]
basicConstraints=critical,CA:TRUE
keyUsage=critical,keyCertSign,cRLSign
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid:always
[server]
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=IP:192.168.150.219
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
[client]
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=clientAuth
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
'@
[IO.File]::WriteAllText(($work+'\openssl.cnf'),$configText,(New-Object Text.UTF8Encoding($false)))
$env:OPENSSL_CONF=$work+'\openssl.cnf'
OpenSsl 'ca-renew' @('req','-x509','-new','-sha256','-days','90','-key',($active+'\ca.key'),'-subj','/CN=ModelMirrors CA','-set_serial',(Serial),'-extensions','ca','-out',($work+'\ca.crt'))
foreach($name in @('server','client')) {
 $subject=if($name -eq 'server'){'/CN=192.168.150.219'}else{'/CN=modelmirrors-client'}
 OpenSsl ($name+'-csr') @('req','-new','-sha256','-key',($active+'\'+$name+'.key'),'-subj',$subject,'-out',($work+'\'+$name+'.csr'))
 OpenSsl ($name+'-renew') @('x509','-req','-sha256','-days','90','-in',($work+'\'+$name+'.csr'),'-CA',($work+'\ca.crt'),'-CAkey',($active+'\ca.key'),'-set_serial',(Serial),'-extfile',($work+'\openssl.cnf'),'-extensions',$name,'-out',($work+'\'+$name+'.crt'))
}
OpenSsl 'verify-ca' @('verify','-CAfile',($work+'\ca.crt'),($work+'\ca.crt'))
OpenSsl 'verify-server' @('verify','-purpose','sslserver','-verify_ip','192.168.150.219','-CAfile',($work+'\ca.crt'),($work+'\server.crt'))
OpenSsl 'verify-client' @('verify','-purpose','sslclient','-CAfile',($work+'\ca.crt'),($work+'\client.crt'))
$renewed=[ordered]@{};$publicKeys=[ordered]@{}
foreach($name in @('ca','server','client')) {
 OpenSsl ($name+'-key-public') @('pkey','-in',($active+'\'+$name+'.key'),'-pubout','-outform','DER','-out',($work+'\'+$name+'-key-public.der'))
 foreach($version in @('old','new')) {
  $cert=if($version -eq 'old'){$active+'\'+$name+'.crt'}else{$work+'\'+$name+'.crt'}
  OpenSsl ($name+'-'+$version+'-cert-public') @('x509','-in',$cert,'-pubkey','-noout','-out',($work+'\'+$name+'-'+$version+'-public.pem'))
  OpenSsl ($name+'-'+$version+'-cert-der') @('pkey','-pubin','-in',($work+'\'+$name+'-'+$version+'-public.pem'),'-outform','DER','-out',($work+'\'+$name+'-'+$version+'-public.der'))
  if((Hash ($work+'\'+$name+'-'+$version+'-public.der')) -ne (Hash ($work+'\'+$name+'-key-public.der'))){throw 'old/new certificate does not preserve key pairing'}
 }
 if((Hash ($active+'\'+$name+'.key')) -ne $privateKeys[$name] -or (Get-Acl -LiteralPath ($active+'\'+$name+'.key')).Sddl -ne $keyAcls[$name]){throw 'private key or ACL changed'}
 if((Hash ($active+'\'+$name+'.crt')) -ne $certificateFiles[$name]){throw 'production certificate changed during preparation'}
 $renewed[$name]=Certificate ($work+'\'+$name+'.crt')
 if(-not $renewed[$name].validNow -or $renewed[$name].subject -ne $old[$name].subject){throw 'renewed certificate subject/validity differs'}
 $publicKeys[$name]=Hash ($work+'\'+$name+'-key-public.der')
}
$record=[ordered]@{schema='mirrors.rc12.production-pki-renewal/v1';status='renewed-material-prepared-and-verified';createdAtUtc=[DateTime]::UtcNow.ToString('o');oldCertificates=$old;renewedCertificates=$renewed;publicKeySha256=$publicKeys;existingKeysAndAclsPreserved=$true;privateKeysExported=$false;validityDays=90;serverIpSan='192.168.150.219';caChainAndPurposeChecksPassed=$true;configurationHashes=$config;dllHashes=$dlls;oldBinarySha256=$expectedOld;candidateBinarySha256=$expectedNew;rollbackRetained=$true;productionModified=$false;externalConsumerAcknowledgementsReceived=$false}
Save ($work+'\renewed-public.json') $record
$record|ConvertTo-Json -Depth 12
