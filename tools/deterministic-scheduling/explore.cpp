#include "counter_support.hpp"
#include <mirrorcpp/schedule_exploration.hpp>
#include <openssl/evp.h>
#include <fstream>
#include <filesystem>
#include <iostream>
#include <iomanip>
#include <sstream>

namespace fs = std::filesystem;
namespace sc = mirrorcpp::schedule;
using nlohmann::json;
namespace {
std::string hash(std::istream& stream) {
  std::unique_ptr<EVP_MD_CTX, decltype(&EVP_MD_CTX_free)> context(EVP_MD_CTX_new(), EVP_MD_CTX_free);
  if (!context || EVP_DigestInit_ex(context.get(), EVP_sha256(), nullptr) != 1) throw std::runtime_error("hash initialization failed");
  std::array<char, 65'536> buffer{};
  while (stream.read(buffer.data(), buffer.size()) || stream.gcount())
    if (EVP_DigestUpdate(context.get(), buffer.data(), static_cast<std::size_t>(stream.gcount())) != 1) throw std::runtime_error("hash failed");
  std::array<unsigned char, EVP_MAX_MD_SIZE> digest{}; unsigned length = 0;
  if (EVP_DigestFinal_ex(context.get(), digest.data(), &length) != 1 || length != 32) throw std::runtime_error("hash finalization failed");
  std::ostringstream out;
  for (unsigned i = 0; i < length; ++i) out << std::hex << std::setfill('0') << std::setw(2) << static_cast<unsigned>(digest[i]);
  return out.str();
}
std::size_t number(const std::string& text) {
  std::size_t consumed = 0; auto value = std::stoull(text, &consumed);
  if (consumed != text.size() || text.empty() || text[0] == '-') throw std::invalid_argument("invalid unsigned bound");
  return value;
}
}
int main(int argc, char** argv) {
  try {
    fs::path output;
    sc::ExplorationLimits limits;
    std::size_t preemptions = 64;
    std::string mode = "ok";
    bool require_comparison = false;
    for (int i = 1; i < argc; ++i) {
      const std::string key = argv[i];
      if (key == "--require-comparison") { require_comparison = true; continue; }
      if (++i == argc) throw std::invalid_argument("missing argument value");
      const std::string value = argv[i];
      if (key == "--out") output = value;
      else if (key == "--max-runs") limits.max_runs = number(value);
      else if (key == "--max-enumerated") limits.max_enumerated_schedules = number(value);
      else if (key == "--preemptions") preemptions = number(value);
      else if (key == "--time-ms") limits.time_budget = std::chrono::milliseconds(number(value));
      else if (key == "--evidence-bytes") limits.max_evidence_bytes = number(value);
      else if (key == "--mode") mode = value;
      else throw std::invalid_argument("unknown option");
    }
    if (output.empty() || (mode != "ok" && mode != "teardown-fail" && mode != "cancel" && mode != "unexpected-checkpoint"))
      throw std::invalid_argument("invalid exploration invocation");
    std::ifstream executable(fs::canonical(argv[0]), std::ios::binary);
    if (!executable) throw std::runtime_error("cannot hash explorer executable");
    std::istringstream mapping(dpm_counter::expected_mapping().dump());
    sc::Identity identity{std::string(mirrors_generated::scheduledCounter::ScheduledCounterSemanticDigest), hash(mapping), hash(executable)};
    sc::FiniteSpace space;
    space.identity = identity;
    space.actors = {{{"a", "increment-a"}, {"read", "write", "$done"}},
                    {{"b", "increment-b"}, {"read", "write", "$done"}}};
    space.inputs = {json{{"initial", 0}, {"mode", mode}}, json{{"initial", 5}, {"mode", mode}}};
    space.max_preemptions = preemptions;
    space.require_model_comparison = require_comparison;
    space.state_variables = {"count", "saved", "phase"};
    auto stats = std::make_shared<dpm_counter::Stats>();
    auto stop = std::make_shared<std::stop_source>();
    auto result = sc::explore_finite(space, sc::local_exploration_runner(dpm_counter::adapter(identity, stats, stop)), limits, stop->get_token());
    result["actualIdentity"] = {{"modelSemanticDigest", identity.model_semantic_digest}, {"mappingSha256", identity.mapping_sha256},
                                {"implementationSha256", identity.implementation_sha256}};
    result["sut"] = {{"acquisitions", stats->acquired.load()}, {"enteredWorkers", stats->entered.load()}, {"teardowns", stats->disposed.load()}};
    result["mode"] = mode;
    std::ofstream file(output); if (!file) throw std::runtime_error("cannot write exploration report");
    file << result.dump(2) << '\n';
    std::cout << "exploration status=" << result.at("status") << " attempts=" << result.at("attemptedRuns") << '\n';
    return 0; // The acceptance gate requires exact complete/incomplete classifications.
  } catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 2; }
}
