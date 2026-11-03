# MW-12 candidate binding

`python3 Plans/mainwork-mw12-20261103/apply_bindings.py --attempt binding-a1` updated the registry, runtime pin, product-version record, and both catalog/lock roots. The process exited 1: the immediate repeat saw different catalog bytes than the first refresh. A follow-up refresh pair left the repeat bytes unchanged. Lock validation then passed. This is an uncommitted candidate at `75fbf962020cea8a13e009ecfdb3e912e7ce212f`, not a clean or tagged release freeze. No qualification is claimed.

## Binding

`mirrors.interop.requiredEnvironment.ECMA_REF` is `9192171fc5f8d8457f8d13ffaafa117222914ec2`. The other client and backend pins are unchanged. The prepared runtime pin is `tools/interop/ecma-runtime-pin.json`.

The local and gate D prefixes bind the candidate install paths, C3 `.lake/build/bin/framework_catalog` (`5a64a5bd40e999b20dd8268f2846c0f5ad5359067db9f014379c150e27d76126`), and the pinned strace wrapper (`0d677426d0a518cf7f3c4f9b6527d1b313752eabb0e3a96d4ec8fa799b4265c7`). Hide roots are this Mirrors checkout and the selected MirrorECMA and MirrorGate checkouts. Argument order, argv lengths, and attachment indexes are unchanged. These are future bindings. The candidate directory was not installed, and neither D audit ran. Tracer namespace admission is not established.

The Mirrors component records on `catalog/components/mirrors.json` and both catalog variants include `product-version` for `Shell/Version.lean`.

## Identity

| Catalog | Role | C0 selection digest |
| --- | --- | --- |
| `catalog/framework-catalog.json` | structural control | `ad9d28ae4b3b4eb2a662117b411fc8acc82e24cc82a04d8dfe6e770289c610bc` |
| `catalog/framework-catalog-wsl2-26.04.json` | selected execution, `ubuntu-26.04-wsl2-x86_64` | `22596af73d943b2204a2ae3c7bbc39ae9c41ff03442507e0f26b183ac503a88c` |

The in-run first refresh digests were base `9f9896b73dd5f9be2639479be6da2782ed0ccfb3eb1ff6c259be50da3726a223` and WSL2 `0f6a838d56a329a7a76b8ae6db62a340dbf9605d98319e1badf7facbcee69ca0`. The retained catalogs are the repeat digests above. File SHA-256 values are `d69e8f5244d990d652ef6201f2f37ae0b12896d6c235c13d118aeade212e6f4d` and `af47093b7f78d361800008bb03cda2dd2663b17ed9b67aa09ce8fda2b23e34c4`.

Mirrors product is `0.2.0-rc.6`. MirrorECMA `9192171fc5f8d8457f8d13ffaafa117222914ec2` is clean, product `mirrorecma` `0.1.0`. MirrorGate `4b379ac0c017e7621c945ebf8c106cd98a6c70d1` is clean, product `MirrorGate` `0.1.0`. The dirty source content digest is `59be0488dc9b32c086ac0b66e05459197fe9209e410ceeb47a87cf26f55ba80a`. Both dependency locks remain `6033532222a34073408ae0a9e59da548588e8f1eccead5f035d21d4a2087d5fe` and match `HEAD`. Every fixture lock input uses its `distribution/<root>/` prefix.

## Tests

Python 3.14.4. `TMPDIR` was `/home/lsz/Codebase/Mirrors/.golden-build/mw12-20261103/binding-tmp` on ext4 (`/dev/sdd[/home/lsz]` mounted at `/home/lsz`). `PYTHONDONTWRITEBYTECODE=1`.

| Suite | Result |
| --- | --- |
| `python3 -m unittest discover -s tools/distribution -p test_*.py -v` | 68 tests, exit 0, 4.899s |
| `python3 -m unittest discover -s tools/evidence/tests -p test_*.py -v` | 146 tests, exit 0, 23.027s |

`test_*.py` was one argv element. Raw streams and exit codes are under `binding/logs/`.

## Evidence

Pre-edit bytes are in `binding/binding-a1-before/`. The assertion receipt is `binding/binding-a1-assertions.json`. Refresh command logs are under `Plans/mainwork-mw12-20261103/integration/` for `binding-a1-base-refresh`, `binding-a1-wsl-refresh`, `binding-a1-base-repeat`, `binding-a1-wsl-repeat`, `binding-a1-base-stable`, and `binding-a1-wsl-stable`.

## Not run

Lake, an installed build, a D audit, Apalache, TLC, remote model checks, production operations, and Git ref changes.
