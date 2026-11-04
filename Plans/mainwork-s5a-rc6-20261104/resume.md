# Exact frozen S5-A continuation commands

These commands are **not executed**. Run only after the exact carrier has been
restored and admitted as described in `README.md`. All outputs must be new;
retain failed attempts and select new output paths before retrying. Run the D
audits in the admitted host context, not the restrictive sandbox.

```bash
MIRRORS=/home/lsz/Codebase/Mirrors
S5_STAGE="$MIRRORS/.golden-build/mainwork-s5a-rc6-20261104"
S5_FREEZE="$MIRRORS/.golden-build/mainwork-freeze-20261103"
S5_LOCKS="$S5_FREEZE/candidates/wsl2/distribution/reference-node-wsl2-26.04"
S5_CATALOG="$S5_FREEZE/candidates/wsl2/catalog/framework-catalog-wsl2-26.04.json"
S5_SNAPSHOT="$S5_FREEZE/snapshots/wsl2"
S5_VERIFIER="$MIRRORS/.lake/build/bin/framework_catalog"
S5_VERIFIER_SHA=5a64a5bd40e999b20dd8268f2846c0f5ad5359067db9f014379c150e27d76126
S5_STRACE="$MIRRORS/.golden-build/mw12-20261103/integration-runtime/strace-pinned"
S5_STRACE_SHA=0d677426d0a518cf7f3c4f9b6527d1b313752eabb0e3a96d4ec8fa799b4265c7
S5_ECMA="$MIRRORS/.golden-build/mw12-20261103/inputs/companions/MirrorECMA"
S5_GATE="$MIRRORS/.golden-build/mw12-20261103/inputs/companions/MirrorGate"

# Set S5_BATTERIES to the restored, verified regular file before continuing.
: "${S5_BATTERIES:?exact locked Batteries carrier path required}"
install -d -m 0700 "$S5_STAGE/tmp" "$S5_STAGE/cache" "$S5_STAGE/install" "$S5_STAGE/audit"
export TMPDIR="$S5_STAGE/tmp"

for S5_PROFILE in checked-replay-local checked-replay-gate; do
  python3 tools/distribution/build.py \
    --profile "$S5_PROFILE" --locks-root "$S5_LOCKS" --catalog "$S5_CATALOG" \
    --out "$S5_STAGE/cache/$S5_PROFILE" --snapshot-root "$S5_SNAPSHOT" \
    --lake-bin /home/lsz/.elan/bin/lake \
    --node-archive "$MIRRORS/.golden-build/version-0.1/toolchains/node-v24.15.0-linux-x64.tar.xz" \
    --batteries-bundle "$S5_BATTERIES" --git-bin /usr/bin/git --ldd-bin /usr/bin/ldd \
    --typescript-node-modules "$MIRRORS/.golden-build/rc3-s5-20261031/ts-deps" \
    --evidence-wheels "$MIRRORS/.golden-build/rc3-s5-20261031/prepared/evidence-wheels" \
    --framework-catalog-bin "$S5_VERIFIER" --framework-catalog-sha256 "$S5_VERIFIER_SHA" || exit $?

  python3 tools/distribution/install.py \
    --cache "$S5_STAGE/cache/$S5_PROFILE" --prefix "$S5_STAGE/install/$S5_PROFILE" \
    --framework-catalog-bin "$S5_VERIFIER" --framework-catalog-sha256 "$S5_VERIFIER_SHA" || exit $?

  S5_COMBINATION=candidate.local-node-checked
  if [ "$S5_PROFILE" = checked-replay-gate ]; then S5_COMBINATION=candidate.node-gate; fi
  install -d -m 0700 "$S5_STAGE/audit/$S5_PROFILE"
  python3 tools/distribution/qualification.py \
    --prefix "$S5_STAGE/install/$S5_PROFILE" \
    --framework-catalog-bin "$S5_VERIFIER" --framework-catalog-sha256 "$S5_VERIFIER_SHA" \
    --bwrap /usr/bin/bwrap --strace "$S5_STRACE" --strace-sha256 "$S5_STRACE_SHA" \
    --combination "$S5_COMBINATION" \
    --audit-out "$S5_STAGE/audit/$S5_PROFILE/install-diagnostics.json" \
    --hide-root "$MIRRORS" --hide-root "$S5_ECMA" --hide-root "$S5_GATE" \
    --hide-root /home/lsz/Codebase/MirrorECMA --hide-root /home/lsz/Codebase/MirrorGate || exit $?
done
```

Retain stdout, stderr, exit codes, and before/after identities for each command.
The loop is a recipe, not an acceptance wrapper: inspect every result and require
both actual D audit receipts. No optional Lean build cache, local model checker,
Java/Apalache restoration, or Ubuntu 24.04 installation is selected here.
