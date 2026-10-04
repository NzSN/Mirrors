#pragma once
#include <mirrorcpp/schedule_binding.hpp>
#include <filesystem>
#include <mutex>
#include <set>
#include <string>

namespace dpm_native {
namespace sc = mirrorcpp::schedule;
using nlohmann::json;

struct Context {
  std::unique_ptr<mirrorcpp::Transport> transport;
  json identity;
  json state;
  json transcript = json::array();
  std::string expected_image_sha;
  bool initialized = false;
  bool closed = false;
  bool quit_acknowledged = false;
  long exit_code = -1;
  std::size_t acquisition_count = 0;
  std::size_t cleanup_count = 0;

  json invoke(const json& request) {
    if (!transport) throw std::runtime_error("native transport absent");
    const auto wire = request.dump();
    if (wire.size() > 65'535) throw std::runtime_error("native request exceeds frame bound");
    auto sent = transport->send_line(wire);
    if (!sent) throw std::runtime_error(sent.error().message);
    auto line = transport->recv_line();
    if (!line) throw std::runtime_error(line.error().message);
    auto reply = json::parse(*line);
    transcript.push_back({{"request", request}, {"reply", reply}});
    if (transcript.size() > 512) throw std::runtime_error("native transcript exceeds bound");
    if (reply.contains("error")) throw std::runtime_error(reply.at("error").get<std::string>());
    const auto& actual = reply.at("nativeIdentity");
    if (!initialized) {
      if (!actual.is_object() || actual.at("imageSha256") != expected_image_sha ||
          !actual.at("processId").is_number_unsigned() || actual.at("processId").get<unsigned>() == 0 ||
          !actual.at("createdFileTime").is_string() || actual.at("createdFileTime").get<std::string>().empty())
        throw std::runtime_error("native process/image identity mismatch");
      const auto& actors = actual.at("actors");
      if (!actors.is_object() || actors.size() != 2 || !actors.contains("t1") || !actors.contains("t2") ||
          !actors.at("t1").is_number_unsigned() || !actors.at("t2").is_number_unsigned() ||
          actors.at("t1").get<unsigned>() == 0 || actors.at("t2").get<unsigned>() == 0 || actors.at("t1") == actors.at("t2"))
        throw std::runtime_error("duplicate or invalid native actor identity");
      identity = actual;
      initialized = true;
    } else if (actual != identity) throw std::runtime_error("native actor/process identity changed");
    if (reply.contains("state")) state = reply.at("state");
    return reply;
  }
  void finish() {
    if (closed) return;
    closed = true;
    ++cleanup_count;
    std::string failure;
    if (transport) {
      try {
        const auto reply = invoke({{"op", "Quit"}});
        quit_acknowledged = reply.contains("closed") && reply.at("closed") == true;
        if (!quit_acknowledged) failure = "native Quit acknowledgement missing";
      } catch (const std::exception& error) { failure = error.what(); }
      auto result = transport->close();
      if (result) exit_code = *result;
      else if (failure.empty()) failure = result.error().message;
      transport.reset();
    }
    if (exit_code != 0 && failure.empty()) failure = "native worker did not exit cleanly";
    if (!failure.empty()) throw std::runtime_error(failure);
  }
  json receipt() const {
    return {{"schema", "mirrors.dpm-native-bridge/v1"}, {"identity", identity},
            {"acquisitions", acquisition_count}, {"cleanups", cleanup_count},
            {"quitAcknowledged", quit_acknowledged}, {"exitCode", exit_code},
            {"closed", closed}, {"transcript", transcript}};
  }
  ~Context() { if (transport) { try { finish(); } catch (...) {} } }
};

inline void exact_fields(const json& value, std::initializer_list<std::string_view> fields) {
  if (!value.is_object() || value.size() != fields.size()) throw std::invalid_argument("unknown or missing native mapping fields");
  for (const auto field : fields) if (!value.contains(field)) throw std::invalid_argument("missing native mapping field");
}
inline void validate_mapping(const json& mapping) {
  exact_fields(mapping, {"schema", "profile", "roles", "modelSteps"});
  if (mapping.at("schema") != "mirrors.dpm3-native-mapping/v1" ||
      mapping.at("profile") != "dpm-writesentry-two-operation/v1" ||
      !mapping.at("modelSteps").is_array() || mapping.at("modelSteps").empty() || mapping.at("modelSteps").size() > 150)
    throw std::invalid_argument("unsupported bounded native mapping");
  exact_fields(mapping.at("roles"), {"arm", "write"});
  for (const auto role : {"arm", "write"}) {
    const auto& definition = mapping.at("roles").at(role);
    exact_fields(definition, {"nativeActor", "operation"});
    if ((definition.at("nativeActor") != "t1" && definition.at("nativeActor") != "t2") ||
        definition.at("operation") != (std::string_view(role) == "arm" ? "Arm" : "Write"))
      throw std::invalid_argument("invalid native role declaration");
  }
  const std::set<std::string> phases = {"Reserve", "ArmLock", "ArmSelect", "PublishOdd", "PublishPayload", "PublishEven",
    "ArmUnlock", "ArmTarget", "ArmFinishLock", "ArmFinishUnlock", "ArmOutcome", "Release", "CallDone", "WriteBegin",
    "TrapEntry", "SnapshotProbe", "SnapshotNoAdmission", "SnapshotAdmissionChecked", "SnapshotLease", "SnapshotAdmissionLost",
    "SnapshotAdmissionValidated", "SnapshotSeq1", "SnapshotInvalid", "SnapshotPayload", "SnapshotSeq2", "SnapshotTorn",
    "SnapshotAccepted", "ContextRejected", "OwnerRejected", "LoadRejected", "Filtered", "Hit", "HitReleased", "WriteDone"};
  std::map<std::string, bool> started{{"arm", false}, {"write", false}}, done = started;
  std::map<std::string, std::string> active{{"t1", ""}, {"t2", ""}};
  for (const auto& step : mapping.at("modelSteps")) {
    exact_fields(step, {"role", "request", "parameters"});
    const auto role = step.at("role").get<std::string>();
    if (!started.contains(role) || done.at(role)) throw std::invalid_argument("unknown or reused operation role");
    const auto& parameters = step.at("parameters");
    exact_fields(parameters, {"action", "thread", "command", "address", "value", "writer", "span", "entry", "slot", "target"});
    const auto actor = parameters.at("thread").get<std::string>();
    const auto phase = parameters.at("action").get<std::string>();
    const auto& definition = mapping.at("roles").at(role);
    if (parameters.at("thread") != definition.at("nativeActor") || parameters.at("command") != definition.at("operation") ||
        parameters.at("address") != "A1" || parameters.at("writer") != "allowed" || parameters.at("span") != 1 ||
        parameters.at("value") != (role == "arm" ? "good" : "bad") || !phases.contains(phase))
      throw std::invalid_argument("model input outside native pilot mapping");
    for (const auto key : {"entry", "slot"})
      if (!parameters.at(key).is_number_integer() || parameters.at(key) < 0 || parameters.at(key) > 4)
        throw std::invalid_argument("native index outside four-slot model");
    if (parameters.at("target") != "t1" && parameters.at("target") != "t2" && parameters.at("target") != "noThread")
      throw std::invalid_argument("native target outside mapping");
    const auto& request = step.at("request");
    if (!started.at(role)) {
      exact_fields(request, {"op", "thread", "command", "address", "value", "writer", "span"});
      if (request.at("op") != "Begin" || !active.at(actor).empty() || phase != (role == "arm" ? "Reserve" : "WriteBegin"))
        throw std::invalid_argument("native operation begins while actor active or at wrong phase");
      for (const auto key : {"thread", "command", "address", "value", "writer", "span"})
        if (request.at(key) != parameters.at(key)) throw std::invalid_argument("native/model input disagreement");
      active.at(actor) = role;
      started.at(role) = true;
    } else {
      exact_fields(request, {"op", "thread"});
      if (request.at("op") != "Advance" || request.at("thread") != actor || active.at(actor) != role)
        throw std::invalid_argument("native operation continuation mismatch");
    }
    if (phase == "CallDone") { done.at(role) = true; active.at(actor).clear(); }
  }
  if (!done.at("arm") || !done.at("write")) throw std::invalid_argument("pilot requires completed Arm and Write operations");
}

inline sc::Adapter adapter(const json& mapping, sc::Identity identity,
                           const std::filesystem::path& launcher,
                           const std::shared_ptr<Context>& context) {
  validate_mapping(mapping);
  sc::Adapter result;
  result.identity = std::move(identity);
  result.actors = {{"arm", "native-arm-operation"}, {"write", "native-write-operation"}};
  std::set<std::string> checkpoints;
  std::map<std::string, std::vector<json>> commands;
  for (const auto& step : mapping.at("modelSteps")) {
    const auto actor = step.at("role").get<std::string>();
    commands[actor].push_back(step.at("request"));
    checkpoints.insert(step.at("parameters").at("action").get<std::string>());
  }
  result.checkpoints.assign(checkpoints.begin(), checkpoints.end());
  result.factory = [context, launcher, commands](const json&) {
    if (context->transport || context->acquisition_count) throw std::runtime_error("native bridge is single-use");
    context->transport = mirrorcpp::spawn_mirror(launcher);
    if (!context->transport) throw std::runtime_error("native worker spawn failed");
    ++context->acquisition_count;
    try { context->invoke({{"op", "Initialize"}}); }
    catch (...) { try { context->finish(); } catch (...) {} throw; }
    sc::Program program;
    for (const auto& [actor, requests] : commands) {
      program.workers.push_back({actor, [context, requests](sc::Checkpoint& hook) {
        for (const auto& request : requests) {
          const auto actual = context->invoke(request);
          hook.arrive(actual.at("phase").get<std::string>());
        }
      }});
    }
    program.observe = [context] { return context->state; };
    program.teardown = [context] { context->finish(); };
    return program;
  };
  return result;
}
}  // namespace dpm_native
