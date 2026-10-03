//! Small generated-binding consumer. The Python owner supplies exact build/input
//! paths and validates these observed outcomes; an error alone is never a pass.
#![allow(dead_code)]

mod counter {
    include!(env!("MIRRORS_GENERATED_COUNTER_RS"));
}

use mirrorrust::{
    ApalacheConfig, ApalacheSpec, BindingError, CompiledAdapterKey, CompiledAdapterRegistration,
    CompiledAdapterRegistry, CompiledAdapterSelection, Error, NegotiatedError, NegotiationPolicy,
    SemanticDigest, State, TlsOptions, TraceGenerationConfig, Transport, Value,
    STATE_COMPUTER_CONTRACT_VERSION,
};
use num_bigint::BigInt;
use serde_json::{json, Value as Json};
use std::{cell::RefCell, env, rc::Rc};

#[derive(Default)]
struct Recording {
    factories: usize,
    drops: usize,
    events: Vec<&'static str>,
    observations: Vec<String>,
    strides: Vec<String>,
}

struct Counter {
    count: BigInt,
    faulty_observer: bool,
    recording: Rc<RefCell<Recording>>,
}

impl counter::CounterPort for Counter {
    fn initialize(&mut self) -> Result<(), BindingError> {
        self.recording.borrow_mut().events.push("Initialize");
        self.count = 0.into();
        Ok(())
    }

    fn tick(&mut self, input: counter::TickInput) -> Result<(), BindingError> {
        let mut recording = self.recording.borrow_mut();
        recording.events.push("Tick");
        recording.strides.push(input.stride.to_string());
        self.count += input.stride;
        Ok(())
    }

    fn observe(&mut self) -> Result<counter::CounterObservation, BindingError> {
        let count = if self.faulty_observer {
            &self.count + 1
        } else {
            self.count.clone()
        };
        let mut recording = self.recording.borrow_mut();
        recording.events.push("Observe");
        recording.observations.push(count.to_string());
        Ok(counter::CounterObservation { count })
    }
}

impl Drop for Counter {
    fn drop(&mut self) {
        self.recording.borrow_mut().drops += 1;
    }
}

fn required(name: &str) -> Result<String, NegotiatedError> {
    env::var(name).map_err(|_| {
        Error::InvalidArgument(format!("missing harness environment name: {name}")).into()
    })
}

fn connect(transport: &str, case: &str) -> Result<Transport, NegotiatedError> {
    match transport {
        "stdio" => Ok(mirrorrust::spawn_mirror(&required(
            "GENERATED_RUST_MIRROR_BIN",
        )?)?),
        "tcp" | "tls" => {
            let host = required("GENERATED_RUST_HOST")?;
            let port: u16 = required("GENERATED_RUST_PORT")?
                .parse()
                .map_err(|_| Error::InvalidArgument("invalid harness port".into()))?;
            if transport == "tcp" {
                return Ok(mirrorrust::connect_mirror(&host, port)?);
            }
            let mut tls = TlsOptions::new(
                required("MIRRORS_REMOTE_CA")?,
                required("MIRRORS_REMOTE_CLIENT_CERT")?,
                required("MIRRORS_REMOTE_CLIENT_KEY")?,
            );
            tls.pin = Some(if case == "wrong-pin" {
                "0".repeat(64)
            } else {
                required("MIRRORS_REMOTE_SERVER_PIN")?
            });
            Ok(mirrorrust::connect_tls_mirror(&host, port, &tls)?)
        }
        _ => Err(Error::InvalidArgument("unknown harness transport".into()).into()),
    }
}

fn execute(
    transport_name: &str,
    case: &str,
    recording: Rc<RefCell<Recording>>,
) -> Result<Option<String>, (NegotiatedError, Option<String>)> {
    let run = || -> Result<(Transport, ApalacheConfig), NegotiatedError> {
        let config = ApalacheConfig {
            spec_path: if transport_name == "tls" {
                "Counter.tla".into()
            } else {
                required("GENERATED_RUST_SPEC")?
            },
            init_predicate: Some("Init".into()),
            next_predicate: Some("Next".into()),
            const_init: Some("CInit".into()),
            invariant: "TraceComplete".into(),
            length_bound: 6,
            param_vars: Some("parameters".into()),
        };
        Ok((connect(transport_name, case)?, config))
    };
    let (transport, config) = run().map_err(|error| (error, None))?;
    let peer = transport.peer_fingerprint().map(str::to_owned);
    let expected_digest = if case == "wrong-digest" {
        "0".repeat(64)
    } else {
        counter::SEMANTIC_DIGEST.to_owned()
    };
    let digest =
        SemanticDigest::from_hex(&expected_digest).map_err(|error| (error, peer.clone()))?;
    let mut metadata = counter::model_interface();
    metadata.semantic_digest = expected_digest;
    let faulty_observer = case == "faulty-observer";
    let mut registry = CompiledAdapterRegistry::new(vec![CompiledAdapterRegistration {
        key: CompiledAdapterKey {
            semantic_digest: digest,
            adapter_id: "generated-rust-counter-acceptance".into(),
            target_profile: "mirrorrust-v1".into(),
            state_computer_contract_version: STATE_COMPUTER_CONTRACT_VERSION.into(),
        },
        factory: Box::new(move |context| {
            recording.borrow_mut().factories += 1;
            // The SUT is constructed only inside this deferred matched factory.
            let port = Counter {
                count: 0.into(),
                faulty_observer,
                recording: recording.clone(),
            };
            counter::bind_counter(port, context.effective_config())?.into_local_binding()
        }),
    }]);
    let mut selection = CompiledAdapterSelection {
        metadata,
        adapter_id: "generated-rust-counter-acceptance".into(),
        target_profile: "mirrorrust-v1".into(),
        state_computer_contract_version: STATE_COMPUTER_CONTRACT_VERSION.into(),
        registry: &mut registry,
        policy: NegotiationPolicy::Require,
        fallback_factory: None,
    };
    let result = if transport_name == "tls" {
        let source = required("GENERATED_RUST_SPEC")
            .and_then(|path| std::fs::read_to_string(path).map_err(NegotiatedError::from));
        match source {
            Ok(source) => mirrorrust::run_client_negotiated_transport(
                transport,
                config,
                TraceGenerationConfig {
                    num_traces: 1,
                    view: Some("View".into()),
                },
                &mut selection,
                Some(ApalacheSpec {
                    sources: vec![source],
                }),
            ),
            Err(error) => Err(error),
        }
    } else {
        match required("GENERATED_RUST_TRACE") {
            Ok(trace) => mirrorrust::run_client_with_traces_negotiated_transport(
                transport,
                config,
                vec![trace],
                &mut selection,
            ),
            Err(error) => Err(error),
        }
    };
    result.map(|()| peer.clone()).map_err(|error| (error, peer))
}

fn count(state: &State) -> Option<String> {
    match state.get("count") {
        Some(Value::Int(value)) => Some(value.to_string()),
        _ => None,
    }
}

fn failure(error: &NegotiatedError) -> Json {
    match error {
        NegotiatedError::Legacy(Error::StepMismatch {
            action,
            expected,
            actual,
            ..
        }) => json!({
            "kind": "step_mismatch", "action": action,
            "expectedCount": count(expected), "actualCount": count(actual),
        }),
        NegotiatedError::Registration { code, .. } => {
            json!({"kind": "registration_error", "code": code})
        }
        NegotiatedError::ModelInterface { code, .. } => {
            json!({"kind": "model_interface_error", "code": code})
        }
        NegotiatedError::Legacy(Error::Tls(message))
            if message.starts_with("certificate fingerprint mismatch:") =>
        {
            json!({"kind": "tls_pin_mismatch"})
        }
        NegotiatedError::Legacy(Error::Tls(_)) => json!({"kind": "tls_error"}),
        NegotiatedError::Legacy(Error::Io(_)) => json!({"kind": "io_error"}),
        NegotiatedError::Legacy(Error::TransportClosed) => json!({"kind": "transport_closed"}),
        NegotiatedError::Legacy(Error::RegisterFailed(_)) => {
            json!({"kind": "legacy_registration_error"})
        }
        _ => json!({"kind": "unexpected_error"}),
    }
}

fn main() {
    let args = env::args().skip(1).collect::<Vec<_>>();
    if args.len() != 2
        || !["stdio", "tcp", "tls"].contains(&args[0].as_str())
        || ![
            "correct",
            "faulty-observer",
            "wrong-digest",
            "unauthorized",
            "wrong-pin",
        ]
        .contains(&args[1].as_str())
    {
        eprintln!("usage: generated-rust-transport <stdio|tcp|tls> <correct|faulty-observer|wrong-digest|unauthorized|wrong-pin>");
        std::process::exit(64);
    }
    let recording = Rc::new(RefCell::new(Recording::default()));
    let result = execute(&args[0], &args[1], recording.clone());
    let (outcome, peer, exit_code) = match result {
        Ok(peer) => (json!({"kind": "completed"}), peer, 0),
        Err((error, peer)) => {
            let exit_code = if matches!(error, NegotiatedError::Legacy(Error::StepMismatch { .. }))
            {
                1
            } else {
                2
            };
            (failure(&error), peer, exit_code)
        }
    };
    let recording = recording.borrow();
    println!(
        "{}",
        json!({
            "schema": "mirrors.generated-rust-transport-row/v1",
            "transport": args[0], "case": args[1], "semanticDigest": counter::SEMANTIC_DIGEST,
            "peerFingerprint": peer, "factoryCount": recording.factories,
            "disposedPorts": recording.drops, "events": recording.events,
            "observations": recording.observations, "strides": recording.strides,
            "outcome": outcome,
        })
    );
    std::process::exit(exit_code);
}
