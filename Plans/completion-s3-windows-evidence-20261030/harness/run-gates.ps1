$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false)
$Stage='D:/ModelMirrors/staging/s3-windows-20261030-d737aa0'
$source=Join-Path $Stage 'mirrors-d737aa0'
$logs=Join-Path $Stage 'logs'
$first=Join-Path $logs 'first-pass'
New-Item -ItemType Directory -Force -Path $first | Out-Null
foreach($g in @('fixtures_replay','diff_cross','model_interface_spec','stdio_smoke','jobstore_spec','async_resource_spec','dpm_sync_spec')){
  $p=Join-Path $logs ($g+'.log')
  if(Test-Path -LiteralPath $p){ Move-Item -LiteralPath $p -Destination (Join-Path $first ($g+'.log')) -Force }
}
$leanbin='C:\Users\win10\.elan\toolchains\leanprover--lean4---v4.33.0\bin'
$tmp='D:\ModelMirrors\tmp\s3-windows-20261030'
$env:CC='D:/Programs/Perl/c/bin/gcc.exe'
$env:OSSL_INC='D:/Programs/msys2/ucrt64/include'
$env:OSSL_LIB='D:/Programs/msys2/ucrt64/lib'
$env:TEMP=$tmp; $env:TMP=$tmp; $env:TMPDIR=$tmp
$env:PATH="D:\Programs\msys2\ucrt64\bin;$leanbin;D:\Programs\Perl\c\bin;"+$env:PATH
foreach($name in @('APALACHE_MC','APALACHE_JAR','TLA2TOOLS_JAR')){Remove-Item -LiteralPath ("Env:"+$name) -ErrorAction SilentlyContinue}
function Sha([string]$p){ if(Test-Path -LiteralPath $p){ (Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToLower() } else { $null } }
$opensslCli=((& where.exe openssl 2>&1 | Out-String).Trim())
$records=@()
foreach($gate in @('fixtures_replay','diff_cross','model_interface_spec','stdio_smoke','transport_spec','jobstore_spec','async_resource_spec','dpm_sync_spec')){
  $exe=Join-Path $source ('.lake/build/bin/'+$gate+'.exe')
  $log=Join-Path $logs ($gate+'.log')
  $s=(Get-Date)
  $line='"'+$exe+'" > "'+$log+'" 2>&1'
  Push-Location -LiteralPath $source
  try { & cmd.exe /d /s /c $line; $code=$LASTEXITCODE } finally { Pop-Location }
  $f=(Get-Date)
  $records += [ordered]@{gate=$gate;command=('.lake/build/bin/'+$gate+'.exe');cwd=$source;exit=$code;startedUtc=$s.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ');finishedUtc=$f.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ');seconds=[math]::Round(($f-$s).TotalSeconds,1);log=('logs/'+$gate+'.log');logBytes=(Get-Item -LiteralPath $log).Length;logSha256=(Sha $log)}
  Write-Output ("GATE " + $gate + " EXIT " + $code)
}
$doc=[ordered]@{schema='mirrors.s3.windows-gates/v1';cwd=$source;environment=[ordered]@{pathPrepend='D:\Programs\msys2\ucrt64\bin;'+$leanbin+';D:\Programs\Perl\c\bin';opensslCli=$opensslCli;APALACHE_MC='unset';APALACHE_JAR='unset';TLA2TOOLS_JAR='unset'};gates=$records}
[IO.File]::WriteAllText((Join-Path $Stage 'gates.json'),($doc|ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($false)))
$failed=@($records | Where-Object { $_.exit -ne 0 }).Count
Write-Output ("GATES_FAILED " + $failed)
exit $(if($failed -gt 0){1}else{0})
