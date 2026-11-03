"""Write the rc.6 Windows ZIP twice from the same packaged bytes."""
import hashlib
import json
import sys
import zipfile
from pathlib import Path

ROOT = Path(r"D:\ModelMirrors\staging\s3-rc6-20261103-3c4a873")
SOURCE = ROOT / "mirrors-v0.2.0-rc.6-windows-x86_64"
NAME = "mirrors-v0.2.0-rc.6-windows-x86_64"
OUTPUTS = [ROOT / f"{NAME}.zip", ROOT / f"{NAME}-repeat.zip"]
ALLOWED = {
    "BUILD.json",
    "README.txt",
    "bin/ModelMirrors.exe",
    "bin/model_interface_gen.exe",
    "bin/libcrypto-3-x64.dll",
    "bin/libssl-3-x64.dll",
    "bin/zlib1.dll",
}


def main() -> None:
    files = [path for path in SOURCE.rglob("*") if path.is_file()]
    files.sort(key=lambda path: path.relative_to(SOURCE).as_posix())
    rels = [path.relative_to(SOURCE).as_posix() for path in files]
    if set(rels) != ALLOWED or any(path.is_symlink() for path in files):
        print(f"unexpected package members: {rels}", file=sys.stderr)
        raise SystemExit(1)
    for output in OUTPUTS:
        if output.exists():
            print(f"refusing to overwrite {output}", file=sys.stderr)
            raise SystemExit(1)
        with zipfile.ZipFile(output, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            for path in files:
                entry = zipfile.ZipInfo(NAME + "/" + path.relative_to(SOURCE).as_posix(), date_time=(2026, 11, 3, 0, 0, 0))
                entry.compress_type = zipfile.ZIP_DEFLATED
                entry.external_attr = 0o644 << 16
                archive.writestr(entry, path.read_bytes(), compresslevel=9)
    values = [hashlib.sha256(path.read_bytes()).hexdigest() for path in OUTPUTS]
    if values[0] != values[1]:
        print("repeat packaging differs", file=sys.stderr)
        raise SystemExit(1)
    payload = {
        "schema": "mirrors.s3-rc6.windows-archive/v1",
        "published": False,
        "deployed": False,
        "archive": OUTPUTS[0].name,
        "sha256": values[0],
        "bytes": OUTPUTS[0].stat().st_size,
        "repeatArchive": OUTPUTS[1].name,
        "repeatSha256": values[1],
        "repeatedPackagingIdentical": True,
        "reproducibleCompilation": False,
        "releaseAdmission": False,
        "fullLakeTest": False,
    }
    (ROOT / "windows-package-archive.json").write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(f"WINDOWS PACKAGE {values[0]} {OUTPUTS[0].stat().st_size}")


if __name__ == "__main__":
    main()
