# S3 rc.6 clean package record — 2026-11-03

The accepted bounded S3 package set is built from local-only annotated tag
`v0.2.0-rc.6` (`5a2a6fd8728b610db7a6225b4a9d4c5d585344aa`), peeling to freeze
commit `3c4a87309cc3a81924660497207d7c295759bdc1`. The shared checkout has no
rc.6 tag and no remote tag was pushed.

| Package | SHA-256 | Scope |
| --- | --- | --- |
| `linux-dist/mirrors-v0.2.0-rc.6-linux-x86_64.tar.gz` | `9dc8e0ce2203c155bf8150479fd25e19bb5cd9774a6b688fd38fc57e74022038` | Maintained focused non-model release gates plus second isolated Ubuntu 26.04.1 WSL2 smoke |
| `dist-windows/mirrors-v0.2.0-rc.6-windows-x86_64.zip` | `9919ac2cb96a3dd693df89b02059a559f25aff7e052efc00a60a2e569c87564e` | Native Windows build and eight declared non-model suites; repeat ZIP and PE closure |

Both packages have `published: false` and `deployed: false`. This is not full
Windows `lake test`, reproducible-compilation evidence, installed D/M5/Q,
remote-model, framework or release admission. The exact locked S5 Batteries
carrier remains a separate missing input.

## Review

- `task.md`: phased A–D task contract.
- `source-identity.json`, `intake.json`, `input-inventory.json`: admitted inputs.
- `linux-*.json`, `windows-*.json`: construction and package receipts.
- `review.md`: Codex findings, independent reproduction and acceptance boundary.
- `s3-package-set.json`: unified package identities.
- `inventory.json`: hashes of Git-payload candidates and required raw artifacts.

Run the offline review from the repository root:

```bash
python3 Plans/mainwork-s3-rc6-20261103/verify_s3.py
```

The verifier reruns phase-A and maintained Linux archive checks, validates both
archives/manifests/gates/PE imports, independently compares the fresh post-build
Windows source manifest, and checks inventory closure and negative controls.
