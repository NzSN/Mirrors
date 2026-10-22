#include <mirrorcpp/mirrorcpp.hpp>
#include <cstdlib>
#include <cstdio>
#include <stdexcept>
#include <string>
using namespace mirrorcpp;

static std::string required(const char* name) {
  const char* value = std::getenv(name);
  if (!value) throw std::runtime_error(name);
  return value;
}

int main() {
  const auto mode = required("COMPAT_TRANSPORT");
  const auto scenario = required("COMPAT_CASE");
  std::unique_ptr<Transport> transport;
  if (mode == "stdio") transport = spawn_mirror(required("COMPAT_MIRROR"));
  else if (mode == "tcp") {
    auto result = connect_tcp("127.0.0.1", std::stoi(required("COMPAT_PORT")));
    if (!result) throw std::runtime_error(result.error().message);
    transport = std::move(*result);
  } else {
    TlsOptions options;
    options.ca_path = required("COMPAT_CA"); options.cert_path = required("COMPAT_CERT"); options.key_path = required("COMPAT_KEY");
    options.pin = scenario == "wrong-pin" ? std::string(64, '0') : required("COMPAT_PIN");
    auto result = connect_tls("localhost", std::stoi(required("COMPAT_PORT")), options);
    if (scenario == "wrong-pin") {
      if (!result && result.error().kind == ErrorKind::tls && result.error().message.find("fingerprint mismatch") != std::string::npos) {
        std::puts("{\"outcome\":\"pin_mismatch\",\"calls\":0}"); return 0;
      }
      throw std::runtime_error("wrong pin did not produce a fingerprint mismatch");
    }
    if (!result) throw std::runtime_error(result.error().message);
    transport = std::move(*result);
  }
  if (!transport) throw std::runtime_error("no transport");
  ApalacheConfig config;
  config.spec_path = "Counter.tla"; config.invariant = "TraceComplete";
  config.length_bound = 6; config.param_vars = "parameters"; config.const_init = "CInit";
  int calls = 0;
  auto result = run_client_with_traces(*transport, config, {required("COMPAT_TRACE")},
    [&](std::string_view, const State&, const State&) -> State {
      const int index = calls++;
      const int values[] = {0, 2, 5};
      return {{"count", Value{scenario == "mismatch" && index == 1 ? 99 : values[index]}}};
    });
  if (scenario == "match" && result && calls == 3) std::puts("{\"outcome\":\"match\",\"calls\":3}");
  else if (scenario == "mismatch" && !result && result.error().kind == ErrorKind::step_mismatch && calls == 2)
    std::puts("{\"outcome\":\"step_mismatch\",\"calls\":2}");
  else throw std::runtime_error(result ? "unexpected successful replay" : result.error().message);
}
