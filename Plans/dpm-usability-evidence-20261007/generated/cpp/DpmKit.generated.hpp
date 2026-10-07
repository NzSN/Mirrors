// Generated DPM wiring only. Application behavior stays handwritten.
#pragma once
#include <mirrorcpp/schedule.hpp>
#include <stdexcept>
namespace mirrors_generated::dpm_d54bd0b831cdfffd {
inline constexpr std::string_view model_semantic_digest = "d54bd0b831cdfffd1b42ec41e0cd9c71e4ad9374dce7719932a67120faeff3da";
inline constexpr std::string_view mapping_sha256 = "5c37b697b199019fdb8210686c063a155b2841494fa506a92db0b3b57c2067c3";
inline std::vector<mirrorcpp::schedule::ActorDeclaration> actors() { return {{"a","increment-a"},{"b","increment-b"}}; }
inline std::vector<std::string> checkpoints() { return {"read","write"}; }
inline mirrorcpp::schedule::Step step_for(std::string_view actionId, std::string_view actorArgument = {}) {
  if (actionId == "Finish") {
    std::string_view selected = actorArgument;
    if (selected != "a" && selected != "b") throw std::invalid_argument("undeclared kit actor");
    return {std::string(selected), "$done"};
  }
  if (actionId == "Read") {
    std::string_view selected = actorArgument;
    if (selected != "a" && selected != "b") throw std::invalid_argument("undeclared kit actor");
    return {std::string(selected), "read"};
  }
  if (actionId == "Write") {
    std::string_view selected = actorArgument;
    if (selected != "a" && selected != "b") throw std::invalid_argument("undeclared kit actor");
    return {std::string(selected), "write"};
  }
  throw std::invalid_argument("unmapped kit action");
}
}
