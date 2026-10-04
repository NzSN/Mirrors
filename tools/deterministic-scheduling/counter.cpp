#include "counter_support.hpp"
#include <mirrorcpp/schedule_binding.hpp>
#include <openssl/evp.h>
#include <array>
#include <atomic>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>

namespace fs = std::filesystem;
namespace sc = mirrorcpp::schedule;
namespace generated = mirrors_generated::scheduledCounter;
using nlohmann::json;
using namespace std::chrono_literals;
namespace {
std::string read(const fs::path& path, std::uintmax_t limit = 1'048'576) {
  if (!fs::is_regular_file(path) || fs::file_size(path) > limit) throw std::runtime_error("invalid bounded input file");
  std::ifstream file(path, std::ios::binary);
  if (!file) throw std::runtime_error("cannot read input file");
  return {std::istreambuf_iterator<char>(file), {}};
}
std::string sha(const fs::path& path) {
  std::ifstream file(path, std::ios::binary);
  if (!file) throw std::runtime_error("cannot hash artifact");
  std::unique_ptr<EVP_MD_CTX, decltype(&EVP_MD_CTX_free)> context(EVP_MD_CTX_new(), EVP_MD_CTX_free);
  if (!context || EVP_DigestInit_ex(context.get(), EVP_sha256(), nullptr) != 1) throw std::runtime_error("SHA initialization failed");
  std::array<char, 65'536> buffer{};
  while (file.read(buffer.data(), buffer.size()) || file.gcount())
    if (EVP_DigestUpdate(context.get(), buffer.data(), static_cast<std::size_t>(file.gcount())) != 1)
      throw std::runtime_error("SHA update failed");
  std::array<unsigned char, EVP_MAX_MD_SIZE> bytes{}; unsigned count = 0;
  if (EVP_DigestFinal_ex(context.get(), bytes.data(), &count) != 1 || count != 32) throw std::runtime_error("SHA finalization failed");
  std::ostringstream out;
  for (unsigned i = 0; i < count; ++i) out << std::hex << std::setfill('0') << std::setw(2) << static_cast<unsigned>(bytes[i]);
  return out.str();
}
using dpm_counter::Stats;
using dpm_counter::Port;
using dpm_counter::adapter;
using dpm_counter::expected_mapping;
using dpm_counter::big;
struct Options { fs::path mirror, spec, trace, schedule, mapping, out; int repeats = 1; };
Options options(int count, char** argv) {
  Options o;
  for (int i = 1; i < count; ++i) {
    const std::string key = argv[i];
    if (++i == count) throw std::invalid_argument("missing argument value");
    const std::string value = argv[i];
    if (key == "--mirror") o.mirror = value;
    else if (key == "--spec") o.spec = value;
    else if (key == "--trace") o.trace = value;
    else if (key == "--schedule") o.schedule = value;
    else if (key == "--mapping") o.mapping = value;
    else if (key == "--out") o.out = value;
    else if (key == "--repeats") o.repeats = std::stoi(value);
    else throw std::invalid_argument("unknown option");
  }
  if (o.mirror.empty() || o.spec.empty() || o.trace.empty() || o.schedule.empty() || o.mapping.empty() || o.out.empty() || o.repeats < 1 || o.repeats > 4)
    throw std::invalid_argument("required bounded runner options missing");
  return o;
}
}  // namespace

int main(int argc, char** argv) {
  try {
    const auto o = options(argc, argv);
    if (json::parse(read(o.mapping)) != expected_mapping()) throw std::invalid_argument("unsupported mapping artifact");
    auto plan = sc::parse_schedule(read(o.schedule));
    const auto mode = plan.inputs.at("mode").get<std::string>();
    const std::set<std::string> modes = {"ok", "mutate", "teardown-fail", "mutate-and-teardown-fail", "bad-observation",
      "wrong-identity", "denied-negotiation", "unexpected-checkpoint", "cancel", "malformed-input", "reentrant"};
    if (!modes.contains(mode)) throw std::invalid_argument("unsupported fixture mode");
    sc::Identity identity{std::string(generated::ScheduledCounterSemanticDigest), sha(o.mapping), sha(fs::canonical(argv[0]))};
    auto stats = std::make_shared<Stats>();
    auto stop = std::make_shared<std::stop_source>();
    sc::Policy policy; policy.execution_timeout = 30s;
    auto session = std::make_shared<sc::BindingSession>(plan, adapter(identity, stats, stop), policy, stop->get_token());
    mirrorcpp::ApalacheConfig config; config.spec_path = fs::absolute(o.spec).string(); config.param_vars = "parameters";
    config.init_predicate = plan.inputs.at("initial") == 5 ? "InitFive" : "Init"; config.next_predicate = "Next"; config.invariant = "Safety"; config.length_bound = 6;
    json evidence;
    if (mode == "malformed-input" || mode == "reentrant") {
      auto port = std::make_shared<Port>(session, mode);
      auto binding = generated::bind_scheduledCounter(*port, config);
      port->reenter = binding.computer;
      (void)binding.computer("init", {}, {});
      std::string first, second;
      const auto payload = mode == "malformed-input" ? json{{"parameters", {{"actor", big(1)}}}} : json{{"parameters", {{"actor", "a"}}}};
      try { (void)binding.computer("read", mirrorcpp::decode_state(payload), {}); }
      catch (const mirrorcpp::ModelInterfaceBindingError& error) { first = error.code(); }
      try { (void)binding.computer("read", mirrorcpp::decode_state(json{{"parameters", {{"actor", "a"}}}}), {}); }
      catch (const mirrorcpp::ModelInterfaceBindingError& error) { second = error.code(); }
      auto cleanup = session->dispose();
      evidence = {{"schema", "mirrors.scheduled-binding-control/v1"}, {"firstError", first}, {"secondError", second},
                  {"cleanupSucceeded", cleanup.has_value()}, {"binding", session->receipt()}};
    } else {
      auto digest = mirrorcpp::semantic_digest_from_hex(generated::ScheduledCounterSemanticDigest);
      if (!digest) throw std::runtime_error("generated semantic digest invalid");
      mirrorcpp::CompiledAdapterKey key{*digest, "dpm-counter", "mirrorcpp-v1", std::string(mirrorcpp::state_computer_contract_version)};
      mirrorcpp::CompiledAdapterRegistry registry({{key, [session, mode, digest](const mirrorcpp::ApalacheConfig& config) -> mirrorcpp::Result<mirrorcpp::LocalBinding> {
        auto port = std::make_shared<Port>(session, mode);
        auto bound = generated::bind_scheduledCounter(*port, config);
        mirrorcpp::LocalBinding binding;
        binding.semantic_digest = *digest;
        binding.computer = [port, compute = bound.computer](std::string_view action, const auto& inputs, const auto& prior) {
          return compute(action, inputs, prior);
        };
        binding.assert_compatible_config = [](const mirrorcpp::ApalacheConfig& cfg) -> mirrorcpp::Result<void> {
          if (cfg.param_vars != "parameters") return std::unexpected(mirrorcpp::Error(mirrorcpp::ErrorKind::model_interface, "parameters mismatch"));
          return {};
        };
        binding.dispose = [port, session] { return session->dispose(); };
        return binding;
      }}});
      auto metadata = generated::ScheduledCounterModelInterface;
      if (mode == "denied-negotiation") metadata.semantic_digest = std::string(64, 'f');
      mirrorcpp::CompiledAdapterSelection selection{metadata, "dpm-counter", "mirrorcpp-v1", std::string(mirrorcpp::state_computer_contract_version), &registry, mirrorcpp::NegotiationPolicy::require, {}};
      auto transport = mirrorcpp::spawn_mirror(fs::absolute(o.mirror));
      if (!transport) throw std::runtime_error("comparison process spawn failed");
      const std::vector<std::string> traces(static_cast<std::size_t>(o.repeats), fs::absolute(o.trace).string());
      auto result = sc::replay_with_traces(*transport, config, traces, selection, *session);
      evidence = std::move(result.evidence);
      (void)transport->close();
    }
    evidence["mode"] = mode;
    evidence["actualIdentity"] = {{"modelSemanticDigest", identity.model_semantic_digest}, {"mappingSha256", identity.mapping_sha256}, {"implementationSha256", identity.implementation_sha256}};
    evidence["sut"] = {{"acquisitions", stats->acquired.load()}, {"enteredWorkers", stats->entered.load()}, {"teardowns", stats->disposed.load()}};
    std::ofstream output(o.out); if (!output) throw std::runtime_error("report output failed"); output << evidence.dump(2) << '\n';
    // The harness requires exact classifications, not exit zero alone.
    std::cout << evidence.at("schema") << " " << mode << '\n';
    return 0;
  } catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 2; }
}
