#!/usr/bin/env bash
set -euo pipefail
fix_root=/home/jlc/Tools/mirrors-client-fixes-20261015
fix_build=/mnt/d/Desktop/Workspaces/Mirrors-client-fixes-20261015
out="$fix_build/cpp-gate"
export TMPDIR=/tmp/fix-tests
export PATH="$fix_root/tools/bin:/usr/bin:/bin"
exec > >(tee "$out/logs/01-source-and-bwrap-prepare.log") 2>&1
cd "$fix_build"
printf '%s  %s\n' 577f5fd3dd9fd4b52741d85a242b9d14b7250d2d52dcb73f6ce38eeb7628fc83 cpp-gate-sources.tar | sha256sum -c -
printf '%s  %s\n' 22ffa7cfacbc611263dcc0fbd5b47cc9d4c7fd3c48d63221e8561478b721c1b4 cpp-gate-sources.sha256 | sha256sum -c -
test ! -e "$fix_root/source/MirrorCPP"
test ! -e "$fix_root/source/MirrorGate"
tar -xf cpp-gate-sources.tar -C "$fix_root/source"
cp cpp-gate-sources.sha256 "$out/manifests/source-files.sha256"
cd "$fix_root/source"
sha256sum -c "$out/manifests/source-files.sha256" > "$out/logs/source-hash-verification.log"
printf 'verified source files: '
wc -l < "$out/manifests/source-files.sha256"
mkdir -p "$out/bwrap-source" "$fix_root/tools/bwrap09"
cd "$fix_build/downloads"
printf '%s  %s\n' c6347eaced49ac0141996f46bba3b089e5e6ea4408bc1c43bab9f2d05dd094e1 bubblewrap-0.9.0.tar.xz | sha256sum -c -
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
  https://api.github.com/repos/containers/bubblewrap/releases/tags/v0.9.0 \
  -o "$out/manifests/bubblewrap-release.json"
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
  https://api.github.com/repos/containers/bubblewrap/git/tags/5beb8d46d5edde6e53f6e7d4e6e37cbb645c5f4e \
  -o "$out/manifests/bubblewrap-tag-object.json"
cp bubblewrap-tag.json "$out/manifests/bubblewrap-tag-ref.json"
python3 - "$out/manifests" <<'PY'
import json,sys
from pathlib import Path
root=Path(sys.argv[1])
ref=json.loads((root/'bubblewrap-tag-ref.json').read_text())
tag=json.loads((root/'bubblewrap-tag-object.json').read_text())
release=json.loads((root/'bubblewrap-release.json').read_text())
assert ref['ref']=='refs/tags/v0.9.0'
assert ref['object']['sha']==tag['sha']=='5beb8d46d5edde6e53f6e7d4e6e37cbb645c5f4e'
assert tag['tag']=='v0.9.0' and tag['object']['type']=='commit'
assert release['tag_name']=='v0.9.0' and not release['draft']
asset=next(x for x in release['assets'] if x['name']=='bubblewrap-0.9.0.tar.xz')
assert asset['browser_download_url']=='https://github.com/containers/bubblewrap/releases/download/v0.9.0/bubblewrap-0.9.0.tar.xz'
digest=asset.get('digest')
if digest: assert digest=='sha256:c6347eaced49ac0141996f46bba3b089e5e6ea4408bc1c43bab9f2d05dd094e1'
result={'tagObject':tag['sha'],'tagCommit':tag['object']['sha'],
        'releaseAsset':asset['browser_download_url'],'releaseDigest':digest,
        'observedArchiveSha256':'c6347eaced49ac0141996f46bba3b089e5e6ea4408bc1c43bab9f2d05dd094e1',
        'tagSignatureVerified':False}
(root/'bubblewrap-provenance.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result))
PY
tar -xJf bubblewrap-0.9.0.tar.xz -C "$out/bwrap-source"
cat "$out/bwrap-source/bubblewrap-0.9.0/meson_options.txt"
head -35 "$out/bwrap-source/bubblewrap-0.9.0/meson.build"
sha256sum "$out/manifests/"bubblewrap-*.json > "$out/manifests/bubblewrap-metadata.sha256"
echo CPP_GATE_SOURCE_AND_BWRAP_READY
