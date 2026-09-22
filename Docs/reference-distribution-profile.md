# Reference distribution profile

Status: I1 selected proposal under the B2 execution decision, 2026-09-22

The first distribution candidate is Ubuntu 24.04 x86_64. This selects a narrow
build and qualification target; it is not a generic Linux support claim. The
checked-corpus Node path is required. Gate replay and fresh trace generation are
separate optional profiles whose unavailable prerequisites do not silently
degrade into a different mode.

## Profile identifiers

| Profile | Identifier | Requirement |
| --- | --- | --- |
| Local checked-corpus replay | `mirrors.reference-node-checked/ubuntu-24.04-x86_64/v1` | Required initial distribution |
| Restricted Gate replay | `mirrors.reference-node-gate/ubuntu-24.04-x86_64/v1` | Optional component; fail admission if its backend requirements are unavailable |
| Fresh trace generation | `mirrors.reference-fresh-trace/ubuntu-24.04-x86_64/v1` | Optional component; Java/Apalache never become replay prerequisites |

I2 may change spelling only through a reviewed catalog/profile contract; it must
preserve these three capability boundaries.

## Candidate observations

Read-only probes on 2026-09-22 observed:

| Assumption | Observation | Qualification state |
| --- | --- | --- |
| OS and architecture | Ubuntu 24.04.4 LTS, `x86_64` | Exact current userland observed; host is WSL2, so native Ubuntu remains unverified |
| Kernel | `6.6.87.2-microsoft-standard-WSL2` | WSL2-only observation; not the native/hosted Ubuntu kernel profile |
| libc/runtime ABI | glibc 2.39; current Mirrors binaries are x86-64 dynamically linked ELF using `/lib64/ld-linux-x86-64.so.2` | Observed for current local build; minimum portable ABI still requires I2/build qualification |
| OpenSSL | OpenSSL library 3.0.13 | Observed host dependency; exact library linkage/TLS qualification belongs to packaged binaries |
| Filesystem | Repository and `/tmp` are ext4 on the same `/dev/sdd` mount | Same-filesystem atomic rename can be tested here; cross-device, network and overlay filesystems are unqualified |
| Node | Host `v24.19.0`; selected framework pin is 24.15.0 | Host is deliberately not the selected runtime. Distribution must use the content-addressed 24.15.0 tree |
| Python | 3.12.3 | Matches Gate's Python 3.12 family declaration; exact packaged/operator boundary remains explicit below |
| Bubblewrap | Executable reports `bubblewrap built for Codex`, not a SemVer | Cannot prove Gate's >=0.9 requirement from version output |
| Namespace admission | The full user/PID/IPC/UTS/network probe failed inside the command sandbox with `Operation not permitted`, then succeeded when executed outside that sandbox | Host namespace creation is available through the permitted execution path; the full Gate suite and cleanup acceptance were not run in I1 |
| cgroup v2 | Controllers are visible, mount is read-only and root is not writable | No delegated cgroup parent; aggregate-limit acceptance is unavailable here |
| Hosted workflow configuration | Mirrors, MirrorECMA and Gate workflows name `ubuntu-24.04`; Gate shared orchestration also names a self-hosted Linux x64 Bubblewrap runner | Configuration supports the candidate choice but is not installed-consumer evidence |

## Dependency boundary

### Required local checked-corpus profile

| Dependency | Distribution class | Rule |
| --- | --- | --- |
| `ModelMirrors` server and `model_interface_gen` | Bundled, hashed executable artifacts | Exact bytes, product version, source revision, dynamic dependencies and build provenance are recorded |
| `mirrorecma` package and CLI | Bundled, hashed package artifact | Install offline from the distribution cache; verify packed bytes and installed manifest |
| Generated suite module, model-interface lock/manifest and checked corpus | Bundled application artifacts | Preserve compiler target, semantic/provenance digests, source closure and per-occurrence corpus hashes |
| Node 24.15.0 Linux x64 | Content-addressed runtime tree | Admit by full tree identity and provenance; do not select the host's Node 24.19.0 by `PATH` |
| Application adapter and dependencies | Content-addressed application/runtime tree | Prepared explicitly, hashed as admitted content, and kept separate from trusted generated evaluator code |
| glibc loader and required system libraries | Operator-provided host prerequisite for v1 | I2 records the actual ELF requirements and refuses an incompatible host before replay |
| Installation/activation filesystem | Operator-provided host prerequisite | Staging and active target must share a filesystem for atomic rename. Cross-filesystem activation needs an explicit later design and test |

Checked-corpus replay must run without Java, Apalache, a compiler invocation,
source checkouts, network access, package installation, or global build tools.
The compiler artifact can remain installed for separately requested `doctor`,
`check`, or preparation commands, but ordinary replay does not execute it.

### Optional Gate profile

| Dependency | Distribution class | Rule |
| --- | --- | --- |
| Gate supervisor, protocol, Node SDK/runtime shim and MirrorECMA integration | Bundled, hashed artifacts | Preserve package/source identities and protocol/profile versions separately |
| Node 24.15.0 runtime root and application dependencies | Content-addressed runtime trees | Gate policy admits exact roots and hashes; version strings do not identify tree contents |
| Python 3.12, Bubblewrap >=0.9 and approved public `/usr` tree | Operator-provided host prerequisites | Exact executable/runtime observations are recorded at admission; no fallback to raw subprocess execution |
| Linux namespaces, kernel policy and writable temporary/session roots | Operator-provided host prerequisites | Required live admission must pass and produce cleanup evidence |
| Operator Gate policy and delegated roots | Operator-provided configuration | Never bundled with application artifacts; must be owner-controlled and read-only to submitted code |
| Delegated cgroup v2 parent | Operator-provided optional prerequisite | Required only when aggregate guarantees are requested; reject rather than downgrade when absent |

Credentials, private models, expected states, private traces, evaluator policy,
host trust anchors and signing keys are outside all distributed payloads.

### Optional fresh-trace profile

| Dependency | Distribution class | Rule |
| --- | --- | --- |
| Apalache 0.61.0 archive | Bundled or cached content-addressed tool artifact | Verify the selected archive against the pinned SHA-256 before use |
| Java 25.0.4+7 runtime | Content-addressed runtime tree | Record the complete selected runtime identity and license/provenance; never resolve an arbitrary host `java` |
| TLA+ source closure and generation configuration | Bundled trusted inputs | Keep source/provenance identity separate from the checked corpus generated from it |

## Installation and filesystem assumptions

I2/I3 must stage into an owner-only directory, verify every manifest entry before
activation, and activate through same-filesystem rename. The previous complete
manifest remains addressable for rollback. A failed verification or interrupted
stage cannot mutate the active manifest. Symlink traversal, unexpected files,
duplicate paths and case/normalization collisions are rejected before activation.
No portability claim is made for NFS, SMB, case-insensitive filesystems, another
architecture, musl, or a different distribution ABI.

## Required qualification gaps

- Run the installed local profile on a native or hosted Ubuntu 24.04 x86_64
  consumer with source checkouts and global build tools unavailable.
- Record the exact glibc/loader/OpenSSL requirements of the distributed binaries
  and test them against the clean consumer rather than this development tree.
- Exercise same-filesystem upgrade interruption, corruption and rollback. Add a
  deliberate cross-device refusal case.
- Run the Gate profile where Bubblewrap reports a verifiable compatible version
  and namespace admission succeeds. Record kernel and backend cleanup evidence.
- Supply a distinct delegated cgroup fixture before claiming aggregate limits.
- Qualify other OS releases, architectures and filesystems independently; they
  do not inherit this profile's acceptance.

The boundary above is the I1 handoff to I2. Package publication, hosted service
deployment, credential provisioning and cgroup delegation remain separate
operator actions.
