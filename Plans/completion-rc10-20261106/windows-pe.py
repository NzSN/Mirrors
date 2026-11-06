"""Check PE imports against the reviewed rc.10 system closure."""
import json
import struct
import sys
import zipfile
from pathlib import Path

ROOT = Path(r"D:\ModelMirrors\staging\completion-rc10-20261106")
ZIP = ROOT / "mirrors-v0.2.0-rc.10-windows-x86_64.zip"
NAME = "mirrors-v0.2.0-rc.10-windows-x86_64"
SYSTEM = {
    "ADVAPI32.dll",
    "IPHLPAPI.DLL",
    "KERNEL32.dll",
    "SHELL32.dll",
    "USER32.dll",
    "USERENV.dll",
    "WS2_32.dll",
    "bcrypt.dll",
    "dbghelp.dll",
    "icu.dll",
    "ole32.dll",
    "ucrtbase.dll",
    "msvcrt.dll",
    "CRYPT32.dll",
    "ntdll.dll",
}
PACKAGED = {"libcrypto-3-x64.dll", "libssl-3-x64.dll", "zlib1.dll"}
BINARIES = ("ModelMirrors.exe", "model_interface_gen.exe", "libcrypto-3-x64.dll", "libssl-3-x64.dll", "zlib1.dll")


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(1)


def pe_imports(data: bytes) -> set[str]:
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    if data[pe:pe + 4] != b"PE\0\0":
        fail("not a PE image")
    coff = pe + 4
    sections = struct.unpack_from("<H", data, coff + 2)[0]
    opt_size = struct.unpack_from("<H", data, coff + 16)[0]
    opt = coff + 20
    if struct.unpack_from("<H", data, opt)[0] != 0x20B:
        fail("not PE32+")
    directories = opt + 112
    table = []
    for index in range(sections):
        offset = opt + opt_size + 40 * index
        virtual_size, virtual_address, raw_size, raw_pointer = struct.unpack_from("<IIII", data, offset + 8)
        table.append((virtual_address, virtual_size, raw_pointer, raw_size))

    def file_offset(rva: int) -> int:
        for virtual_address, virtual_size, raw_pointer, raw_size in table:
            if virtual_address <= rva < virtual_address + max(virtual_size, raw_size):
                return raw_pointer + (rva - virtual_address)
        fail(f"unmapped RVA 0x{rva:x}")
        return 0

    names = set()
    rva = struct.unpack_from("<I", data, directories + 8)[0]
    while rva:
        offset = file_offset(rva)
        name_rva = struct.unpack_from("<I", data, offset + 12)[0]
        if name_rva == 0:
            break
        target = file_offset(name_rva)
        names.add(data[target:data.index(b"\0", target)].decode("ascii"))
        rva += 20
    return names


def allowed(name: str) -> bool:
    folded = {item.lower() for item in SYSTEM | PACKAGED}
    return name.lower() in folded or name.lower().startswith("api-ms-win-")


def main() -> None:
    imports = {}
    with zipfile.ZipFile(ZIP) as handle:
        for binary in BINARIES:
            data = handle.read(f"{NAME}/bin/{binary}")
            found = pe_imports(data)
            unknown = sorted(name for name in found if not allowed(name))
            imports[binary] = sorted(found)
            if unknown:
                fail(f"{binary} imports outside the reviewed closure: {unknown}")
    record = {
        "schema": "mirrors.s3-rc10.windows-pe/v1",
        "published": False,
        "deployed": False,
        "comparison": "case-insensitive",
        "imports": imports,
        "closurePassed": True,
    }
    (ROOT / "windows-pe.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    print("PE CLOSURE PASSED")


if __name__ == "__main__":
    main()
