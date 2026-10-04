#include "adapter.hpp"
#include <fstream>
#include <iostream>

namespace sc = mirrorcpp::schedule;
using nlohmann::json;
namespace {
json parameters(const std::string& role, const std::string& phase) {
  return {{"action", phase}, {"thread", role == "arm" ? "t1" : "t2"},
          {"command", role == "arm" ? "Arm" : "Write"}, {"address", "A1"},
          {"value", role == "arm" ? "good" : "bad"}, {"writer", "allowed"},
          {"span", 1}, {"entry", 0}, {"slot", 0}, {"target", "noThread"}};
}
json mapping() {
  json rows = json::array();
  for (const std::string role : {"arm", "write"}) {
    auto p = parameters(role, role == "arm" ? "Reserve" : "WriteBegin");
    json request = {{"op", "Begin"}, {"thread", p["thread"]}, {"command", p["command"]},
                    {"address", p["address"]}, {"value", p["value"]}, {"writer", p["writer"]}, {"span", 1}};
    rows.push_back({{"role", role}, {"request", request}, {"parameters", p}});
    rows.push_back({{"role", role}, {"request", {{"op", "Advance"}, {"thread", p["thread"]}}},
                    {"parameters", parameters(role, "CallDone")}});
  }
  return {{"schema", "mirrors.dpm3-native-mapping/v1"}, {"profile", "dpm-writesentry-two-operation/v1"},
          {"roles", {{"arm", {{"nativeActor", "t1"}, {"operation", "Arm"}}},
                     {"write", {{"nativeActor", "t2"}, {"operation", "Write"}}}}}, {"modelSteps", rows}};
}
void require(bool condition, const char* message) { if (!condition) throw std::runtime_error(message); }
}
int main(int argc, char** argv) {
  try {
    if (argc != 4) throw std::invalid_argument("expected fake worker, mode, report");
    const std::string mode = argv[2];
    auto map = mapping();
    auto context = std::make_shared<dpm_native::Context>();
    context->expected_image_sha = std::string(64, 'a');
    if (mode == "bad-mapping") {
      map["modelSteps"][0]["request"]["thread"] = "unknown";
      bool refused = false;
      try { dpm_native::validate_mapping(map); } catch (const std::exception&) { refused = true; }
      require(refused && context->acquisition_count == 0, "bad mapping acquired a worker");
      std::ofstream(argv[3]) << json{{"passed", true}, {"scope", "synthetic transport control"}}.dump() << '\n';
      return 0;
    }
    sc::Schedule plan;
    plan.identity = {std::string(64, '1'), std::string(64, '2'), std::string(64, '3')};
    for (const auto& step : map["modelSteps"]) {
      const auto role = step["role"].get<std::string>(), phase = step["parameters"]["action"].get<std::string>();
      plan.steps.push_back({role, phase});
      if (phase == "CallDone") plan.steps.push_back({role, "$done"});
    }
    auto execution = sc::run_schedule(plan, dpm_native::adapter(map, plan.identity, argv[1], context));
    const auto report = execution->report();
    require(context->closed && context->transport == nullptr, "synthetic child was not reaped");
    if (mode == "ok") require(report.passed() && context->quit_acknowledged && context->exit_code == 0, "synthetic transport positive failed");
    else {
      require(!report.passed(), "negative synthetic transport accepted");
      if (mode == "unexpected-phase") require(report.outcome == sc::Outcome::unexpected_checkpoint, "missing phase refusal");
      if (mode == "identity-change" || mode == "duplicate-actors" || mode == "crash")
        require(report.outcome == sc::Outcome::application_failed, "missing native protocol failure");
      if (mode == "missing-quit") require(report.cleanup == sc::Cleanup::teardown_failed, "missing cleanup refusal");
    }
    std::ofstream output(argv[3]);
    output << json{{"passed", true}, {"scope", "synthetic transport control; not native execution"},
                   {"scheduler", execution->receipt()}, {"bridge", context->receipt()}}.dump(2) << '\n';
    return 0;
  } catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
}
