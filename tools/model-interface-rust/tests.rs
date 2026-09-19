#![allow(dead_code, unused_variables, unused_mut)]
#[path = "../../.golden-build/model-interface-rust/CorpusMirror.generated.rs"]
mod corpus;
#[path = "../../test/fixtures/model-interface/counter/generated-rust/CounterMirror.generated.rs"]
mod counter;

#[path = "../../.golden-build/model-interface-rust/MultiMirror.generated.rs"]
mod multi;

#[cfg(test)]
mod tests {
    use super::{corpus::*, counter};
    use mirrorrust::{ApalacheConfig, BindingError, FallibleStateComputer, State, Value};
    use num_bigint::BigInt;
    use std::{cell::RefCell, rc::Rc};

    #[derive(Default)]
    struct Sut {
        count: BigInt,
        events: Vec<&'static str>,
        fail: u8,
    }
    struct Port(Rc<RefCell<Sut>>);
    impl counter::CounterPort for Port {
        fn initialize(&mut self) -> Result<(), BindingError> {
            let mut s = self.0.borrow_mut();
            s.events.push("Initialize");
            s.count = 0.into();
            Ok(())
        }
        fn tick(&mut self, input: counter::TickInput) -> Result<(), BindingError> {
            let mut s = self.0.borrow_mut();
            s.events.push("Tick");
            if s.fail == 1 {
                return Err(BindingError::new("custom", "adapter failed"));
            }
            if s.fail == 2 {
                panic!("adapter panicked");
            }
            s.count += input.stride;
            Ok(())
        }
        fn observe(&mut self) -> Result<counter::CounterObservation, BindingError> {
            let mut s = self.0.borrow_mut();
            s.events.push("Observe");
            if s.fail == 3 {
                return Err(BindingError::new("custom", "observer failed"));
            }
            Ok(counter::CounterObservation {
                count: if s.fail == 4 {
                    &s.count + 1
                } else {
                    s.count.clone()
                },
            })
        }
    }
    fn config() -> ApalacheConfig {
        serde_json::from_value(serde_json::json!({"specPath":"specs/Counter.tla", "paramVars":"parameters", "invariant":"TraceComplete", "lengthBound":3})).unwrap()
    }
    fn params(value: Value) -> State {
        State::from([(
            "parameters".into(),
            Value::Record(State::from([("stride".into(), value)])),
        )])
    }
    fn binding() -> (counter::CounterBinding<Port>, Rc<RefCell<Sut>>) {
        let sut = Rc::new(RefCell::new(Sut::default()));
        (
            counter::bind_counter(Port(sut.clone()), &config()).unwrap(),
            sut,
        )
    }
    #[test]
    fn replay_and_coverage() {
        let (mut b, sut) = binding();
        assert!(b.assert_all_actions_covered().is_err());
        let empty = State::new();
        assert_eq!(
            b.compute("init", &empty, &empty).unwrap()["count"],
            Value::Int(0.into())
        );
        for (stride, expected) in [(2, 2), (3, 5)] {
            assert_eq!(
                b.compute("tick", &params(Value::Int(stride.into())), &empty)
                    .unwrap(),
                State::from([("count".into(), Value::Int(expected.into()))])
            );
        }
        b.assert_all_actions_covered().unwrap();
        assert_eq!(b.coverage()["Tick"], 2);
        assert_eq!(
            sut.borrow().events,
            [
                "Initialize",
                "Observe",
                "Tick",
                "Observe",
                "Tick",
                "Observe"
            ]
        );
        b.compute("init", &empty, &empty).unwrap();
        assert_eq!(sut.borrow().count, 0.into());
        let huge: BigInt = "99999999999999999999999999999999999999999999999999999"
            .parse()
            .unwrap();
        assert_eq!(
            b.compute("tick", &params(Value::Int(huge.clone())), &empty)
                .unwrap()["count"],
            Value::Int(huge)
        );
        let mut local = b.into_local_binding().unwrap();
        (local.assert_compatible_config)(&config()).unwrap();
        local.computer.compute("init", &empty, &empty).unwrap();
    }
    #[test]
    fn failures_poison_without_further_effects() {
        for mode in 0..6 {
            let (mut b, sut) = binding();
            let empty = State::new();
            let expected = match mode {
                0 => "transition_before_initialization",
                1 => "unknown_action",
                2 => "input_shape_mismatch",
                3 | 4 => "adapter_failure",
                _ => "observation_shape_mismatch",
            };
            if mode >= 2 {
                b.compute("init", &empty, &empty).unwrap();
            }
            if mode >= 3 {
                sut.borrow_mut().fail = mode - 2;
            }
            let result = if mode == 1 {
                b.compute("unknown", &empty, &empty)
            } else {
                b.compute(
                    "tick",
                    &params(if mode == 2 {
                        Value::Str("bad".into())
                    } else {
                        Value::Int(2.into())
                    }),
                    &empty,
                )
            };
            assert_eq!(result.unwrap_err().code, expected);
            let events = sut.borrow().events.clone();
            assert_eq!(
                b.compute("init", &empty, &empty).unwrap_err().code,
                "binding_poisoned"
            );
            assert_eq!(sut.borrow().events, events);
            if mode == 2 {
                assert_eq!(events, ["Initialize", "Observe"]);
            }
        }
    }
    #[test]
    fn config_failure_has_no_effects() {
        let sut = Rc::new(RefCell::new(Sut::default()));
        let mut cfg = config();
        cfg.param_vars = None;
        assert!(
            matches!(counter::bind_counter(Port(sut.clone()), &cfg), Err(e) if e.code == "configuration_mismatch")
        );
        assert!(sut.borrow().events.is_empty());
        assert_eq!(
            counter::model_interface().semantic_digest,
            counter::SEMANTIC_DIGEST
        );
        let contract: serde_json::Value = serde_json::from_str(counter::CONTRACT_JSON).unwrap();
        assert_eq!(contract["model"]["module"], "Counter");
    }
    #[test]
    fn negotiated_stdio_replay() {
        use mirrorrust::{
            CompiledAdapterKey, CompiledAdapterRegistration, CompiledAdapterRegistry,
            CompiledAdapterSelection, NegotiationPolicy, SemanticDigest,
            STATE_COMPUTER_CONTRACT_VERSION,
        };
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .unwrap()
            .parent()
            .unwrap();
        for mode in 0..3 {
            let sut = Rc::new(RefCell::new(Sut::default()));
            let factories = Rc::new(RefCell::new(0));
            let captured_sut = sut.clone();
            let captured_factories = factories.clone();
            let digest = if mode == 2 {
                "0".repeat(64)
            } else {
                counter::SEMANTIC_DIGEST.into()
            };
            let mut metadata = counter::model_interface();
            metadata.semantic_digest = digest.clone();
            let mut registry = CompiledAdapterRegistry::new(vec![CompiledAdapterRegistration {
                key: CompiledAdapterKey {
                    semantic_digest: SemanticDigest::from_hex(&digest).unwrap(),
                    adapter_id: "rust-test".into(),
                    target_profile: "mirrorrust-v1".into(),
                    state_computer_contract_version: STATE_COMPUTER_CONTRACT_VERSION.into(),
                },
                factory: Box::new(move |context| {
                    *captured_factories.borrow_mut() += 1;
                    if mode == 1 {
                        captured_sut.borrow_mut().fail = 4;
                    }
                    counter::bind_counter(Port(captured_sut.clone()), context.effective_config())?
                        .into_local_binding()
                }),
            }]);
            let mut selection = CompiledAdapterSelection {
                metadata,
                adapter_id: "rust-test".into(),
                target_profile: "mirrorrust-v1".into(),
                state_computer_contract_version: STATE_COMPUTER_CONTRACT_VERSION.into(),
                registry: &mut registry,
                policy: NegotiationPolicy::Require,
                fallback_factory: None,
            };
            let mut cfg = config();
            cfg.spec_path = root.join("specs/Counter.tla").display().to_string();
            let result = mirrorrust::run_client_with_traces_negotiated(
                root.join(".lake/build/bin/mirror").to_str().unwrap(),
                cfg,
                vec![root
                    .join("test/fixtures/model-interface/counter/counter.itf.json")
                    .display()
                    .to_string()],
                &mut selection,
            );
            match mode {
                0 => {
                    result.unwrap();
                    assert_eq!(*factories.borrow(), 1);
                    assert_eq!(sut.borrow().count, 5.into());
                }
                1 => assert!(
                    matches!(result, Err(mirrorrust::Error::StepMismatch { .. })),
                    "{result:?}"
                ),
                _ => {
                    assert!(result.is_err());
                    assert_eq!(*factories.borrow(), 0);
                    assert!(sut.borrow().events.is_empty());
                }
            }
        }
    }
    #[test]
    fn aliases_paths_and_all_inputs_before_effects() {
        use super::multi;
        struct MultiPort(Rc<RefCell<Sut>>);
        impl multi::MultiPort for MultiPort {
            fn initialize(&mut self, input: multi::InitializeInput) -> Result<(), BindingError> {
                let mut s = self.0.borrow_mut();
                s.events.push("Initialize");
                s.count = input.seed;
                Ok(())
            }
            fn tick(&mut self, input: multi::TickInput) -> Result<(), BindingError> {
                let mut s = self.0.borrow_mut();
                s.events.push("Tick");
                if input.validate {
                    s.count += input.stride;
                }
                Ok(())
            }
            fn observe(&mut self) -> Result<multi::MultiObservation, BindingError> {
                let mut s = self.0.borrow_mut();
                s.events.push("Observe");
                Ok(multi::MultiObservation {
                    count: s.count.clone(),
                })
            }
        }
        for bad in 0..5 {
            let sut = Rc::new(RefCell::new(Sut::default()));
            let mut b = multi::bind_multi(MultiPort(sut.clone()), &config()).unwrap();
            b.compute(
                "reset",
                &State::from([("count".into(), Value::Int(9.into()))]),
                &State::new(),
            )
            .unwrap();
            let nested = match bad {
                0 => Value::Seq(vec![Value::Variant(
                    "flag".into(),
                    Box::new(Value::Bool(true)),
                )]),
                1 => Value::Seq(vec![Value::Variant(
                    "flag".into(),
                    Box::new(Value::Str("bad".into())),
                )]),
                2 => Value::Seq(vec![]),
                3 => Value::Seq(vec![Value::Variant(
                    "wrong".into(),
                    Box::new(Value::Bool(true)),
                )]),
                _ => Value::Null,
            };
            let input = State::from([(
                "parameters".into(),
                Value::Record(State::from([
                    ("stride".into(), Value::Int(2.into())),
                    ("meta".into(), nested),
                ])),
            )]);
            let result = b.compute("increment", &input, &State::new());
            if bad == 0 {
                assert_eq!(result.unwrap()["count"], Value::Int(11.into()));
                b.assert_all_actions_covered().unwrap();
                assert_eq!(b.coverage()["Tick"], 1);
            } else {
                assert_eq!(result.unwrap_err().code, "input_shape_mismatch");
                assert_eq!(sut.borrow().events, ["Initialize", "Observe"]);
                assert_eq!(sut.borrow().count, 9.into());
            }
        }
    }
    fn roundtrip<T: NativeCodec>(value: Value) {
        assert_eq!(T::decode(&value).unwrap().encode().unwrap(), value);
    }
    #[test]
    fn structural_codecs() {
        roundtrip::<BigInt>(Value::Int(
            "1234567890123456789012345678901234567890".parse().unwrap(),
        ));
        roundtrip::<bool>(Value::Bool(true));
        roundtrip::<String>(Value::Str("λ\n\"".into()));
        roundtrip::<MirrorNull>(Value::Null);
        roundtrip::<MirrorSet<MirrorSet<BigInt>>>(Value::Set(vec![Value::Set(vec![Value::Int(
            1.into(),
        )])]));
        roundtrip::<MirrorSeq<String>>(Value::Seq(vec![Value::Str("x".into())]));
        roundtrip::<MiTypeO8>(Value::Tuple(vec![Value::Int(3.into()), Value::Bool(false)]));
        roundtrip::<MiTypeO9>(Value::Tuple(vec![]));
        roundtrip::<MiTypeO10>(Value::Record(State::from([
            ("type".into(), Value::Str("x".into())),
            ("quoted\"\\\nλ".into(), Value::Int(7.into())),
        ])));
        roundtrip::<MiTypeO11>(Value::Record(State::new()));
        roundtrip::<MirrorMap<MirrorSeq<BigInt>>>(Value::Map(vec![(
            Value::Str("x".into()),
            Value::Seq(vec![Value::Int(2.into())]),
        )]));
        roundtrip::<MiTypeO3>(Value::Variant(
            "some".into(),
            Box::new(Value::Int(5.into())),
        ));
        roundtrip::<MiTypeO3>(Value::Variant("none".into(), Box::new(Value::Null)));
        assert!(MiTypeO3::decode(&Value::Variant("other".into(), Box::new(Value::Null))).is_err());
        assert!(MiTypeO8::decode(&Value::Seq(vec![])).is_err());
        assert!(MiTypeO10::decode(&Value::Record(State::new())).is_err());
        assert!(
            MiTypeO11::decode(&Value::Record(State::from([("extra".into(), Value::Null)])))
                .is_err()
        );
        assert!(MirrorNull::decode(&Value::Tuple(vec![])).is_err());
    }
    #[test]
    fn duplicate_sets_use_semantic_equality() {
        let a = Value::Set(vec![Value::Int(1.into()), Value::Int(2.into())]);
        let b = Value::Set(vec![Value::Int(2.into()), Value::Int(1.into())]);
        assert!(MirrorSet::<MirrorSet<BigInt>>::decode(&Value::Set(vec![a, b])).is_err());
        assert!(MirrorSet(vec![
            MirrorSet(vec![BigInt::from(1), BigInt::from(2)]),
            MirrorSet(vec![BigInt::from(2), BigInt::from(1)])
        ])
        .encode()
        .is_err());
        assert!(MirrorMap::<BigInt>::decode(&Value::Map(vec![
            (Value::Str("a".into()), Value::Int(1.into())),
            (Value::Str("a".into()), Value::Int(2.into()))
        ]))
        .is_err());
    }
}
