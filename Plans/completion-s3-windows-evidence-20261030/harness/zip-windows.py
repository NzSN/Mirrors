from pathlib import Path
import hashlib, json, sys, zipfile
root = Path(sys.argv[1])
source = root / 'candidate-v0.2.0-rc.1'
name = 'mirrors-v0.2.0-rc.1-windows-x86_64'
outputs = [root / (name + '.zip'), root / (name + '-repeat.zip')]
for output in outputs:
    with zipfile.ZipFile(output, 'x', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(source.rglob('*')):
            if not path.is_file():
                continue
            assert not path.is_symlink()
            entry = zipfile.ZipInfo(name + '/' + path.relative_to(source).as_posix(), date_time=(2026, 10, 30, 0, 0, 0))
            entry.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(entry, path.read_bytes(), compresslevel=9)
values = [hashlib.sha256(path.read_bytes()).hexdigest() for path in outputs]
assert values[0] == values[1], 'repeat packaging differs'
payload = {'schema': 'mirrors.s3.windows-archive/v1', 'archive': outputs[0].name,
           'sha256': values[0], 'bytes': outputs[0].stat().st_size,
           'repeatArchive': outputs[1].name, 'repeatSha256': values[1],
           'repeatedPackagingIdentical': True,
           'scope': 'identical packaging of the same selected binaries; no reproducible-compilation claim'}
(root / 'windows-package-archive.json').write_text(json.dumps(payload, indent=2) + '\n', encoding='utf-8')
print('WINDOWS PACKAGE', values[0], outputs[0].stat().st_size)
