# Profile-3 final capture 1 — post-status documentation

Required run passed with 183/183 completed observations: 564 exact matches, 14
reviewed differences, 292 explicitly unsupported comparisons, and zero
unresolved findings. The normalized semantic SHA-256 is
`b239480873912e7cabc79bde8266613b6aece19fb1acdede15afe9aca2459c11`.

Raw evidence is indexed by `artifact-index.json`; restore it with
`tar -xzf raw-evidence.tar.gz`.

## Aggregate validation

The complete aggregate passed with exit status `0` using the scoped pinned JDK
and an absolute Apalache executable:

```sh
PATH=/home/nzsn/Repos/Mirrors/.golden-build/tla-differential/jdk/jdk-25.0.4+7/bin:$PATH \
APALACHE_MC=/home/nzsn/Repos/Mirrors/.golden-build/tla-differential/toolchain/apalache-0.61.0/bin/apalache-mc \
lake test
```

The exact aggregate output is retained in
[`aggregate-lake-test.log`](aggregate-lake-test.log), SHA-256
`0fd912476cf07cb50773303817c78a5eb7d31084949e4a53916dc0c022e9fbff`.
