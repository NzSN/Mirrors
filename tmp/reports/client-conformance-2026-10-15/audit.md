# Client conformance audit

Date: 2026-10-15. Guide SHA-256: `8017baebdb0a73473107a88b16422311afe84a1e3afa754f58887190fc73c7b4`.

**No: not all inspected clients fully follow the guide.** Six gaps were reproduced remotely, and Haskell has an additional source-confirmed framing-bound gap.

The scope is four client SDKs, the shipped Mirrors CLI clients and the Haskell reference client. Applicable Gate facade requirements are included. This report is the validation update to the preceding static client reports.

| Implementation | Revision | Assessment |
| --- | --- | --- |
| MirrorECMA | `19f6ae6` | Negotiation pairing gap; key-mode contract discrepancy. |
| MirrorCPP | `410c58a` | Gate error-family loss; key-mode contract discrepancy. |
| MirrorRust | `5049e99` | No Rust-specific implementation defect found in static scope; full runtime conformance is not established. |
| MirrorLean | `b8b9491` | TLS identity bypass and source-closure defect; key-mode contract discrepancy. |
| Mirrors CLI | `c17bae9` | Unterminated EOF accepted; cancellation sent after terminal protocol error. |
| Haskell reference | `5ee414e` | Missing framing bounds; reference exceptions and additional compatibility observations. |

## Confirmed implementation gaps

### F1 · P2 · Empty TLS serverName disables SAN identity checks

**Rules:** C25, MI18. **Validation:** remote reproduced.

A caller passes serverName := some "" to the MirrorLean TLS API.

The default and wrong-name controls reject the CA-valid CN-only peer, but the empty override connects. On the SAN-bearing peer, the normal control connects and a wrong name rejects.

An empty configuration value can reduce authentication to CA-chain validation, accepting a peer without the intended SAN identity. This does not demonstrate a fingerprint-pin bypass.

**Repair direction:** Reject an empty effective server name before connection and retain defensive SAN setup in the C shim.

**Source:** [MirrorLean/MirrorLean/ServerMode.lean:111](https://github.com/NzSN/MirrorLean/blob/b8b9491bd96e3126da55d34a7ba3a4493766dcf3/MirrorLean/ServerMode.lean#L111), [MirrorLean/server-mode/native/mirrorlean_tls.c:246](https://github.com/NzSN/MirrorLean/blob/b8b9491bd96e3126da55d34a7ba3a4493766dcf3/server-mode/native/mirrorlean_tls.c#L246)

**Evidence:** [remote/tls-results/server.jsonl](remote/tls-results/server.jsonl), [remote/tls-results/server-cn.jsonl](remote/tls-results/server-cn.jsonl)

### F2 · P2 · Comment markers inside TLA+ strings hide dependencies

**Rules:** C13. **Validation:** remote reproduced.

A valid string literal containing "(*" precedes Helper == INSTANCE Dep.

The control resolves two sources including Dep; the marker case reports success with only the root source and no Dep.

The client can send an incomplete inline EXTENDS/INSTANCE closure for a valid model, leading to downstream registration/compilation failure.

**Repair direction:** Track quoted strings and escapes when stripping comments, then cover marker strings before INSTANCE and EXTENDS declarations.

**Source:** [MirrorLean/MirrorLean/Spec.lean:50](https://github.com/NzSN/MirrorLean/blob/b8b9491bd96e3126da55d34a7ba3a4493766dcf3/MirrorLean/Spec.lean#L50)

**Evidence:** [remote/closure.jsonl](remote/closure.jsonl)

### F3 · P2 · Callback negotiation admits an invalid target/computer pairing

**Rules:** MI4, 9.7. **Validation:** remote reproduced.

Select mirrorecma-v1 with mirrors.async-state-computer/v1 without an explicit execution field.

The invalid callback selection is accepted and invokes factory/computer/dispose once. The same pair with execution: "sync" rejects locally with state_computer_contract_mismatch and zero calls/sends.

One public overload reaches application construction despite an incompatible local computer-contract declaration.

**Repair direction:** Apply the same target/computer-contract pairing admission before transport and factory acquisition across overloads.

**Source:** [MirrorECMA/src/negotiated.ts:226](https://github.com/NzSN/MirrorECMA/blob/19f6ae6ce8d9b073bef888fc66efc4c49f2a07ab/src/negotiated.ts#L226)

**Evidence:** [remote/ecma-result.json](remote/ecma-result.json)

### F4 · P2 · Optional C++ Gate integration loses structured failure families

**Rules:** SO7. **Validation:** remote reproduced.

A post-match factory returns a classified Gate admission, worker-protocol or deadline error.

The actual public runner maps three distinct input codes with identical human text to adapter_factory_failed. Normal replay and wrong-digest zero-factory controls behave correctly.

The optional facade cannot recover the original stable failure family from Error or SandboxEvidence. Base wire compatibility is not disproved by this finding.

**Repair direction:** Preserve trusted original Gate code/stage at the integration boundary while retaining primary failures and ordinary Mirrors mismatch.

**Source:** [MirrorCPP/src/client.cpp:382](https://github.com/NzSN/MirrorCPP/blob/410c58a175c3135d9cd76c85e33a718f63761855/src/client.cpp#L382)

**Evidence:** [remote/cpp-result.json](remote/cpp-result.json), [cpp.json](cpp.json)

Runtime probe uses FakeTransport and classified factory results, not a real Gate process. The actual Gate path and generated invoke/observe error loss are source-traced only.

### F5 · P2 · Built-in CLI accepts a JSON reply without its terminating LF

**Rules:** C1. **Validation:** remote reproduced.

A TCP peer sends a complete spec_validated JSON object without newline and then closes.

Both the valid-LF control and the missing-LF case print VALID and exit 0.

The CLI accepts an unterminated frame that the guide requires it to reject. All four SDKs have strict EOF/LF rejection in their source paths.

**Repair direction:** Reject nonempty buffered bytes at EOF or read failure unless a complete LF-terminated frame was received.

**Source:** [Mirrors/Shell/Transport/Tcp.lean:92](https://github.com/NzSN/Mirrors/blob/c17bae951c4d5bbc5818c2a4f82e2d93d07abc52/Shell/Transport/Tcp.lean#L92), [Mirrors/Shell/Transport/Tls.lean:178](https://github.com/NzSN/Mirrors/blob/c17bae951c4d5bbc5818c2a4f82e2d93d07abc52/Shell/Transport/Tls.lean#L178)

**Evidence:** [remote/cli/summary.json](remote/cli/summary.json)

Plain TCP was reproduced. The analogous TLS receive branch is source evidence only.

### F6 · P2 · Trace capture writes cancel_job after terminal protocol_error

**Rules:** C5, 10. **Validation:** remote reproduced.

An accepted async trace job receives protocol_error in response to await_job.

The recorded exchange is register_trace_gen_async → await_job → cancel_job, with protocol_error before the final write. The CLI retains the original stderr and exits 2.

Cleanup sends another flow message on a connection the guide declares unusable. The original error is not overwritten.

**Repair direction:** Separate local poll-budget cancellation from peer/protocol-terminal failures and cancel only while the connection remains usable.

**Source:** [Mirrors/Shell/TraceCapture.lean:95](https://github.com/NzSN/Mirrors/blob/c17bae951c4d5bbc5818c2a4f82e2d93d07abc52/Shell/TraceCapture.lean#L95)

**Evidence:** [remote/cli/summary.json](remote/cli/summary.json)

### F7 · P2 · Haskell transport paths lack the 65,535-byte bound

**Rules:** C2. **Validation:** source confirmed.

An outgoing registration/state is oversized, or a peer supplies an oversized unterminated line.

sendMsg encodes without a final size check; TCP/stdio line readers and TLS buffer accumulation have no uniform payload cap.

Oversized messages can be emitted and receive memory can grow beyond the mandated bound before JSON parsing.

**Repair direction:** Centralize final encoded-send validation and bounded raw-byte line reads, including UTF-8 boundary controls.

**Source:** [ModelMirros/src/Protocol/Transport/Core.hs:15](https://github.com/NzSN/ModelMirrors/blob/5ee414ee16b8aba50ceb480ac8013a56165272bb/src/Protocol/Transport/Core.hs#L15)

**Evidence:** [haskell.json](haskell.json)

Confirmed by current source inspection; no Haskell runtime or build was run.

## Contract discrepancies

### D1 · Clarify async register_error: failed attempt or terminal connection?

C5 says to stop the session and use a new connection after register_error. Section 10 says it is terminal for that register attempt. The server async dispatcher and all four SDKs intentionally retain the connection after a queue-full rejection. Closing it can cancel other jobs owned by that connection under C6. Reconcile the guide/server contract before changing clients. This ambiguity does not excuse F6: protocol_error is explicitly terminal.

[Mirrors/Docs/client-implementation-guide.md:96](https://github.com/NzSN/Mirrors/blob/c17bae951c4d5bbc5818c2a4f82e2d93d07abc52/Docs/client-implementation-guide.md#L96), [Mirrors/Docs/client-implementation-guide.md:716](https://github.com/NzSN/Mirrors/blob/c17bae951c4d5bbc5818c2a4f82e2d93d07abc52/Docs/client-implementation-guide.md#L716), [Mirrors/Shell/Mirror/Session.lean:900](https://github.com/NzSN/Mirrors/blob/c17bae951c4d5bbc5818c2a4f82e2d93d07abc52/Shell/Mirror/Session.lean#L900)

### D2 · Clarify exact 0600 versus owner-only key permissions

Rust enforces exactly mode & 07777 == 0600. ECMA, C++, Lean, the built-in CLI and Haskell reject group/other access but accept owner-only 0400/0700 and special-bit variants. These do not match the literal rule. Owner-only modes do not by themselves demonstrate private-key exposure; decide whether to enforce the exact mode or document the intended private-only policy.

[Mirrors/Docs/client-implementation-guide.md:274](https://github.com/NzSN/Mirrors/blob/c17bae951c4d5bbc5818c2a4f82e2d93d07abc52/Docs/client-implementation-guide.md#L274), [MirrorRust/src/transport.rs:348](https://github.com/NzSN/MirrorRust/blob/5049e99886a3d1f775e60190478c26e39c9aefc9/src/transport.rs#L348), [Mirrors/Ffi/tls_shim.c:203](https://github.com/NzSN/Mirrors/blob/c17bae951c4d5bbc5818c2a4f82e2d93d07abc52/Ffi/tls_shim.c#L203)

## Additional observations

- **Haskell reply identity correlation:** Public async helpers discard echoed job IDs and accepted job kind. This is a source-confirmed defensive correctness concern, but C17/C23 do not explicitly require an ID-equality check. It is not counted among the seven unambiguous implementation gaps. [ModelMirros/src/Protocol/Client.hs:142](https://github.com/NzSN/ModelMirrors/blob/5ee414ee16b8aba50ceb480ac8013a56165272bb/src/Protocol/Client.hs#L142)
- **Haskell cancel response grammar:** cancelJob accepts job_status only, while the guide permits job_result too. Both current servers return job_status, so this is a source-only compatibility gap for another legal peer response, not a demonstrated current-server regression. [ModelMirros/src/Protocol/Client.hs:183](https://github.com/NzSN/ModelMirrors/blob/5ee414ee16b8aba50ceb480ac8013a56165272bb/src/Protocol/Client.hs#L183)
- **MirrorLean nullable config decoder:** The convenience ApalacheConfig JSON decoder accepts an absent constInit but rejects explicit null. Normal typed outbound requests omit absent fields and remain compliant with C14. The remote closure probe also records this peripheral API difference. [MirrorLean/MirrorLean/Protocol.lean:47](https://github.com/NzSN/MirrorLean/blob/b8b9491bd96e3126da55d34a7ba3a4493766dcf3/MirrorLean/Protocol.lean#L47)
- **Historical Haskell TLS policy:** Case-sensitive fingerprint comparison is a documented reference exception. SAN-only validation through its TLS dependency was not established by this audit; no CN-fallback defect is asserted. [ModelMirros/src-tls/Protocol/Transport/Tls.hs:247](https://github.com/NzSN/ModelMirrors/blob/5ee414ee16b8aba50ceb480ac8013a56165272bb/src-tls/Protocol/Transport/Tls.hs#L247)

## Coverage and limits

- Read-only audit of the inspected checkout revisions. No source fixes or commits were made.
- Six focused findings were reproduced on remote Windows-dev Ubuntu WSL. All compilation and runtime probes ran remotely; no local builds/tests or model checking ran.
- Source-supported cells mean implementation and/or test-source evidence, not a fresh runtime pass or a proof of universal conformance.
- Full SDK suites, the full transport/interop matrix, Haskell runtime, and actual Gate backend failure injection were not rerun.
- MI and SO requirements are conditional on advertised profiles. Descriptor mode is ECMA-only; Lean required verification has no prefer fallback and no Gate facade.
- Caller-owned model inputs, complete manual source closures, observations, deployment policy and tool mediation remain caller/host obligations.
- The per-client raw reports are the preceding static-review snapshots. This aggregate and remote evidence provide their validation update.

The HTML report has the full filterable 342-cell numbered-rule matrix; [audit.json](audit.json) retains every assessment and source reference.

## Client detail reports

- [MirrorECMA static report](ecma.md) · [machine-readable matrix](ecma.json)
- [MirrorCPP static report](cpp.md) · [machine-readable matrix](cpp.json)
- [MirrorRust static report](rust.md) · [machine-readable matrix](rust.json)
- [MirrorLean static report](lean.md) · [machine-readable matrix](lean.json)
- [Mirrors CLI static report](cli.md) · [machine-readable matrix](cli.json)
- [Haskell reference static report](haskell.md) · [machine-readable matrix](haskell.json)

## Related repositories

- **MirrorGate:** Shared orchestration dependency; Node/C++/Rust native facade and integration paths included under SO rules.
- **MirrorExamples / WriteSentry:** Application consumers, not independent client SDKs. Their application-specific adapters and vendored/pinned SDK copies were not separately qualified.
- **tla-connect-rs:** Direct TLA+/Apalache integration, not a client of the Mirrors model protocol.
- **MirrorRegistry:** Documented optional discovery component; no checkout was found under ~/Repos.

## Evidence provenance

All 52 public remote artifacts verify against [the evidence manifest](remote/evidence-manifest.json), SHA-256 `fc2230e541a07c3294b5c6b720674f8600a36570f687aa31255550e0b7d16670`. Source parity covers 33 C++ implementation/header files, all 42 ECMA TypeScript sources, all 66 tracked MirrorLean files, and the 11 relevant built-in CLI files. Existing C++/ECMA/CLI binaries were matched to retained qualified artifact hashes; this is identity evidence, not inherited full conformance credit.

No private keys or build caches were transferred. [Cleanup](remote/cleanup.json) confirms no owned processes remain. No prior source/install/evidence tree was modified.
