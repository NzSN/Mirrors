// Copy to your application; implement actual behavior outside generated files.
// Include DpmKit.generated.rs as a module named dpm_kit.
use mirrorrust::schedule_binding::BindingSession;
pub fn initialize(session: &mut BindingSession) -> Result<(), String> { session.initialize().map_err(|e| e.to_string()) }
pub fn transition(session: &mut BindingSession, action: &str, actor: Option<&str>) -> Result<(), String> {
    session.advance(&crate::dpm_kit::step_for(action, actor)?).map_err(|e| e.to_string())
}
// Handwritten typed port: convert session observation to its actual native observation type.
// Own deferred workers/checkpoint hooks and disposal; never seed expected model state.
