# Running Mirrors validation in WSL2

This guide covers a native Linux build of Mirrors inside WSL2, including
access through the development `r_windev` wrapper. Keep the checkout in the WSL
filesystem, such as `$HOME/Repos/Mirrors`, rather than under `/mnt/c` or
`/mnt/d`; this avoids mounted-filesystem build overhead and Linux permission
differences.

## Enter WSL2

From Windows, start the Ubuntu distribution directly:

```console
wsl.exe -d Ubuntu
```

From a host that provides `r_windev`, run a simple WSL command through the
Windows host as follows:

```bash
r_windev ':; MSYS_NO_PATHCONV=1 wsl.exe -d Ubuntu -- uname -a'
```

`MSYS_NO_PATHCONV=1` is required when the remote Windows shell is Git Bash.
Without it, MSYS may rewrite WSL paths such as `/mnt/d` into Windows paths.
Keep the `:;` prefix required by `r_windev` for compound remote commands.

For a multiline operation, put the commands in a script and invoke the script
as one WSL command. This avoids an extra `bash -lc` quoting layer:

```bash
r_windev ':; cat > D:/Services/run-mirrors-wsl.sh' < run-mirrors-wsl.sh
r_windev ':; MSYS_NO_PATHCONV=1 wsl.exe -d Ubuntu -- bash /mnt/d/Services/run-mirrors-wsl.sh'
```

## Prerequisites

Install the Linux development dependencies inside WSL, independently of the
Windows toolchain:

```bash
sudo apt-get update
sudo apt-get install -y build-essential git libssl-dev openssl pkg-config python3
```

Install `elan`, then let the repository's `lean-toolchain` select the pinned
Lean version. Install `apalache-mc` separately and record its absolute path.
Confirm the environment before testing:

```bash
cd "$HOME/Repos/Mirrors"
git rev-parse HEAD
git status --short
lean --version
pkg-config --modversion openssl
command -v apalache-mc
```

If `libssl-dev` cannot be installed system-wide, `OSSL_INC` and `OSSL_LIB` may
point at a complete user-local OpenSSL development tree. It must contain both
the generic and architecture-specific headers. Some Ubuntu OpenSSL shared
libraries are incompatible with the sysroot in a pinned Lean toolchain; an
undefined `GLIBC_2.33` or `GLIBC_2.34` reference from `libcrypto.so` indicates
that environment mismatch. Use a compatible OpenSSL installation or a
user-local static-library overlay rather than changing Mirrors sources.

## Run the complete gate

Use an explicit Apalache path so the live model-checking tiers do not
self-skip:

```bash
cd "$HOME/Repos/Mirrors"
export APALACHE_MC="$HOME/.local/bin/apalache-mc"
lake test 2>&1 | tee "$HOME/mirrors-lake-test-$(git rev-parse HEAD).log"
```

Success requires the final `ALL LAKE TESTS GREEN` line and exit status zero.
Also inspect the log for skipped external tiers and report them separately.
After the run, confirm `git status --short` is empty so build or test tooling
did not modify tracked source or generated fixtures.

## Recorded TF2 acceptance run

The unbounded aggregate run for the TF2 parser acceptance completed on
2026-09-12 in Ubuntu on WSL2 at commit
`a653c9e6172845d4005c25b5e00628cbdc9a5b3a`. It used Lean 4.33.0 and an
explicit `/home/jlc/.local/bin/apalache-mc`, exited zero, emitted
`ALL LAKE TESTS GREEN`, reported no skipped tier, and left the WSL checkout
clean. The run covered the 57-fixture TLA parser corpus together with the full
model-interface, transport, registry, Counter, and async inventory.
