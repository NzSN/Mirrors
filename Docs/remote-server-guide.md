# Using a remote Mirrors server

Start here to deploy Mirrors on one machine and validate models or run application
conformance checks from another. The [application integration guide](application-integration-guide.md)
explains which path your application needs; validation alone does not test a SUT.

## Choose the operation

| Need | Client | Source and lifetime rules |
| --- | --- | --- |
| Validate a local TLA+ model | `ModelMirrors validate`, optionally `--async` | Sends entry module and recursively resolved dependencies inline; keep the connection open |
| Manage validation or trace-generation jobs | MirrorECMA `Connection` | Explicit inline sources or server-visible files; submitting connection owns jobs |
| Check an application against a reviewed corpus | MirrorECMA `runSuite` or project `replay` | Prepare the remote model/corpus paths explicitly; project replay does not upload them |
| Check a restricted implementation | Gate `evaluateSuite` | Trusted evaluator connects to Mirrors; Gate independently owns worker isolation |

## Prepare the server

Build/install the executable following [versioning](versioning.md). Install a
compatible Apalache and Java for validation and trace generation. Set
`APALACHE_MC` to the executable path in the service's environment, not merely in
an interactive shell. Give the service a writable temporary directory; inline
sources, run directories, and backend processes are owned by the server.

Provision a CA trust bundle, a server certificate with the endpoint's DNS or IP
in its SAN, and a separate client certificate/key trusted by that CA. Distribute
client credentials through your deployment's credential management. The CA
private key is not a server runtime dependency. TLS 1.3 and mutual authentication
are required. On POSIX, private key files must have mode `0600`.

```sh
APALACHE_MC=/opt/apalache/bin/apalache-mc \
  ModelMirrors --server 8999 --tls \
    --cert /etc/mirrors/server.crt --key /etc/mirrors/server.key \
    --ca /etc/mirrors/ca.crt --bind 0.0.0.0 --jobs 4
```

Allow client traffic to the chosen port in the host/network firewall. `--jobs`
controls both the connection-worker pool and process-wide async capacity. Idle
connections consume connection workers, so reserve capacity when using separate
observer connections. Plain `--serve` is available for trusted network setups;
it does not provide transport authentication.

For Windows, use a service wrapper such as NSSM around the native executable;
Mirrors does not itself implement the Windows Service Control Manager protocol.
Configure the executable, working directory, arguments, automatic start, logs,
and service environment explicitly. Preserve the packaged OpenSSL DLLs and
`zlib1.dll`; the existing Windows deployment needs zlib during TLS processing.
Ensure the service account can read its credentials, execute Apalache/Java, and
write `TEMP`/`TMP`. Interactive PATH and service PATH can differ.

Before an upgrade, retain the installed executable and dependency hashes, build
and test a staged candidate, then stop, replace, and start the service. Verify the
installed hash and perform a real mTLS validation; service status alone does not
prove a working model checker. Keep a rollback copy until acceptance completes.
The [dated Windows deployment record](windows-deployment-20260918.md) is an
example inventory, not configuration every application should copy.

## Validate from the client machine

```sh
ModelMirrors validate --host mirror.example.com --port 8999 \
  --tls --cert ./pki/client.crt --key ./pki/client.key --ca ./pki/ca.crt \
  --spec ./Main.tla --inv Safe --init Init --next Next --bound 3 --async
```

Use the hostname/IP covered by the server certificate. Optional `--pin` is the
SHA-256 fingerprint of the server leaf certificate. Entry-module dependencies
through `EXTENDS` and `INSTANCE` are resolved recursively from sibling files;
`--dep FILE` adds modules elsewhere. The complete JSONL request must fit 65,535
bytes. Standard-module and resolution details are in the
[CLI source-delivery contract](interface-reference.md#validate-cli-source-delivery).
This behavior does not imply automatic upload for suite replay.

`--async` submits and polls on the same connection. It prints `VALID` (exit 0),
`INVALID` (exit 1), or an infrastructure/protocol error (exit 2). Each await uses
30-second long polls; this is not a total deadline or detached execution. Without
`--async`, the CLI uses synchronous validation. Disconnect cancels and evicts
owned jobs; a second connection can observe a live job but does not take ownership.

## Integrate an application

Use the [MirrorECMA remote guide](../../MirrorECMA/docs/remote-server.md) for
TypeScript transports and concurrent jobs. For application suites, follow
[project remote-path rules](../../MirrorECMA/docs/project-tools.md) and prepare
server-visible models and traces before replay. Model-interface negotiation on
mTLS additionally requires the server's client-fingerprint allowlist; transport
CA authentication alone is insufficient. See the
[negotiation contract](model-interface-runtime-distribution-design.md).

For restricted execution, use the [Gate remote integration guide](../../MirrorGate/docs/remote-mirrors.md).
The trusted evaluator keeps model credentials and private inputs; sandboxed
implementations receive only the public implementation port. A Windows Mirrors
server does not provide a Windows Gate isolation backend.

## Troubleshoot and verify

| Symptom | Check |
| --- | --- |
| Connection refused or timeout | Listening address, port, firewall, service process, and available connection workers |
| TLS failure | TLS 1.3, CA chains, client certificate, server SAN, key permissions, packaged DLLs and pin |
| Backend execution error | Service account's Apalache/Java paths, temporary-directory access, and service logs |
| Missing model or trace | Inline-source selection versus server-visible paths; suite replay does not upload files |
| Model negotiation denied | Explicit client leaf fingerprint allowlist and descriptor-read policy |
| Queue full | Outstanding workers and slots; cancellation can precede physical worker cleanup |
| Job unknown after reconnect | Owner disconnect evicts jobs; job IDs are not durable detached handles |

[Async protocol](interface-reference.md),
[resource model](async-protocol-resource-model.md), and
[Lean proofs](async-resource-lean-proofs.md) explain ownership and guarantees.
The [server resource E2E](async-server-resource-e2e.md) checks real concurrent
mTLS jobs, cleanup and bounded RSS on Linux. It is not a proof of zero runtime
heap leaks and does not provide Windows memory-soak evidence. The optional
`tools/check-validate-remote.py --async` gate exercises a supplied remote JSONL
relay; credentials remain under operator control.
