$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false)
$Stage='D:/ModelMirrors/staging/s3-windows-20261030-d737aa0'
$source=Join-Path $Stage 'mirrors-d737aa0'
$logs=Join-Path $Stage 'logs'
$leanbin='C:\Users\win10\.elan\toolchains\leanprover--lean4---v4.33.0\bin'
$tmp='D:\ModelMirrors\tmp\s3-windows-20261030'
$env:CC='D:/Programs/Perl/c/bin/gcc.exe'
$env:OSSL_INC='D:/Programs/msys2/ucrt64/include'
$env:OSSL_LIB='D:/Programs/msys2/ucrt64/lib'
$env:TEMP=$tmp; $env:TMP=$tmp; $env:TMPDIR=$tmp
$env:PATH="D:\Programs\msys2\ucrt64\bin;$leanbin;D:\Programs\Perl\c\bin;"+$env:PATH
foreach($name in @('APALACHE_MC','APALACHE_JAR','TLA2TOOLS_JAR')){Remove-Item -LiteralPath ("Env:"+$name) -ErrorAction SilentlyContinue}
function Sha([string]$p){ if(Test-Path -LiteralPath $p){ (Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToLower() } else { $null } }
$initial=Join-Path $logs 'transport_spec.log'
$retained=Join-Path $logs 'transport_spec-initial-failure.log'
$initialInfo=[ordered]@{log='logs/transport_spec-initial-failure.log';bytes=(Get-Item -LiteralPath $initial).Length;sha256=(Sha $initial);cause='OpenSSL CLI resolution: the prepared PATH put a non-conforming openssl ahead of the OpenSSL 3 CLI, so throwaway PKI signing failed; corrected by prepending the OpenSSL 3.5.0 msys2 ucrt64 bin directory'}
Copy-Item -LiteralPath $initial -Destination $retained
$whereOpen=((& where.exe openssl 2>&1 | Out-String).Trim())
$exe=Join-Path $source '.lake/build/bin/transport_spec.exe'
$log=Join-Path $logs 'transport_spec.log'
$s=(Get-Date)
$line='"'+$exe+'" > "'+$log+'" 2>&1'
Push-Location -LiteralPath $source
try { & cmd.exe /d /s /c $line; $code=$LASTEXITCODE } finally { Pop-Location }
$f=(Get-Date)
$entry=[ordered]@{gate='transport_spec';command='.lake/build/bin/transport_spec.exe';cwd=$source;exit=$code;startedUtc=$s.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ');finishedUtc=$f.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ');seconds=[math]::Round(($f-$s).TotalSeconds,1);log='logs/transport_spec.log';logBytes=(Get-Item -LiteralPath $log).Length;logSha256=(Sha $log);retry=$true;initialAttempt=$initialInfo;opensslCli=$whereOpen}
$gates=@(Get-Content -Raw -LiteralPath (Join-Path $Stage 'gates.json') | ConvertFrom-Json)
$out=@()
foreach($g in $gates){ if($g.gate -eq 'transport_spec'){ $out += $entry } else { $out += $g } }
$out | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $Stage 'gates.json') -Encoding UTF8
$env2=[ordered]@{schema='mirrors.s3.windows-gate-retry/v1';gate='transport_spec';initialAttempt=$initialInfo;correctedPathPrepend='D:\Programs\msys2\ucrt64\bin';opensslCliResolved=$whereOpen;exit=$code;logSha256=(Sha $log)}
$env2 | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $Stage 'transport-retry.json') -Encoding UTF8
Write-Output ("TRANSPORT EXIT " + $code)
Write-Output ("OPENSSL " + $whereOpen)
Get-Content -LiteralPath $log -Tail 8
