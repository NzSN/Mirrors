#include <mirrorcpp/schedule_sync.hpp>
#include <chrono>
#include <iostream>
#include <map>
#include <memory>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

int main(int argc, char** argv) {
  namespace sync = mirrorcpp::schedule_sync;
  using namespace std::chrono_literals;
  try {
    std::map<std::string, std::string> options;
    for (int index = 1; index < argc; index += 2) {
      if (index + 1 == argc || !options.emplace(argv[index], argv[index + 1]).second)
        throw std::invalid_argument("missing or duplicate option");
    }
    if (options.size() != 5 || !options.contains("--order") || !options.contains("--mutation") ||
        !options.contains("--model-digest") || !options.contains("--mapping-sha256") ||
        !options.contains("--implementation-sha256"))
      throw std::invalid_argument("unknown or missing option");
    const auto order = options.at("--order");
    const auto mutation = options.at("--mutation");
    if ((order != "first" && order != "last") ||
        (mutation != "none" && mutation != "count" && mutation != "fifo" &&
         mutation != "early-unlock" && mutation != "cleanup" && mutation != "deadline"))
      throw std::invalid_argument("unsupported finite fixture variant");
    auto count = std::make_shared<int>(0);
    auto received = std::make_shared<std::vector<std::int64_t>>();
    auto observations = std::make_shared<unsigned>(0);
    sync::Adapter adapter;
    adapter.identity = {options.at("--model-digest"), options.at("--mapping-sha256"),
                        options.at("--implementation-sha256")};
    adapter.actors = {"producer", "consumer"};
    adapter.resources = {{"mutex", sync::Kind::mutex, 0}, {"queue", sync::Kind::queue, 1}};
    adapter.factory = [count, received, observations, mutation] {
      sync::Program program;
      program.workers = {
        {"producer", [count, mutation](sync::Hook& hook) {
          hook.lock("mutex");
          *count += mutation == "count" ? 2 : 1;
          if (mutation == "early-unlock") {
            hook.unlock("mutex"); hook.checkpoint("critical");
          } else {
            hook.checkpoint("critical"); hook.unlock("mutex");
          }
          hook.send("queue", mutation == "fifo" ? 20 : 10);
          hook.send("queue", mutation == "fifo" ? 10 : 20);
        }},
        {"consumer", [count, received](sync::Hook& hook) {
          received->push_back(hook.receive("queue"));
          received->push_back(hook.receive("queue"));
          hook.lock("mutex"); ++*count; hook.checkpoint("critical"); hook.unlock("mutex");
        }}
      };
      program.observe = [count, received, observations, mutation] {
        if (mutation == "deadline" && ++*observations == 2) std::this_thread::sleep_for(50ms);
        return nlohmann::json{{"count", *count}, {"received", *received}};
      };
      program.teardown = [mutation] {
        if (mutation == "cleanup") throw std::runtime_error("controlled teardown mutation");
      };
      return program;
    };
    sync::Policy policy;
    policy.max_decisions = 32;
    policy.max_evidence_bytes = 65536;
    policy.execution_timeout = mutation == "deadline" ? 20ms : 2000ms;
    auto execution = sync::start(std::move(adapter), policy);
    for (unsigned step = 0; step < 32 && !execution->report().finished; ++step) {
      const auto enabled = execution->enabled();
      if (enabled.empty()) break;
      const auto actor = order == "first" ? enabled.front() : enabled.back();
      if (execution->advance(actor).outcome != "completed") break;
    }
    const auto report = execution->cleanup(1000ms);
    std::cout << execution->receipt().dump() << '\n';
    return report.passed() ? 0 : 2;
  } catch (const std::exception& error) {
    std::cerr << "controlled model fixture refused: " << error.what() << '\n';
    return 2;
  }
}
