// Copy to your application; this generated seed is not your SUT implementation.
#pragma once
#include "DpmKit.generated.hpp"
#include <mirrorcpp/schedule_binding.hpp>
namespace mirrors_generated::dpm_d54bd0b831cdfffd_example {
inline void initialize(mirrorcpp::schedule::BindingSession& session) { session.initialize(); }
inline void transition(mirrorcpp::schedule::BindingSession& session, std::string_view action, std::string_view actor = {}) {
  session.advance(mirrors_generated::dpm_d54bd0b831cdfffd::step_for(action, actor));
}
// A handwritten typed port calls these after binding admission.
// Supply a deferred factory, actual checkpoint workers and native typed observation.
}
