@echo off
call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat" >nul
if errorlevel 1 exit /b 1
set TEMP=C:\Users\ayden\Desktop\Workspace\MirrorsRemote\dpm-20261004\normal-v3\temp
set TMP=C:\Users\ayden\Desktop\Workspace\MirrorsRemote\dpm-20261004\normal-v3\temp
cd /d "C:\Users\ayden\Desktop\Workspace\MirrorsRemote\dpm-20261004\normal-v3\build"
ml64.exe /nologo /c /Fo writers.obj "C:\Users\ayden\Desktop\Workspace\MirrorsRemote\dpm-20261004\normal-v3\source\tests\mbt\runtime_writers.asm"
if errorlevel 1 exit /b 1
cl.exe /nologo /std:c++20 /O2 /W4 /EHsc /MD /DWIN32_LEAN_AND_MEAN /DNOMINMAX /DWRITESENTRY_MBT_PHASES /I "C:\Users\ayden\Desktop\Workspace\MirrorsRemote\dpm-20261004\normal-v3\source\include" /I "C:\Users\ayden\Desktop\Workspace\MirrorsRemote\dpm-20261004\normal-v3\source\src" /I "C:\Users\ayden\Desktop\Workspace\MirrorsRemote\dpm-20261004\normal-v3\source\tests\mbt" /I "C:\Users\ayden\Desktop\Workspace\MirrorsRemote\dpm-20261004\normal-v3\source\jsoninclude" "C:\Users\ayden\Desktop\Workspace\MirrorsRemote\dpm-20261004\normal-v3\source\tests\mbt\dpm_worker.cpp" "C:\Users\ayden\Desktop\Workspace\MirrorsRemote\dpm-20261004\normal-v3\source\src\self_watch.cpp" "C:\Users\ayden\Desktop\Workspace\MirrorsRemote\dpm-20261004\normal-v3\source\src\veh.cpp" writers.obj bcrypt.lib /Fe:dpm_native_worker.exe
exit /b %errorlevel%
