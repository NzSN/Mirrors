$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false)
$s='D:\ModelMirrors\staging\qualification-rc7-20261105'
$dst='D:\ModelMirrors\staging\windows-fixes-20261106\python312-completion'
if(Test-Path -LiteralPath $dst){throw 'retain existing Python runtime'}
Copy-Item -Recurse -LiteralPath ($s+'\python312') -Destination $dst
Move-Item -LiteralPath ($dst+'\python312._pth') -Destination ($dst+'\python312._pth.original')
Copy-Item -LiteralPath ($dst+'\python.exe') -Destination ($dst+'\python3.exe')
$wheelRoot=$dst+'\wheels'
New-Item -ItemType Directory -Path $wheelRoot | Out-Null
& 'C:\Windows\System32\tar.exe' -xf ($s+'\20261106-iteration-pure-wheels.tar') -C $wheelRoot
if($LASTEXITCODE -ne 0){throw 'wheel carrier extraction failed'}
$env:COMPLETION_PYTHON_ROOT=$dst
& 'D:\Programs\Python310\python.exe' ($s+'\20261106-iteration-install-wheels.py')
if($LASTEXITCODE -ne 0){throw 'wheel installation failed'}
& ($dst+'\python3.exe') -c 'import sys,jsonschema,attr,pyrsistent; print(sys.version); print(sys.prefix); print(jsonschema.__file__); print(pyrsistent.__file__)'
if($LASTEXITCODE -ne 0){throw 'prepared runtime import check failed'}
