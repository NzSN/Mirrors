# MirrorCPP Windows qualification source

This Git source carrier retains the task-owned portability commit
`c95f0e185436f145af9fad8895430e899bc479a3`, based on upstream MirrorCPP
`8c542a6b1339cc0b6176465ff7f17a32e614553d` from
<https://github.com/NzSN/MirrorCPP>. It is source, not a compiled SDK or a
published upstream release. The original sibling checkout is unchanged.

`mirrorcpp-windows-v0.1.1.bundle` is 345645 bytes; SHA-256:
`fa06550a9d23c6efc50257ac531a1b4bce3b99b06ec050d6a0a95226b437bf0c`.
It contains complete Git objects for an offline checkout of the selected commit.
The reviewed patch and bounded validation record are in
`Plans/qualification-rc7-20261105/`. No private credentials or build outputs
are included.

```sh
git clone third_party/mirrorcpp/mirrorcpp-windows-v0.1.1.bundle /tmp/mirrorcpp-source
git -C /tmp/mirrorcpp-source checkout --detach c95f0e185436f145af9fad8895430e899bc479a3
```

The registered CLI hash binds the retained Linux build separately. Cloning the
source does not imply byte-reproducible compilation, native Windows client
qualification, all SDK test coverage, or Windows ACL/Unicode-path acceptance.
