use mirrorrust::{ApalacheConfig, Error, State, Value};
use std::env;

fn required(name: &str) -> String { env::var(name).expect(name) }

fn main() {
    let mode = required("COMPAT_TRANSPORT");
    let scenario = required("COMPAT_CASE");
    let connected = match mode.as_str() {
        "stdio" => mirrorrust::spawn_mirror(&required("COMPAT_MIRROR")),
        "tcp" => mirrorrust::connect_mirror("127.0.0.1", required("COMPAT_PORT").parse().unwrap()),
        "tls" => {
            let mut options = mirrorrust::TlsOptions::new(required("COMPAT_CA"), required("COMPAT_CERT"), required("COMPAT_KEY"));
            options.pin = Some(if scenario == "wrong-pin" { "0".repeat(64) } else { required("COMPAT_PIN") });
            mirrorrust::connect_tls_mirror("localhost", required("COMPAT_PORT").parse().unwrap(), &options)
        }
        _ => panic!("unsupported transport"),
    };
    if scenario == "wrong-pin" {
        match connected {
            Err(Error::Tls(message)) if message.contains("fingerprint mismatch") => {
                println!("{{\"outcome\":\"pin_mismatch\",\"calls\":0}}");
                return;
            }
            _ => panic!("wrong pin did not produce a fingerprint mismatch"),
        }
    }
    let mut calls = 0;
    let config = ApalacheConfig {
        spec_path: "Counter.tla".into(), invariant: "TraceComplete".into(), length_bound: 6,
        const_init: Some("CInit".into()), param_vars: Some("parameters".into()),
        init_predicate: None, next_predicate: None,
    };
    let result = mirrorrust::run_client_with_traces_transport(
        connected.unwrap(), config, vec![required("COMPAT_TRACE")],
        |_: &str, _: &State, _: &State| {
            let index = calls;
            calls += 1;
            let value = if scenario == "mismatch" && index == 1 { 99 } else { [0, 2, 5][index] };
            [("count".to_owned(), Value::Int(value.into()))].into_iter().collect()
        },
    );
    match (scenario.as_str(), result) {
        ("match", Ok(())) if calls == 3 => println!("{{\"outcome\":\"match\",\"calls\":3}}"),
        ("mismatch", Err(Error::StepMismatch { .. })) if calls == 2 => println!("{{\"outcome\":\"step_mismatch\",\"calls\":2}}"),
        (_, other) => panic!("unexpected replay result: {other:?}, calls={calls}"),
    }
}
