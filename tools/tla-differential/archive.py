"""Publish portable evidence without exposing the host's workspace paths."""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from pathlib import Path

from corpus import canonical_json
from report import semantic_payload


def archive(source: Path, destination: Path, repository: Path):
    report = json.loads((source / "report.json").read_text())
    if not report["inputs"].get("implementationStable"):
        raise ValueError("cannot publish evidence from a changing implementation")
    if destination.exists():
        raise ValueError("evidence destination already exists")
    semantic = canonical_json(semantic_payload(report)) + "\n"
    if semantic != (source / "semantic.json").read_text():
        raise ValueError("source semantic payload does not verify")
    refs = {ref["path"]: ref["sha256"] for row in report["observations"] for ref in row["rawArtifacts"]}
    for name, sha in refs.items():
        path = source / name
        if not path.resolve().is_relative_to(source.resolve()) or path.is_symlink() or hashlib.sha256(path.read_bytes()).hexdigest() != sha:
            raise ValueError("source evidence does not verify: " + name)
    shutil.copytree(source, destination)
    replacements = [(str(source.resolve()), "<run>"), (str(repository.resolve()), "<repo>")]
    for row in report["observations"]:
        argv = row["invocation"]["argv"]
        if argv and Path(argv[0]).is_absolute() and not argv[0].startswith(str(repository.resolve())):
            replacements.append((argv[0], "<runtime>"))

    def portable(text):
        for old, new in replacements:
            text = text.replace(old, new)
        return text.replace("/tmp/", "<tmp>/")

    for name in refs:
        path = destination / name
        path.write_text(portable(path.read_text(encoding="utf-8")), encoding="utf-8")
    for row in report["observations"]:
        row["invocation"]["argv"] = [portable(arg) for arg in row["invocation"]["argv"]]
        row["diagnostics"] = json.loads(portable(json.dumps(row["diagnostics"])))
        for ref in row["rawArtifacts"]:
            ref["sha256"] = hashlib.sha256((destination / ref["path"]).read_bytes()).hexdigest()
        observation_path = destination / "fixtures" / row["fixture"] / row["engine"] / "observation.json"
        observation_path.write_text(canonical_json(row) + "\n")
    report["inputs"]["command"] = [portable(arg) for arg in report["inputs"]["command"]]
    report["inputs"]["archive"] = {"sanitizedHostPaths": True,
        "archiverSha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "originalReportSha256": hashlib.sha256((source / "report.json").read_bytes()).hexdigest(),
        "originalRawHashes": refs}
    if canonical_json(semantic_payload(report)) + "\n" != semantic:
        raise ValueError("archiving changed semantic evidence")
    (destination / "report.json").write_text(canonical_json(report) + "\n")
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    archive(args.source.resolve(), args.destination.resolve(), Path(__file__).resolve().parents[2])
