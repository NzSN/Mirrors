#include "IntegerTablesMirror.generated.hpp"
#include <mirrorcpp/client.hpp>
#include <mirrorcpp/transport.hpp>
#include <iostream>
#include <filesystem>
#include <stdexcept>

namespace generated = mirrors_generated::integerTables;
using mirrorcpp::Value;
using mirrorcpp::State;
using Int = Value::Int;

void require(bool value, const char* message) {
  if (!value) throw std::runtime_error(message);
}

struct Port final : generated::IntegerTablesPort {
  int callbacks = 0;
  int observations = 0;
  Int number = 0;
  void initialize() override { ++callbacks; number = 0; }
  void put(const generated::PutInput& input) override {
    ++callbacks;
    number = input.integerItem + input.stringItem;
  }
  generated::IntegerTablesObservation observe() override {
    ++observations;
    generated::IntegerTablesObservation result;
    result.reg.entries = {{Int(-1), number}, {Int("999999999999999999999999999999999999999"), Int(2)}};
    result.dr.entries = {{"t1", {{{Int(1), true}, {Int(2), false}}}},
                         {"t2", {}}};
    result.tls.entries = {{"t1", {{{Int(1), "ready"}, {Int(2), "idle"}}}},
                          {"t2", {}}};
    return result;
  }
};

State payload() {
  return {{"parameters", Value(Value::Record{{
      {"integers", Value(Value::Map{{{Value(Int("-999999999999999999999999999999999999999")), Value(7)},
                                    {Value(1), Value(11)}}})},
      {"strings", Value(Value::Map{{{Value(std::string("1\0\"\\\n", 5)), Value(3)}}})}}})}};
}

int main(int argc, char** argv) {
  try {
    mirrorcpp::ApalacheConfig config;
    config.param_vars = "parameters";
    Port port;
    auto binding = generated::bind_integerTables(port, config);
    const auto original = payload();
    auto init = binding.computer("init", {}, {});
    auto actual = binding.computer("put", original, init);
    require(port.number == 10 && port.callbacks == 2 && port.observations == 2,
            "typed mapKey dispatch did not reach the application");
    require(original == payload(), "projection mutated the input");

    // The pure generated helpers exercise all map key/value sorts and native ownership.
    auto reg = generated::decode_native<decltype(port.observe().reg)>(actual.at("reg"), "reg");
    require(reg.entries[0].first == -1 && reg.entries[1].first > Int("99999999999999999999"),
            "integer map keys were narrowed");
    auto nested = generated::decode_native<decltype(port.observe().dr)>(actual.at("dr"), "dr");
    require(nested.entries[1].second.entries.empty(), "nested empty map was not preserved");
    auto copied = actual;
    copied.at("reg").get<Value::Map>().entries[0].second = Value(400);
    require(actual.at("reg").get<Value::Map>().entries[0].second == Value(10),
            "map values do not have independent copy ownership");
    auto roundtrip = generated::encode_native(reg, "reg");
    require(roundtrip == actual.at("reg"), "integer map codec round trip failed");

    for (int failure = 0; failure < 6; ++failure) {
      Port untouched;
      auto bad_binding = generated::bind_integerTables(untouched, config);
      bad_binding.computer("init", {}, {});
      auto bad = payload();
      auto& fields = bad.at("parameters").get<Value::Record>().fields;
      auto& entries = fields.at("integers").get<Value::Map>().entries;
      if (failure == 0) entries.clear();
      if (failure == 1) entries.push_back(entries.front());
      if (failure == 2) entries.front().first = Value("-999999999999999999999999999999999999999");
      if (failure == 3) entries.front().second = Value("wrong value");
      if (failure == 4) fields.at("strings").get<Value::Map>().entries.front().first = Value(1);
      if (failure == 5) {
        auto& strings = fields.at("strings").get<Value::Map>().entries;
        strings.push_back(strings.front());
      }
      const int callbacks = untouched.callbacks, observations = untouched.observations;
      try {
        bad_binding.computer("put", bad, {});
        throw std::runtime_error("invalid map input was accepted");
      } catch (const mirrorcpp::ModelInterfaceBindingError& error) {
        require(error.code() == "input_shape_mismatch", "wrong input failure classification");
      }
      require(untouched.callbacks == callbacks && untouched.observations == observations,
              "invalid input invoked an application callback");
    }
    auto duplicate = reg;
    duplicate.entries.push_back(duplicate.entries.front());
    try {
      generated::encode_native(duplicate, "reg");
      throw std::runtime_error("duplicate integer observation key was accepted");
    } catch (const mirrorcpp::ModelInterfaceBindingError& error) {
      require(error.code() == "observation_shape_mismatch", "wrong observation classification");
    }
    if (argc == 3) {
      auto transport = mirrorcpp::spawn_mirror(argv[1]);
      if (!transport) throw std::runtime_error("could not spawn Mirrors replay process");
      Port replay_port;
      auto replay = generated::bind_integerTables(replay_port, config);
      const auto result = mirrorcpp::run_client_with_traces(*transport, config, {argv[2]}, replay.computer);
      if (!result) throw std::runtime_error(result.error().message);
      require(replay_port.callbacks == 2, "server replay did not dispatch both actions");

      config.spec_path = (std::filesystem::path(argv[2]).parent_path() / "IntegerTables.tla").string();
      const auto digest = *mirrorcpp::semantic_digest_from_hex(std::string(generated::IntegerTablesSemanticDigest));
      Port negotiated_port;
      int factories = 0;
      mirrorcpp::CompiledAdapterRegistry registry({{
          {digest, "integer-tables/v2", "mirrorcpp-v2", std::string(mirrorcpp::state_computer_contract_version)},
          [&](const mirrorcpp::ApalacheConfig& candidate) -> mirrorcpp::Result<mirrorcpp::LocalBinding> {
            ++factories;
            auto native = generated::bind_integerTables(negotiated_port, candidate);
            mirrorcpp::LocalBinding local;
            local.semantic_digest = digest;
            local.computer = native.computer;
            local.assert_compatible_config = [](const mirrorcpp::ApalacheConfig& check) -> mirrorcpp::Result<void> {
              if (check.param_vars == "parameters") return {};
              return std::unexpected(mirrorcpp::Error(mirrorcpp::ErrorKind::model_interface,
                  "integer tables require parameters"));
            };
            local.dispose = []() -> mirrorcpp::Result<void> { return {}; };
            return local;
          }}});
      mirrorcpp::CompiledAdapterSelection selection;
      selection.metadata = generated::IntegerTablesModelInterface;
      selection.adapter_id = "integer-tables/v2";
      selection.target_profile = "mirrorcpp-v2";
      selection.registry = &registry;
      auto negotiated_transport = mirrorcpp::spawn_mirror(argv[1]);
      const auto matched = mirrorcpp::run_client_with_traces_negotiated(
          *negotiated_transport, config, {argv[2]}, selection);
      if (!matched) throw std::runtime_error(matched.error().message);
      require(factories == 1 && negotiated_port.callbacks == 2,
              "v2 negotiated replay did not select the exact adapter");
      selection.target_profile = "mirrorcpp-v1";
      auto incompatible_transport = mirrorcpp::spawn_mirror(argv[1]);
      const auto incompatible = mirrorcpp::run_client_with_traces_negotiated(
          *incompatible_transport, config, {argv[2]}, selection);
      require(!incompatible && factories == 1 && negotiated_port.callbacks == 2,
              "incompatible target profile invoked an application factory or callback");
    }
    std::cout << "INTEGER MAP NATIVE GREEN\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
