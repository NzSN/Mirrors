#include <mirrorcpp/schedule_sync.hpp>
#include <iostream>
namespace ss = mirrorcpp::schedule_sync;
int main() {
  using nlohmann::json;
  ss::Policy policy; policy.max_evidence_bytes = 1024;
  ss::Execution* current = nullptr; int calls = 0;
  ss::Adapter adapter{{std::string(64,'a'),std::string(64,'b'),std::string(64,'c')},{"a"},{},[&] {
    ss::Program p; p.workers={{"a",[](ss::Hook&) {}}}; p.teardown=[] {};
    p.observe=[&] {
      if (++calls != 3) return json::object();
      const auto receipt=current->receipt();
      const auto available=policy.max_evidence_bytes-receipt["events"].dump().size()-receipt["observations"].dump().size();
      return json{{"payload",std::string(available-14,'x')}};
    }; return p;
  }};
  auto execution=ss::start(adapter,policy); current=execution.get();
  execution->advance("a"); execution->advance("a");
  const auto cleaned=execution->cleanup(std::chrono::seconds(1));
  const auto receipt=execution->receipt();
  std::cout << json{{"passed",cleaned.passed()},{"outcome",cleaned.outcome},{"limit",policy.max_evidence_bytes},
    {"retainedEventObservationBytes",receipt["events"].dump().size()+receipt["observations"].dump().size()},
    {"receipt",receipt}}.dump() << '\n';
}
