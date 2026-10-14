#include <mirrorcpp/schedule_sync.hpp>
#include <chrono>
#include <iostream>
#include <memory>
#include <thread>
int main() {
  namespace sync = mirrorcpp::schedule_sync;
  using namespace std::chrono_literals;
  sync::Adapter adapter;
  adapter.identity = {std::string(64,'1'), std::string(64,'2'), std::string(64,'3')};
  adapter.actors = {"a"};
  adapter.factory = [] {
    auto observations = std::make_shared<int>(0);
    sync::Program program;
    program.workers = {{"a", [](sync::Hook&) {}}};
    program.observe = [observations] {
      if (++*observations == 3) std::this_thread::sleep_for(250ms);
      return nlohmann::json{{"observations", *observations}};
    };
    program.teardown = [] { std::this_thread::sleep_for(150ms); };
    return program;
  };
  sync::Policy policy; policy.execution_timeout = 100ms;
  auto execution = sync::start(std::move(adapter), policy);
  while (!execution->enabled().empty()) execution->advance("a");
  execution->cleanup(1ms);
  auto receipt = execution->receipt();
  std::cout << receipt.dump() << '\n';
  return receipt["passed"] == false && receipt["outcome"] == "timed_out" &&
    receipt["cleanup"] == "confirmed" && receipt["budgetExceeded"]["execution"] == true &&
    receipt["budgetExceeded"]["cleanup"] == true ? 0 : 1;
}
