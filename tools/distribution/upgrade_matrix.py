#!/usr/bin/env python3
"""Exercise tamper, interruption, idempotence, and rollback in disposable roots."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from distribution_lib import runtime_tree
from install import install, selector, verify_installation
from verify import verify


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--prefix", type=Path, required=True)
    parser.add_argument("--framework-catalog-bin", type=Path, required=True)
    parser.add_argument("--framework-catalog-sha256", required=True)
    parser.add_argument("--audit-out", type=Path, required=True)
    args = parser.parse_args()
    try:
        observations = []
        with tempfile.TemporaryDirectory(prefix="mirrors-upgrade-matrix-") as temporary:
            root = Path(temporary)
            _candidate_manifest, candidate_digest, _candidate_contract = verify(
                args.candidate, args.framework_catalog_bin, args.framework_catalog_sha256)
            if args.cache.resolve() == args.candidate.resolve():
                raise ValueError("old and candidate caches must be distinct paths")
            state, original_digest = install(args.cache, args.prefix,
                args.framework_catalog_bin, args.framework_catalog_sha256, None)
            if original_digest == candidate_digest:
                raise ValueError("old and candidate manifests must have distinct identities")
            state2, _ = install(args.cache, args.prefix,
                args.framework_catalog_bin, args.framework_catalog_sha256, None)
            if state2 != "idempotent": raise ValueError("same manifest was not idempotent")
            active = selector(args.prefix); assert active is not None
            original_version = args.prefix / active["versionDirectory"]
            original_tree = runtime_tree(original_version)
            tampered_install = root / "tampered-install"
            shutil.copytree(original_version, tampered_install)
            package_manifest = tampered_install / "runtime/packages/mirrorecma/package.json"
            with package_manifest.open("ab") as handle:
                handle.write(b" ")
            materialized = json.loads((tampered_install / "materialization.json").read_text())
            materialized.update(runtime_tree(tampered_install / "runtime"))
            (tampered_install / "materialization.json").write_text(
                json.dumps(materialized, indent=2) + "\n")
            try:
                verify_installation(tampered_install, args.framework_catalog_bin,
                    args.framework_catalog_sha256)
                raise ValueError("tampered package plus rewritten local materialization digest passed")
            except Exception as error:
                observations.append({"case": "package-and-local-digest-tamper", "rejected": True,
                    "detail": str(error)[:512]})
            for stage in ("after-copy", "after-materialize", "after-verify", "before-activate",
                    "after-version-rename", "after-selector"):
                try:
                    install(args.candidate, args.prefix, args.framework_catalog_bin,
                        args.framework_catalog_sha256, stage)
                    raise ValueError(f"injection did not fail: {stage}")
                except RuntimeError:
                    pass
                selected = selector(args.prefix)
                if selected is None or selected["manifestDigest"] != original_digest:
                    raise ValueError(f"previous selector not preserved: {stage}")
                if runtime_tree(original_version) != original_tree:
                    raise ValueError(f"previous version bytes changed: {stage}")
                output = subprocess.check_output([str(original_version / "runtime/bin/ModelMirrors"), "--version"], text=True).strip()
                if output != "Mirrors 0.0.2": raise ValueError("previous ModelMirrors unusable")
                observations.append({"stage": stage, "previousDigest": original_digest,
                    "candidateDigest": candidate_digest, "selectorPreserved": True,
                    "previousTreeDigest": original_tree["digest"], "version": output})
            tampered = root / "tampered"; shutil.copytree(args.cache, tampered)
            with (tampered / "artifacts/inputs/framework-catalog.A.json").open("ab") as handle:
                handle.write(b" ")
            try:
                verify(tampered, args.framework_catalog_bin, args.framework_catalog_sha256)
                raise ValueError("tampered cache passed")
            except Exception as error:
                observations.append({"case": "hash-mismatch", "rejected": True,
                    "detail": str(error)[:512]})
            missing = root / "missing"; shutil.copytree(args.cache, missing)
            artifact = json.loads((missing / "distribution-manifest.json").read_text())["artifacts"][0]
            (missing / artifact["path"]).unlink()
            try:
                verify(missing, args.framework_catalog_bin, args.framework_catalog_sha256)
                raise ValueError("missing artifact cache passed")
            except Exception as error:
                observations.append({"case": "missing-artifact", "rejected": True,
                    "detail": str(error)[:512]})
        data = (json.dumps({"schemaVersion": "mirrors.upgrade-matrix-audit/v1",
            "observations": observations}, indent=2) + "\n").encode()
        descriptor = os.open(args.audit_out, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        try:
            offset = 0
            while offset < len(data): offset += os.write(descriptor, data[offset:])
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
        print("REFERENCE DISTRIBUTION UPGRADE MATRIX GREEN")
        return 0
    except Exception as error:
        print(f"upgrade matrix failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
