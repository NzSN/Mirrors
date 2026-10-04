import subprocess
from pathlib import Path
base=['c++', '-std=c++23', '-pthread', '-g', '-O1', '-fno-omit-frame-pointer', '-I/home/nzsn/Repos/MirrorCPP/include', '-I/tmp/mic-mirrorcpp-build/_deps/nlohmann_json-src/include', '/home/nzsn/Repos/MirrorCPP/src/schedule.cpp', '/home/nzsn/Repos/MirrorCPP/examples/scheduled_counter.cpp']
for kind in ["address,undefined"]:
 name="asan" if kind.startswith("address") else "tsan"
 with Path("/tmp/dpm1-"+name+"-build.log").open("w") as log:
  subprocess.run(base+["-fsanitize="+kind,"-o","/tmp/dpm1-"+name],stdout=log,stderr=subprocess.STDOUT,check=True)
 print(name+" built",flush=True)

unit=["c++", "-std=c++23", "-pthread", "-g", "-O1", "-fno-omit-frame-pointer", "-fsanitize=thread",
 "-I/home/nzsn/Repos/MirrorCPP/include", "-I/home/nzsn/Repos/MirrorCPP/examples",
 "-I/tmp/mic-mirrorcpp-build/_deps/nlohmann_json-src/include",
 "-I/tmp/mic-catch2/Catch2-3.5.0/src", "-I/tmp/mirrorcpp-dpm1-build/_deps/catch2-build/generated-includes",
 "/home/nzsn/Repos/MirrorCPP/src/schedule.cpp", "/home/nzsn/Repos/MirrorCPP/test/unit/schedule_test.cpp",
 "/tmp/mirrorcpp-dpm1-build/_deps/catch2-build/src/libCatch2Maind.a",
 "/tmp/mirrorcpp-dpm1-build/_deps/catch2-build/src/libCatch2d.a", "-o", "/tmp/dpm1-tsan-tests"]
with Path("/tmp/dpm1-tsan-tests-build.log").open("w") as log:
 subprocess.run(unit, stdout=log, stderr=subprocess.STDOUT, check=True)
print("tsan focused tests built", flush=True)
