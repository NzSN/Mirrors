"""Portable publication must retain non-UTF-8 native diagnostics losslessly."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from archive import archive
from corpus import canonical_json
from report import semantic_payload


class ArchiveTests(unittest.TestCase):
    def test_native_stderr_bytes_survive_path_sanitization(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            source = root / 'original'
            raw_path = source / 'fixtures' / 'sample' / 'sany' / 'raw' / 'stderr.log'
            raw_path.parent.mkdir(parents=True)
            raw = b'\xd6\xd0\xce\xc4\r\n' + str(source).encode() + b'\r\n'
            raw_path.write_bytes(raw)
            relative = raw_path.relative_to(source).as_posix()
            observation = dict(fixture='sample', engine='sany', provider='filesystem',
                inputDigest='a'*64, execution='completed', outcome='accepted', stage='level',
                facts={}, diagnostics=[], invocation={'argv':[sys.executable]},
                rawArtifacts=[{'path':relative, 'sha256':hashlib.sha256(raw).hexdigest()}])
            report = dict(inputs={'implementationStable':True, 'semanticIdentity':{}, 'command':[]},
                observations=[observation], comparisons=[], coverage={}, verdict='pass')
            (source/'report.json').write_text(json.dumps(report), encoding='utf-8')
            (source/'semantic.json').write_text(canonical_json(semantic_payload(report))+'\n', encoding='utf-8')
            destination = root/'published'
            result = archive(source, destination, root/'repo')
            expected = raw.replace(str(source).encode(), b'<run>')
            self.assertEqual((destination/relative).read_bytes(), expected)
            self.assertEqual(result['observations'][0]['rawArtifacts'][0]['sha256'],
                             hashlib.sha256(expected).hexdigest())
            self.assertEqual(raw_path.read_bytes(), raw)
