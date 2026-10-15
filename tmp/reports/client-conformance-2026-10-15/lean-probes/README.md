# Focused MirrorLean source probes — remote WSL only

No source or test changes in a client checkout. No Mirrors server, Apalache or
TLC required. Source has not been compiled or run on the coordinator.

Place this directory on the remote machine as `TASK/lean-probes`, with an exact
MirrorLean b8b9491bd96e3126da55d34a7ba3a4493766dcf3 source snapshot at
`TASK/MirrorLean` (or a sibling symlink to that private source snapshot).
Requires Lean/Lake 4.33.0 via elan, system `cc`, OpenSSL 3 headers/library and
`openssl`; Python 3 only drives fresh test peers. Build outputs stay in the
owned task workspace. Existing dependency `.olean` files may avoid rebuilding
MirrorLean; a cold remote build compiles the small MirrorLean package.

From the remote `TASK/lean-probes` directory:

```sh
lake build closure-probe tls-identity-probe
.lake/build/bin/closure-probe fixtures > closure.jsonl
python3 run-tls-probe.py --client-root ../MirrorLean --output tls-results
```

Expected current-source C13 witness: ControlRoot has 2 sources and dependency
present; MarkerRoot has only 1 source and dependency absent. Both specs declare
`Helper == INSTANCE Dep`; MarkerRoot also has a valid string `"(*"`. This probes
the real `specFromFiles` API without invoking any modelchecker. Correct behavior
would retain Dep in both closures.

Expected current-source C25 witness: normal SAN peer `server` accepts default,
rejects wrong-name and accepts empty-name. CN-only peer `server-cn` rejects
default and wrong-name but accepts empty-name. The CN-only empty-name connection
is the defect: the client has authenticated the CA without any SAN identity.
The driver starts only test-owned loopback `openssl s_server` children, enforces
finite deadlines, and terminates/reaps them in `finally`. Fresh private keys stay
under remote output/pki; do not transfer private keys into a report.

ClosureProbe also prints two peripheral C14 decoder results: absent constInit
is accepted, null constInit is rejected. This is the public request-config
`ApalacheConfig.ofJson?` convenience API; normal typed outbound client calls omit
optionals and remain wire conforming. Keep this observation separate from the
two runner-facing findings.

Do not describe expected results as runtime reproduction until actual remote
JSONL and compiler results have been inspected.
