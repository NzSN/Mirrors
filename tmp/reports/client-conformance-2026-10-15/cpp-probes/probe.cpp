// Remote-only source probe. No server, subprocess, socket, Gate or model checker.
#include <mirrorcpp/mirrorcpp.hpp>
#include "CounterMirror.generated.hpp"
#include <deque>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

using namespace mirrorcpp;
namespace generated = mirrors_generated::counter;

class FakeTransport final : public Transport {
 public:
  explicit FakeTransport(std::vector<std::string> input)
      : replies(input.begin(), input.end()) {}
  Result<void> send_line(std::string_view line) override {
    writes.emplace_back(line);
    return {};
  }
  Result<std::string> recv_line() override {
    if (replies.empty()) return std::unexpected(Error(ErrorKind::io, "probe exhausted"));
    auto value = std::move(replies.front());
    replies.pop_front();
    return value;
  }
  Result<long> close() override {
    if (!closed) { closed = true; ++close_calls; }
    return 0;
  }
  std::vector<std::string> writes;
  int close_calls = 0;
 private:
  std::deque<std::string> replies;
  bool closed = false;
};

void require(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

nlohmann::json run_case(const std::string& input_code, bool wrong_digest = false) {
  const auto parsed = semantic_digest_from_hex(generated::CounterSemanticDigest);
  require(parsed.has_value(), "generated digest invalid");
  const SemanticDigest digest = *parsed;
  int factory_calls = 0, computer_calls = 0, dispose_calls = 0;
  CompiledAdapterRegistry registry({CompiledAdapterRegistration{
      CompiledAdapterKey{digest, "probe.counter/v1", std::string(mirrorcpp_target_profile),
                         std::string(state_computer_contract_version)},
      [&](const ApalacheConfig&) -> Result<LocalBinding> {
        ++factory_calls;
        if (!input_code.empty())
          return std::unexpected(Error(ErrorKind::model_interface,
                                       "same diagnostic", input_code));
        LocalBinding binding;
        binding.semantic_digest = digest;
        binding.computer = [&](std::string_view, const State&, const State&) {
          ++computer_calls;
          return State{{"count", Value(0)}};
        };
        binding.assert_compatible_config = [](const ApalacheConfig& config) -> Result<void> {
          if (config.param_vars != "parameters")
            return std::unexpected(Error(ErrorKind::model_interface, "bad config"));
          return {};
        };
        binding.dispose = [&]() -> Result<void> { ++dispose_calls; return {}; };
        return binding;
      }}});
  CompiledAdapterSelection selection{
      generated::CounterModelInterface, "probe.counter/v1",
      std::string(mirrorcpp_target_profile), std::string(state_computer_contract_version),
      &registry, NegotiationPolicy::require, std::nullopt};
  const std::string returned_digest = wrong_digest
      ? std::string(64, '0') : std::string(generated::CounterSemanticDigest);
  nlohmann::json first = {
      {"proto_step", "spec_validated"}, {"result", "valid"},
      {"modelInterface", {{"schema", model_interface_negotiation_schema},
          {"status", "matched"}, {"descriptorSchema", model_interface_descriptor_schema},
          {"semanticDigest", "sha256:" + returned_digest}}}};
  FakeTransport transport({first.dump(),
      R"({"proto_step":"initial_state","action":"init","state":{}})",
      R"({"proto_step":"step_ok"})", R"({"proto_step":"all_steps_done"})"});
  ApalacheConfig config;
  config.spec_path = "Counter.tla";
  config.param_vars = "parameters";
  auto result = run_client_with_traces_negotiated(
      transport, config, {"unused-counter.itf.json"}, selection);
  require(transport.close_calls == 1, "flow transport not closed exactly once");
  nlohmann::json row = {{"inputCode", input_code}, {"wrongDigest", wrong_digest},
      {"passed", result.has_value()}, {"factoryCalls", factory_calls},
      {"computerCalls", computer_calls}, {"disposeCalls", dispose_calls},
      {"messagesSent", transport.writes.size()}, {"closeCalls", transport.close_calls}};
  if (result) {
    require(input_code.empty() && !wrong_digest, "unexpected success");
    require(factory_calls == 1 && computer_calls == 1 && dispose_calls == 1 &&
            transport.writes.size() == 2, "normal lifecycle mismatch");
  } else {
    row["kind"] = error_kind_name(result.error().kind);
    row["code"] = result.error().code.value_or("");
    row["message"] = result.error().message;
    row["expectedPresent"] = result.error().expected.has_value();
    row["actualPresent"] = result.error().actual.has_value();
    row["hintsPresent"] = static_cast<bool>(result.error().hints);
    require(computer_calls == 0 && dispose_calls == 0 && transport.writes.size() == 1,
            "negative case reached replay");
    if (wrong_digest) {
      require(factory_calls == 0 && result.error().code == "interface_digest_mismatch",
              "wrong digest did not refuse before factory");
    } else {
      require(factory_calls == 1 && result.error().kind == ErrorKind::model_interface &&
              result.error().code == "adapter_factory_failed" &&
              result.error().message == "same diagnostic",
              "factory failure normalization no longer matches suspected defect");
    }
  }
  return row;
}

int main() {
  try {
    nlohmann::json rows = nlohmann::json::array();
    rows.push_back(run_case(""));
    rows.push_back(run_case("", true));
    for (const char* code : {"mirrorgate.BACKEND_ADMISSION_FAILED",
                            "mirrorgate.WORKER_PROTOCOL_FAILED",
                            "mirrorgate.DEADLINE_EXCEEDED"})
      rows.push_back(run_case(code));
    nlohmann::json report = {
        {"schema", "mirrors.client-guide-cpp-factory-probe/v1"},
        {"scope", "actual public negotiated runner with FakeTransport and generated metadata; no Gate process"},
        {"semanticDigest", generated::CounterSemanticDigest},
        {"rows", rows}, {"factoryErrorCodeCollapseConfirmed", true}};
    std::cout << report.dump(2) << '\n';
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "probe failed: " << error.what() << '\n';
    return 1;
  }
}
