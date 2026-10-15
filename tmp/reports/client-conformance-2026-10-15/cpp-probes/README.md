# Remote-only C++ SO7 factory normalization probe

Compile and execute **only on remote Windows-dev Ubuntu WSL** using the already built fixed MirrorCPP library and matching headers. Do not build on the coordinator. This is one tiny executable, not a rebuild of MirrorCPP or Gate.

Inputs:

- `probe.cpp` (this directory).
- MirrorCPP `410c58a175c3135d9cd76c85e33a718f63761855` public headers and its existing matching `libmirrorcpp.a` (or shared library).
- That checkout's compiler-generated `test/fixtures/model-interface/counter/generated/CounterMirror.generated.hpp`, used unchanged for the actual Counter digest/contract.
- Matching existing GCC/C++23 toolchain and configured nlohmann JSON/Boost headers.
- Existing OpenSSL and pthread link dependencies if the static library was built with TLS.

Example direct compilation, with all variables pointing at already verified **remote** inputs:

```bash
"$CXX" -std=c++23 -O0 \
  -I"$CPP_SOURCE/include" \
  -I"$CPP_SOURCE/test/fixtures/model-interface/counter/generated" \
  -I"$JSON_INCLUDE" -I"$BOOST_INCLUDE" \
  "$PROBE_DIR/probe.cpp" "$CPP_LIBRARY" \
  -lssl -lcrypto -pthread -o "$PROBE_DIR/probe"
"$PROBE_DIR/probe" > "$PROBE_DIR/result.json"
```

If using an already installed CMake package, a scratch CMake project can use `find_package(mirrorcpp CONFIG REQUIRED)`, link `mirrorcpp::mirrorcpp`, add only the generated fixture include directory, and require C++23. Do not configure the MirrorCPP source or fetch dependencies.

The executable runs five deterministic cases through actual `run_client_with_traces_negotiated`:

1. Valid matched registration and normal replay: factory=1, computer=1, dispose=1, close=1.
2. Wrong returned digest: factory=0, reports=0, close=1.
3. Classified `mirrorgate.BACKEND_ADMISSION_FAILED` factory result.
4. Classified `mirrorgate.WORKER_PROTOCOL_FAILED` factory result.
5. Classified `mirrorgate.DEADLINE_EXCEEDED` factory result.

Cases 3–5 all use identical human diagnostic text. The suspected defect is confirmed only if all return `model_interface/adapter_factory_failed`, with the human text unchanged and no expected/actual/hints payload. Their original structured codes cannot be recovered from another public result field. Every flow transport closes; there are no sockets or child processes.

Scope limitation: this proves the real public SDK's error normalization using fake wire transport and actual generated metadata. It does **not** run a Gate integration/backend or prove worker failure injection. The Gate chain is separately established by source evidence in `../cpp.json`: Gate authorization/acquire/attach errors become the exact classified factory results normalized here. Worker invoke/observe code loss remains source-traced only; no broader Gate rebuild is needed.

Record probe/header/library hashes, compiler identity, command, exit status, stdout/stderr and selected source revision before accepting the result. Success exit 0 means all expected normal/negative behavior and the suspected code collapse were observed; it does not mean conformance to SO7.
