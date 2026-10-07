#!/usr/bin/env python3
"""Read-only host eligibility facts; never creates cgroups or signals processes."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
import platform
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--gate-root', type=Path, default=Path(__file__).resolve().parents[3] / 'MirrorGate')
    parser.add_argument('--cgroup-parent', type=Path)
    args = parser.parse_args()
    gate = args.gate_root.resolve()
    backend = gate / 'supervisor/mirrorgate/cgroup.py'
    recovery = gate / 'supervisor/mirrorgate/recovery.py'
    if not backend.is_file() or not recovery.is_file():
        parser.error('Gate backend/recovery source is absent')
    # Import the declared backend, without probing or creating a child group.
    sys.dont_write_bytecode = True
    sys.path.insert(0, str(gate / 'supervisor'))
    from mirrorgate.cgroup import CgroupDelegation
    release = platform.release()
    wsl = 'microsoft' in release.lower() or 'wsl' in release.lower()
    delegation = {'requestedParent': str(args.cgroup_parent) if args.cgroup_parent else None,
                  'readOnlyValidation': 'not_requested', 'reason': 'no_operator_delegation_supplied'}
    if args.cgroup_parent is not None:
        try:
            handle = CgroupDelegation(args.cgroup_parent)
        except (OSError, ValueError, RuntimeError) as error:
            delegation.update(readOnlyValidation='refused', reason=str(error))
        else:
            try:
                delegation.update(readOnlyValidation='passed', reason=None,
                                  device=handle.identity[0], inode=handle.identity[1])
            finally:
                handle.close()
    report = {
        'schema': 'mirrors.m4-host-preflight/v1',
        'host': {'system': platform.system(), 'release': release, 'uid': os.geteuid(), 'wsl': wsl},
        'backendSourceSha256': hashlib.sha256(backend.read_bytes()).hexdigest(),
        'recoverySourceSha256': hashlib.sha256(recovery.read_bytes()).hexdigest(),
        'delegation': delegation,
        'nativeLinuxHost': platform.system() == 'Linux' and not wsl,
        'kernelEnforcementTested': False,
        'postRestartProcessRecoveryTested': False,
        'sideEffects': 'input reads only; no group creation, signals or journal changes',
        'nextRequiredEvidence': ['actual delegated-subtree quota and descendant enforcement',
                                 'controller-death recovery with exact owned process/subtree identity'],
    }
    print(json.dumps(report, indent=2))
    # This is inspection, not an enforcement acceptance test.
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
