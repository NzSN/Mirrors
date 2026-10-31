# Ubuntu 26.04 WSL2 reference distribution variant

Additive profile/lock root for the explicitly selected
`ubuntu-26.04-wsl2-x86_64` scope. It is selected with:

```bash
python3 tools/distribution/build.py \
  --profile checked-replay-local \
  --catalog catalog/framework-catalog-wsl2-26.04.json \
  --locks-root distribution/reference-node-wsl2-26.04 ...
```

The profile and combination identifiers are deliberately unchanged from the
checked Ubuntu 24.04 reference profile so the installed command registry does
not fork. The catalog profile IDs name `ubuntu-26.04-wsl2`; the installer refuses
that profile unless `/proc/sys/kernel/osrelease` reports the
`microsoft-standard-WSL2` kernel family.

The checked `distribution/reference-node` and
`catalog/framework-catalog.json` inputs remain the Ubuntu 24.04 default and are
not modified by this variant. Refresh this variant with
`tools/distribution/refresh_identity.py --catalog ... --locks-root ...
--skip-component-records --skip-render` after an approved source freeze.
