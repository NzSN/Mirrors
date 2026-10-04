#pragma once
#include "ScheduledCounterMirror.generated.hpp"
#include <mirrorcpp/schedule_binding.hpp>
#include <array>
#include <atomic>
#include <memory>
namespace dpm_counter {
namespace sc = mirrorcpp::schedule;
namespace generated = mirrors_generated::scheduledCounter;
using nlohmann::json;
struct Stats {
  std::atomic<int> acquired{0}, entered{0}, disposed{0};
};
inline json expected_mapping() {
  return {{"schema", "mirrors.dpm-counter-mapping/v1"}, {"profile", sc::profile},
          {"actors", json::array({{{"actor", "a"}, {"operation", "increment-a"}},
                                   {{"actor", "b"}, {"operation", "increment-b"}}})},
          {"actions", {{"read", "read"}, {"write", "write"}, {"finish", "$done"}}}};
}
inline json big(int value) { return {{"#bigint", std::to_string(value)}}; }
inline json mapping(const std::array<int, 2>& values) {
  return {{"#map", json::array({json::array({"a", big(values[0])}), json::array({"b", big(values[1])})})}};
}
inline sc::Adapter adapter(sc::Identity identity, const std::shared_ptr<Stats>& stats,
                    const std::shared_ptr<std::stop_source>& stop) {
  sc::Adapter value;
  value.identity = std::move(identity);
  value.actors = {{"a", "increment-a"}, {"b", "increment-b"}};
  value.checkpoints = {"read", "write"};
  value.factory = [stats, stop](const json& inputs) {
    const auto initial = inputs.at("initial").get<int>();
    if (initial != 0 && initial != 5) throw std::invalid_argument("unsupported initial fixture input");
    const auto mode = inputs.at("mode").get<std::string>();
    struct State { int count; std::array<int, 2> saved{0, 0}, phase{0, 0}; };
    auto state = std::make_shared<State>(State{initial});
    ++stats->acquired;
    sc::Program program;
    for (int index = 0; index < 2; ++index) {
      program.workers.push_back({index == 0 ? "a" : "b", [state, stats, index, mode](sc::Checkpoint& hook) {
        ++stats->entered;
        const int saved = state->count;
        state->saved[index] = saved;
        state->phase[index] = 1;
        hook.arrive(mode == "unexpected-checkpoint" ? "wrong" : "read");
        state->count = saved + (mode == "mutate" || mode == "mutate-and-teardown-fail" ? 2 : 1);
        state->phase[index] = 2;
        hook.arrive("write");
        state->phase[index] = 3;
      }});
    }
    program.observe = [state, mode, stop] {
      if (mode == "cancel" && state->phase[0] == 1) stop->request_stop();
      json observed = {{"count", big(state->count)}, {"saved", mapping(state->saved)}, {"phase", mapping(state->phase)}};
      if (mode == "bad-observation") observed["count"] = "not-an-integer";
      return observed;
    };
    program.teardown = [stats, mode] {
      ++stats->disposed;
      if (mode == "teardown-fail" || mode == "mutate-and-teardown-fail") throw std::runtime_error("deliberate SUT teardown failure");
    };
    return program;
  };
  return value;
}
class Port final : public generated::ScheduledCounterPort {
 public:
  explicit Port(std::shared_ptr<sc::BindingSession> session, std::string mode)
      : session_(std::move(session)), mode_(std::move(mode)) {}
  void initialize() override { session_->initialize(); }
  void read(const generated::ReadInput& input) override {
    if (mode_ == "reentrant") {
      try { reenter("read", mirrorcpp::decode_state(json{{"parameters", {{"actor", input.actor}}}}), {}); }
      catch (const mirrorcpp::ModelInterfaceBindingError&) {}
      return;
    }
    session_->advance({input.actor, "read"});
  }
  void write(const generated::WriteInput& input) override { session_->advance({input.actor, "write"}); }
  void finish(const generated::FinishInput& input) override { session_->advance({input.actor, "$done"}); }
  generated::ScheduledCounterObservation observe() override {
    const auto actual = mirrorcpp::decode_state(session_->observation());
    generated::ScheduledCounterObservation observed;
    observed.count = generated::decode_native<decltype(observed.count)>(actual.at("count"), "count");
    observed.phase = generated::decode_native<decltype(observed.phase)>(actual.at("phase"), "phase");
    observed.saved = generated::decode_native<decltype(observed.saved)>(actual.at("saved"), "saved");
    return observed;
  }
  mirrorcpp::StateComputer reenter;
 private:
  std::shared_ptr<sc::BindingSession> session_;
  std::string mode_;
};

}  // namespace dpm_counter
