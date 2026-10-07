// Generated DPM wiring only. Application behavior stays handwritten.
pub const MODEL_SEMANTIC_DIGEST: &str = "d54bd0b831cdfffd1b42ec41e0cd9c71e4ad9374dce7719932a67120faeff3da";
pub const MAPPING_SHA256: &str = "5c37b697b199019fdb8210686c063a155b2841494fa506a92db0b3b57c2067c3";
pub const ACTORS: &[(&str, &str)] = &[("a","increment-a"),("b","increment-b")];
pub const CHECKPOINTS: &[&str] = &["read","write"];
pub fn step_for(action_id: &str, actor: Option<&str>) -> Result<mirrorrust::schedule::Step, String> {
    match action_id {
        "Finish" => {
            let selected = actor.ok_or("actor argument required")?;
            if !ACTORS.iter().any(|(name, _)| *name == selected) { return Err("undeclared kit actor".into()); }
            Ok(mirrorrust::schedule::Step::new(selected, "$done"))
        }
        "Read" => {
            let selected = actor.ok_or("actor argument required")?;
            if !ACTORS.iter().any(|(name, _)| *name == selected) { return Err("undeclared kit actor".into()); }
            Ok(mirrorrust::schedule::Step::new(selected, "read"))
        }
        "Write" => {
            let selected = actor.ok_or("actor argument required")?;
            if !ACTORS.iter().any(|(name, _)| *name == selected) { return Err("undeclared kit actor".into()); }
            Ok(mirrorrust::schedule::Step::new(selected, "write"))
        }
        _ => Err("unmapped kit action".into()),
    }
}
