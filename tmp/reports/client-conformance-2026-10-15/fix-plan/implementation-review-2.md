# Independent implementation review: Gate C++, MirrorCPP and Haskell

Reviewed 2026-10-15. Sources are the owned `/tmp/mirrors-client-fix-20261015/{MirrorGate,MirrorCPP,ModelMirros}` trees against their baseline heads `4a8d0d361589059ad72fe52e05789f302b4b65c8`, `410c58a175c3135d9cd76c85e33a718f63761855` and `5ee414ee16b8aba50ceb480ac8013a56165272bb`. Original sibling checkouts were read only. Scope includes the approved C1/H1/K1 repairs, Haskell reply-correlation/cancellation follow-ups and maintained failure fixtures. No build, runtime probe, test program, network/model operation or source edit was performed by this reviewer.

**Final source-review verdict: no remaining confirmed material findings in these reviewed bytes.** One acceptance-test defect found during review was corrected and rechecked below. Remote compilation, actual execution and source/artifact parity remain required; this is not final implementation acceptance or full guide conformance.

## Corrected finding

**P2 — A timeout could count as explicit negative-test refusal.** The initial Haskell `test/TransportTestSupport.hs` used `bounded (try action)`, allowing an inner broad exception catch to swallow the asynchronous timeout and pass a stalled framing/TLS read. The owner moved `try` outside `timeout` and made `Right Nothing` an assertion failure. A second review identified nested fixture `bounded` timeouts that would still look like ordinary refusal. The final helper throws a dedicated `PeerTimeout`; `expectFailure` and the CN-only observation explicitly reject it as inconclusive infrastructure. Rechecked the helper, export/import and TLS-policy call site. A hanging operation now cannot receive the negative-test credit through either timeout boundary.

## Source boundaries verified

- **Gate diagnostic authority:** SDK/control/worker origins are assigned at their receive boundary. Worker-authored code strings remain application diagnostics and map to `mirrorgate.worker_application` publicly, including forged admission/deadline strings. Only an SDK timeout thrown by the frame-read operation is retried; parsing a worker error happens outside that retry catch. Exact original stage and optional operation ID remain separate from local operation context; diagnostic truncation preserves UTF-8 boundaries.
- **Gate retention and precedence:** invoke/observe preconditions and input encoding enter the first-body snapshot. Closing uses an independent first-cleanup snapshot. The facade captures worker body evidence before generated disposal releases the worker and restores only normalized adapter failure codes. Arbitrary adapter exceptions without a trusted snapshot remain ordinary adapter failures. Registration failures and Mirrors mismatch data remain intact. Body failure wins over cleanup; cleanup after body success fails the operation. Attached control cleanup retains existing non-owned-daemon behavior.
- **Gate maintained evidence seam:** SDK/receipt fixtures exercise same-text distinct families, peer spoofing, local deadlines, malformed observations, pre-dispatch errors and primary-versus-cleanup precedence. The supplied-trace failure harness runs the actual optional facade/controller/worker in owned and attached modes, includes invoke/observe failure variants, actual build/admission rejection, mismatch and a second attached session. It contains no model-generation command. Runtime backend availability, physical cleanup and outcome assertions remain for the remote gate.
- **MirrorCPP keys:** exact low-07777 equals 0600 precedes credentials/connect. Tests use valid disposable key bytes, observed mode readback, retained bytes/modes, real 0600 TLS and an invalid-PEM 0600 credential-loader control. Generic MirrorCPP Error and generated adapter sources are unchanged.
- **Haskell send/receive bounds:** Core checks final Aeson bytes; all three direct built-in sends apply the same bound and raw-LF guard before output. The bytewise Handle reader rejects the 65,536th payload byte without awaiting LF/EOF and closes input on exceptional framing. TLS scans the first LF, retains the suffix, limits retained payload plus a defensively bounded input record and poisons/closes failed input. It does not decode partial UTF-8 chunks. Stdio preserves its nullary constructor and avoids resetting an already binary Handle between coalesced frames.
- **Haskell resource ownership:** TCP listener paths close the Handle that owns the accepted descriptor through `finally`. TLS close/poison releases its backend, and pin failure closes the just-acquired transport. `runAsyncSession` puts the already documented supplied per-session JobStore cleanup in `finally`, rather than expanding cleanup to other stores. The server fixture creates a second store/session to verify survival after the first framing failure.
- **Haskell client follow-ups:** validation/generation accepted kinds and poll/await/cancel echoed IDs are checked before returning data or another request. Cancellation accepts both matching legal status/result shapes with the existing result signature. Wrong replies receive no automatic cancellation/poll continuation. Exact POSIX mode checks cover both TLS constructors; fingerprint case and dependency CN policy remain explicit historical/observational scope.
- **Haskell maintained gate selection:** the five new `*NonModel` groups use actual stdio children, TCP/TLS peers and fake job backends. Their registration/child dispatch is present in Cabal and `test/Main.hs`. Broad existing model-backed groups are separate. Matching compiler/dependency availability, test elaboration, runtime behavior and complete cleanup must still be established remotely.

## Acceptance limits and next action

Use the independently hash-bound corrected sources for remote builds and normal/original-failure/integration gates. Retain executed Haskell test names and TLS dependency policy observations, actual Gate family/cleanup receipts, POSIX filesystem mode readbacks and all source/binary identities. Recheck any file changed after this review, especially compiler/test corrections. This review grants no native Windows/macOS, broad backend, full interop or current-source universal conformance credit.

## Reviewed changed-file hashes

The following SHA-256 inventory freezes the reviewed staged bytes. It includes documentation as well as production/tests. A later differing hash requires an appropriately scoped review update.

<!-- reviewed-hashes -->

### MirrorGate

```text
3d0c1ee8802e180be9c7bb2ba8b36ffa6be332c6e95f36887f1a3fc33a09c126  conformance/control-v1/failure-counter.mjs
448a92f490f965a3c3e9d63ba5804c270d17e9edf911a6b3d93a47fcc16859fe  conformance/control-v1/run-cpp-failures
d83292dbe9468843558545adaf06ed340ae991a195044476f98f72563c56f1e6  integrations/mirrorcpp/README.md
63c1c64224c1d0f28f4d8c594edd0ac23eac3b82aeb6f81f45aab60aecd95786  integrations/mirrorcpp/counter_driver.cpp
9fb2f3a61ea150eba0edc26d80fc23105dd6f338137a36973d74e19a54692d30  integrations/mirrorcpp/orchestration.cpp
ba228a6cf164f121b4ac95e975dee72bb9ce2d65d09d07169be5f2ec488ceb3f  integrations/mirrorcpp/orchestration.hpp
159a4c9a811aff70b0744c142a3adc84795365106db42c23f7f52667bfd0f205  sdk/cpp/README.md
5969e114ab88c9a705d223902759c5cc3fe8fd944e4c3b6a511c70a9f2b4bd83  sdk/cpp/include/mirrorgate/json.hpp
adc6e2a2d963aa746a4775365737d77d453a608c84a758a4d299fbdd2471df40  sdk/cpp/include/mirrorgate/managed_worker.hpp
61e02db7380335b1fe2511bbe16ee96d6bbe3082386de55600380a7b4f0ea368  sdk/cpp/src/control.cpp
3cb495b084e51731071ff6c9e555e4336fc5dc1d852ac616a1b88d1ee11b9b31  sdk/cpp/src/json.cpp
689847008e40a4ff8d250dc619b4a8c620ff4bbe252f7df061923a853fdab088  sdk/cpp/src/managed_worker.cpp
d5979d72c1a14f7143f3c9eeee421c8efaa24f00d3dbef31fc6396538fa2b082  tests/cpp/orchestration_receipt_test.cpp
9986641dae5a6ce0d270d6b7e0cc7a6199580799c5d9efbfb69c1ccbccc0142c  tests/cpp/sdk_test.cpp
```

### MirrorCPP

```text
41f3c90f89b4dd9ad88886e9bac30a5e6747606b32b110653dc13da8494e8f0c  README.md
729f3befe40c85a31323b819397c6f4fda4ab973b902862cdbab0cd37d4207b1  docs/design.md
8490e59e203120eaa246172d8c552cde8bdf469fbb3fef82f65a4c167ea80c9d  src/detail/tls.cpp
d37fc1e067717f3a8942f3163dc5db4a5a97567dd919cd5b6db5dd9cfcdd5836  test/unit/tls_test.cpp
```

### ModelMirros

```text
8cb083241b07b76d2cca80a1e2181377489b73fc31129c7018470ff7e67ac423  ModelMirrors.cabal
0e688624dc5d359f23f4e1e66f9b2cbb4947b4c0d4533d48d2f2588bee53bbd6  docs/transport-framing.md
23d6b57db6d8f0b212e7aeaf3fffcf9028d5cba565d92e5ae5085fb5db6b703b  src-tls/Protocol/Transport/Tls.hs
2ec95a91223dc12fd0cfc4943ce1893b4fa47cacb29d34ddf97c962a5a4aa4f6  src/Protocol/Client.hs
d282f6bfa5aaaf936532837221664e91a4793b8efd913fe0806941ee5fda23aa  src/Protocol/Mirror.hs
3d150ebc85a2521cba61fb9c54877d85dbc35b858537e417c1963647aac00ac6  src/Protocol/Transport/Core.hs
0ecc631076c395f9497570b4a82def9651156401e9d0637dc2280ee4d32993e5  src/Protocol/Transport/Framing.hs
92ef4b74cf9fca2ff7b70f36c211f7cd8609cda180672c3d49766ec9c0e45120  src/Protocol/Transport/Stdio.hs
d3637a7d0e8c0ce338c45b2cdbc05f9cd559eb05b563498a018294cbe0194c43  src/Protocol/Transport/Tcp.hs
7e07aafd36e607c86709ffbbd28bb9f876cf8e7931644a5e5dc4fd4a3f960e87  test/ClientReplySpec.hs
f16788e67564880e57d38f4da1e4037ec1a3cf0c05650b5579d180ff8868a945  test/Main.hs
d6d735c19bfcd1b82c823cf61532a7757b0d436d3723a4fa3126ef72883df7ca  test/ServerFramingSpec.hs
caba6c48b6b6857d0de372ba9d62ada00e6b4e27e3ff93010270396cd00f2a5f  test/StdioTransportSpec.hs
9aa2f50379bcc7caa8f5fac3f9eae7ac3b69fde7c3b5c18cb44392b8c6a69253  test/TlsPolicySpec.hs
e1c71d60cd8392b037dae4481fa7a7d0b8c73b8f9d9407e304f13599ed58e6f1  test/TransportFramingSpec.hs
8baff3e32949dd69a0300ab2f12700582c1eee0e3ea0ad06d664332ea336d058  test/TransportTestSupport.hs
```
