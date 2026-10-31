"""Package the actual successful Windows build; verify every selected input."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[1]
WORK = REPO / ".golden-build/completion-rc5-20261031"
TAG = "v0.2.0-rc.5"
PREFIX = f"mirrors-{TAG}-windows-x86_64"


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


native = json.loads((ROOT / "windows-native.json").read_text(encoding="utf-8-sig"))
assert native["state"] == "passed" and native["tag"] == TAG
assert len(native["gates"]) == 8 and all(g["exitCode"] == 0 for g in native["gates"])
assert native["postBuildSourceStable"] and native["sourceFilesVerified"] == 9367
assert native["versionOutput"] == TAG
output = WORK / "dist-windows"
output.mkdir(exist_ok=False)
package = WORK / "windows-package"
(package / "bin").mkdir(parents=True, exist_ok=False)
imports = {}
system = {n.lower() for n in ("ADVAPI32.dll", "IPHLPAPI.DLL", "KERNEL32.dll",
          "SHELL32.dll", "USER32.dll", "USERENV.dll", "WS2_32.dll", "bcrypt.dll",
          "dbghelp.dll", "icu.dll", "ole32.dll", "ucrtbase.dll", "msvcrt.dll",
          "CRYPT32.dll", "ntdll.dll")}
bundled = {n.lower() for n in native["files"]}
for name, entry in native["files"].items():
    source = WORK / "windows-binaries" / name
    assert sha(source) == entry["sha256"] and source.stat().st_size == entry["bytes"]
    text = subprocess.check_output(["objdump", "-p", str(source)], text=True)
    names = sorted(line.split("DLL Name:", 1)[1].strip() for line in text.splitlines()
                   if "DLL Name:" in line)
    assert names
    unresolved = [n for n in names if n.lower() not in system | bundled
                  and not n.lower().startswith("api-ms-win-")]
    assert not unresolved, (name, unresolved)
    imports[name] = names
    shutil.copyfile(source, package / "bin" / name)
manifest = {
    "schema": "mirrors.s3.windows-package/v1", "tag": TAG, "version": TAG[1:],
    "sourceCommit": native["commit"], "sourceTree": native["tree"],
    "sourceFileCount": native["sourceFilesVerified"], "sourceOverlay": False,
    "sourceArchive": native["archives"]["mirrors-v0.2.0-rc.5-source.tar.gz"],
    "batteriesRevision": native["batteriesRevision"], "host": native["host"],
    "os": native["os"], "toolchain": native["tools"], "files": native["files"],
    "gates": native["gates"], "peImports": imports,
    "published": False, "deployed": False,
    "scope": "native Windows 11 build and eight non-model suites; no full lake test, "
             "live-model, M5/D/Q, deployment, reboot, or reproducible-compilation acceptance",
}
external = output / f"{PREFIX}.build.json"
external.write_text(json.dumps(manifest, indent=2) + "\n")
shutil.copyfile(external, package / "BUILD.json")
(package / "README.txt").write_text(
    f"Mirrors {TAG}; source {native['commit']}.\n"
    "Windows x86-64 package; see BUILD.json for exact toolchain and validation scope.\n"
    "Not published or deployed.\n")
archives = [output / f"{PREFIX}.zip", WORK / f"{PREFIX}-repeat.zip"]
for archive in archives:
    with zipfile.ZipFile(archive, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as handle:
        for path in sorted(package.rglob("*")):
            if not path.is_file():
                continue
            assert not path.is_symlink()
            info = zipfile.ZipInfo(PREFIX + "/" + path.relative_to(package).as_posix(),
                                   date_time=(2026, 10, 31, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100600 << 16
            handle.writestr(info, path.read_bytes(), compresslevel=9)
assert sha(archives[0]) == sha(archives[1])
(output / "SHA256SUMS").write_text("".join(f"{sha(p)}  {p.name}\n" for p in
                                            sorted((archives[0], external))))
receipt = {"schema": "mirrors.completion-windows-package/v1", "tag": TAG,
           "archive": str(archives[0].relative_to(REPO)),
           "sha256": sha(archives[0]), "bytes": archives[0].stat().st_size,
           "externalBuildManifest": str(external.relative_to(REPO)),
           "externalBuildManifestSha256": sha(external), "repeatedPackagingIdentical": True,
           "repeatArchiveSha256": sha(archives[1]), "peImports": imports,
           "memberCount": 7}
(ROOT / "windows-package.json").write_text(json.dumps(receipt, indent=2) + "\n")
print(json.dumps(receipt, indent=2))
