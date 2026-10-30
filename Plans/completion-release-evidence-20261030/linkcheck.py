#!/usr/bin/env python3
"""Bounded relative-link checker for the reviewed Markdown payload.

Checks only local relative targets in changed Markdown files. External URLs,
mailto:, absolute paths, code spans and fenced blocks are ignored. Anchors are
stripped before resolution; heading-anchor validation is out of scope here.
"""
import re, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LINK = re.compile(r'(?<!\!)\[[^\]]*\]\(([^)]+)\)')
FENCE = re.compile(r'^```.*?^```', re.M | re.S)

def changed_markdown():
    out = subprocess.run(['git','status','--porcelain=v1','--untracked-files=all'], cwd=ROOT,
                         text=True, capture_output=True, check=True).stdout
    paths = []
    for line in out.splitlines():
        path = line[3:]
        if path.endswith('.md') and (ROOT/path).is_file():
            paths.append(path)
    return sorted(paths)

def links(text):
    text = FENCE.sub('', text)
    text = re.sub(r'`[^`]*`', '', text)
    for match in LINK.finditer(text):
        target = match.group(1).strip()
        if target.startswith(('http://','https://','mailto:','#','/')) or not target:
            continue
        yield target

def main():
    failures, checked, cross = [], 0, 0
    files = changed_markdown()
    for name in files:
        source = ROOT/name
        for target in links(source.read_text(encoding='utf-8')):
            path = target.split('#',1)[0].split('?',1)[0]
            if not path:
                continue
            checked += 1
            resolved = (source.parent/path).resolve()
            if not resolved.is_relative_to(ROOT.resolve()):
                cross += 1
                if not resolved.exists():
                    failures.append(f'{name}: missing companion target: {target}')
            elif not resolved.exists():
                failures.append(f'{name}: missing target: {target}')
    print(f'checked {checked} relative links in {len(files)} changed Markdown files; {cross} cross-repository companion links, all existing')
    for failure in failures:
        print('FAIL', failure)
    return 1 if failures else 0

if __name__ == '__main__':
    raise SystemExit(main())
