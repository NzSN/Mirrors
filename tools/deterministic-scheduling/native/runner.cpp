#include "WriteSentryMBTMirror.generated.hpp"
#include "adapter.hpp"
#include <openssl/evp.h>
#include <array>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>

namespace fs = std::filesystem;
namespace sc = mirrorcpp::schedule;
namespace g = mirrors_generated::writeSentryMBT;
using nlohmann::json;
using namespace std::chrono_literals;
namespace {
std::string read(const fs::path& path) {
  if (!fs::is_regular_file(path) || fs::file_size(path) > 2 * 1'048'576) throw std::runtime_error("invalid bounded native input");
  std::ifstream file(path, std::ios::binary); if (!file) throw std::runtime_error("cannot open input");
  return {std::istreambuf_iterator<char>(file), {}};
}
std::string hash_stream(std::istream& file) {
  std::unique_ptr<EVP_MD_CTX, decltype(&EVP_MD_CTX_free)> context(EVP_MD_CTX_new(), EVP_MD_CTX_free);
  if (!context || EVP_DigestInit_ex(context.get(), EVP_sha256(), nullptr) != 1) throw std::runtime_error("hash initialization failed");
  std::array<char, 65'536> buffer{};
  while (file.read(buffer.data(), buffer.size()) || file.gcount())
    if (EVP_DigestUpdate(context.get(), buffer.data(), static_cast<std::size_t>(file.gcount())) != 1) throw std::runtime_error("hash update failed");
  std::array<unsigned char, EVP_MAX_MD_SIZE> digest{}; unsigned length = 0;
  if (EVP_DigestFinal_ex(context.get(), digest.data(), &length) != 1 || length != 32) throw std::runtime_error("hash finalization failed");
  std::ostringstream out;
  for (unsigned i = 0; i < length; ++i) out << std::hex << std::setfill('0') << std::setw(2) << static_cast<unsigned>(digest[i]);
  return out.str();
}
std::string sha(const fs::path& path) {
  std::ifstream file(path, std::ios::binary); if (!file) throw std::runtime_error("cannot hash input");
  return hash_stream(file);
}
std::string implementation(const fs::path& self, const fs::path& worker, const fs::path& launcher) {
  std::istringstream record("mirrors.dpm-native-implementation/v1\n" + sha(self) + "\n" + sha(worker) + "\n" + sha(launcher) + "\n");
  return hash_stream(record);
}
class Port final : public g::WriteSentryMBTPort {
 public:
  Port(std::shared_ptr<sc::BindingSession> session, json mapping, std::shared_ptr<std::stop_source> stop, std::string mode)
      : session_(std::move(session)), mapping_(std::move(mapping)), stop_(std::move(stop)), mode_(std::move(mode)) {}
  void initialize() override { index_ = 0; session_->initialize(); }
#define DPM_NATIVE_ACTION(Action, method) void method(const g::Action##Input& input) override { advance(#Action, input); }
#include "actions.inc"
#undef DPM_NATIVE_ACTION
  g::WriteSentryMBTObservation observe() override {
    const auto state = mirrorcpp::decode_state(session_->observation());
    g::WriteSentryMBTObservation observed;
#define FIELD(member, wire) observed.member = g::decode_native<decltype(observed.member)>(state.at(wire), wire)
    FIELD(progress, "progress"); FIELD(disarmConflict, "disarm_conflict"); FIELD(budget, "budget"); FIELD(calls, "calls");
    FIELD(dr, "dr"); FIELD(flags, "flags"); FIELD(locals, "locals"); FIELD(mem, "mem"); FIELD(mutex, "mutex");
    FIELD(operation, "operation"); FIELD(pc, "pc"); FIELD(reg, "reg"); FIELD(result, "result"); FIELD(selected, "selected");
    FIELD(stepCount, "step_count"); FIELD(targets, "targets"); FIELD(tls, "tls"); FIELD(trap, "trap");
#undef FIELD
    return observed;
  }
 private:
  template<class Input> void advance(const char* action, const Input& p) {
    if (index_ >= mapping_.at("modelSteps").size() || p.action != action || p.span != 1 || p.entry < 0 || p.entry > 4 || p.slot < 0 || p.slot > 4)
      throw std::invalid_argument("native generated input outside admitted mapping");
    json parameters = {{"action", p.action}, {"thread", p.thread}, {"command", p.command}, {"address", p.address},
        {"value", p.value}, {"writer", p.writer}, {"span", p.span.template convert_to<int>()},
        {"entry", p.entry.template convert_to<int>()}, {"slot", p.slot.template convert_to<int>()}, {"target", p.target}};
    const auto& next = mapping_.at("modelSteps").at(index_);
    if (parameters != next.at("parameters")) throw std::invalid_argument("model choices differ from frozen native schedule");
    const auto role = next.at("role").get<std::string>();
    if (mode_ == "cancel" && index_ == 1) stop_->request_stop();
    session_->advance({role, action});
    if (std::string_view(action) == "CallDone") session_->advance({role, std::string(sc::completion)});
    ++index_;
  }
  std::shared_ptr<sc::BindingSession> session_;
  json mapping_;
  std::shared_ptr<std::stop_source> stop_;
  std::string mode_;
  std::size_t index_ = 0;
};
struct Options {
  fs::path mirror, model, trace, mapping, schedule, launcher, worker, out;
  std::string mode = "ok";
};
Options options(int argc, char** argv) {
  Options o;
  for (int i = 1; i < argc; ++i) {
    const std::string key = argv[i]; if (++i == argc) throw std::invalid_argument("missing argument");
    const std::string value = argv[i];
    if (key == "--mirror") o.mirror = value; else if (key == "--model") o.model = value;
    else if (key == "--trace") o.trace = value; else if (key == "--mapping") o.mapping = value;
    else if (key == "--schedule") o.schedule = value; else if (key == "--launcher") o.launcher = value;
    else if (key == "--worker") o.worker = value; else if (key == "--out") o.out = value;
    else if (key == "--mode") o.mode = value; else throw std::invalid_argument("unknown argument");
  }
  if (o.mirror.empty() || o.model.empty() || o.trace.empty() || o.mapping.empty() || o.schedule.empty() || o.launcher.empty() || o.worker.empty() || o.out.empty())
    throw std::invalid_argument("missing native runner paths");
  if (o.mode != "ok" && o.mode != "cancel" && o.mode != "wrong-image") throw std::invalid_argument("unknown native control mode");
  return o;
}
}
int main(int argc, char** argv) {
  try {
    const auto o = options(argc, argv);
    const auto mapping = json::parse(read(o.mapping));
    dpm_native::validate_mapping(mapping);
    const auto plan = sc::parse_schedule(read(o.schedule));
    if (plan.inputs != json::object()) throw std::invalid_argument("native concrete inputs must come only from the sealed mapping");
    std::vector<sc::Step> expected;
    for (const auto& step : mapping.at("modelSteps")) {
      const auto role = step.at("role").get<std::string>();
      const auto action = step.at("parameters").at("action").get<std::string>();
      expected.push_back({role, action});
      if (action == "CallDone") expected.push_back({role, std::string(sc::completion)});
    }
    if (plan.steps != expected) throw std::invalid_argument("native/coordinator schedule correspondence differs");
    sc::Identity identity{std::string(g::WriteSentryMBTSemanticDigest), sha(o.mapping), implementation(fs::canonical(argv[0]), o.worker, o.launcher)};
    auto context = std::make_shared<dpm_native::Context>();
    context->expected_image_sha = o.mode == "wrong-image" ? std::string(64, '0') : sha(o.worker);
    auto stop = std::make_shared<std::stop_source>();
    sc::Policy policy; policy.execution_timeout = 240s; policy.cleanup_timeout = 15s;
    auto session = std::make_shared<sc::BindingSession>(plan, dpm_native::adapter(mapping, identity, fs::absolute(o.launcher), context), policy, stop->get_token());
    mirrorcpp::ApalacheConfig config; config.spec_path = fs::absolute(o.model).string(); config.param_vars = "parameters";
    config.init_predicate = "MBTInit"; config.next_predicate = "MBTNext"; config.invariant = "MBTSafety";
    auto digest = mirrorcpp::semantic_digest_from_hex(g::WriteSentryMBTSemanticDigest);
    if (!digest) throw std::runtime_error("invalid generated semantic digest");
    mirrorcpp::CompiledAdapterKey key{*digest, "dpm-native", "mirrorcpp-v2", std::string(mirrorcpp::state_computer_contract_version)};
    mirrorcpp::CompiledAdapterRegistry registry({{key, [session, mapping, stop, mode=o.mode, digest](const auto& cfg) -> mirrorcpp::Result<mirrorcpp::LocalBinding> {
      auto port = std::make_shared<Port>(session, mapping, stop, mode);
      auto generated = g::bind_writeSentryMBT(*port, cfg);
      mirrorcpp::LocalBinding binding;
      binding.semantic_digest = *digest;
      binding.computer = [port, compute=generated.computer](std::string_view action, const auto& input, const auto& prior) {
        return compute(action, input, prior);
      };
      binding.assert_compatible_config = [](const mirrorcpp::ApalacheConfig& config) -> mirrorcpp::Result<void> {
        if (config.param_vars != "parameters") return std::unexpected(mirrorcpp::Error(mirrorcpp::ErrorKind::model_interface, "parameter partition mismatch"));
        return {};
      };
      binding.dispose = [port, session] { return session->dispose(); };
      return binding;
    }}});
    mirrorcpp::CompiledAdapterSelection selection{g::WriteSentryMBTModelInterface, "dpm-native", "mirrorcpp-v2",
      std::string(mirrorcpp::state_computer_contract_version), &registry, mirrorcpp::NegotiationPolicy::require, {}};
    auto transport = mirrorcpp::spawn_mirror(fs::absolute(o.mirror));
    if (!transport) throw std::runtime_error("comparison process spawn failed");
    auto result = sc::replay_with_traces(*transport, config, {fs::absolute(o.trace).string()}, selection, *session);
    (void)transport->close();
    auto evidence = std::move(result.evidence);
    evidence["native"] = context->receipt();
    evidence["mode"] = o.mode;
    evidence["profile"] = "dpm-writesentry-two-operation/v1";
    evidence["fullProductionQualified"] = false;
    evidence["implementationSha256"] = identity.implementation_sha256;
    std::ofstream output(o.out); if (!output) throw std::runtime_error("report write failed");
    output << evidence.dump(2) << '\n';
    std::cout << "native comparison=" << evidence.at("comparison") << " cleanup=" << context->quit_acknowledged << '\n';
    return 0; // Acceptance requires classified evidence, not merely a zero exit.
  } catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 2; }
}
