use mirrorrust::schedule as sc;
use mirrorrust::schedule_binding::{replay_with_traces, BindingSession};
use mirrorrust::schedule_exploration as ex;
use mirrorrust::{
    ApalacheConfig, BindingError, CompiledAdapterKey, CompiledAdapterRegistration,
    CompiledAdapterRegistry, CompiledAdapterSelection, NegotiationPolicy, SemanticDigest, State,
    Transport,
};
use num_traits::ToPrimitive;
use serde_json::{json, Value as Json};
use sha2::{Digest, Sha256};
use std::cell::RefCell;
use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;
use std::rc::Rc;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;
#[allow(dead_code, unused_imports, unused_variables)]
#[path = "generated/counter/ScheduledCounterMirror.generated.rs"]
mod counter;
#[allow(dead_code, unused_imports, unused_variables)]
#[path = "generated/native/WriteSentryMBTMirror.generated.rs"]
mod native;
fn check(ok: bool, message: &str) -> Result<(), String> {
    if ok {
        Ok(())
    } else {
        Err(message.into())
    }
}
fn sha(path: impl AsRef<Path>) -> Result<String, String> {
    Ok(format!(
        "{:x}",
        Sha256::digest(std::fs::read(path).map_err(|e| e.to_string())?)
    ))
}
fn load(path: &str) -> Result<Json, String> {
    serde_json::from_slice(&std::fs::read(path).map_err(|e| e.to_string())?)
        .map_err(|e| e.to_string())
}
fn binding(error: impl Into<String>) -> BindingError {
    BindingError::new("adapter_failure", error)
}
fn exact(value: &Json, keys: &[&str]) -> Result<(), String> {
    check(
        value
            .as_object()
            .is_some_and(|v| v.len() == keys.len() && keys.iter().all(|k| v.contains_key(*k))),
        "unknown or missing mapping fields",
    )
}
fn counter_mapping() -> Json {
    json!({"schema":"mirrors.dpm-counter-mapping/v1","profile":sc::PROFILE,"actors":[{"actor":"a","operation":"increment-a"},{"actor":"b","operation":"increment-b"}],"actions":{"read":"read","write":"write","finish":"$done"}})
}
fn native_mapping(value: &Json) -> Result<(), String> {
    exact(value, &["schema", "profile", "roles", "modelSteps"])?;
    check(
        value["schema"] == "mirrors.dpm3-native-mapping/v1"
            && value["profile"] == "dpm-writesentry-two-operation/v1",
        "unsupported native profile",
    )?;
    exact(&value["roles"], &["arm", "write"])?;
    for role in ["arm", "write"] {
        let r = &value["roles"][role];
        exact(r, &["nativeActor", "operation"])?;
        check(
            (r["nativeActor"] == "t1" || r["nativeActor"] == "t2")
                && r["operation"] == if role == "arm" { "Arm" } else { "Write" },
            "invalid native role",
        )?;
    }
    let phases = [
        "Reserve",
        "ArmLock",
        "ArmSelect",
        "PublishOdd",
        "PublishPayload",
        "PublishEven",
        "ArmUnlock",
        "ArmTarget",
        "ArmFinishLock",
        "ArmFinishUnlock",
        "ArmOutcome",
        "Release",
        "CallDone",
        "WriteBegin",
        "TrapEntry",
        "SnapshotProbe",
        "SnapshotNoAdmission",
        "SnapshotAdmissionChecked",
        "SnapshotLease",
        "SnapshotAdmissionLost",
        "SnapshotAdmissionValidated",
        "SnapshotSeq1",
        "SnapshotInvalid",
        "SnapshotPayload",
        "SnapshotSeq2",
        "SnapshotTorn",
        "SnapshotAccepted",
        "ContextRejected",
        "OwnerRejected",
        "LoadRejected",
        "Filtered",
        "Hit",
        "HitReleased",
        "WriteDone",
    ];
    let steps = value["modelSteps"]
        .as_array()
        .ok_or("native steps missing")?;
    check(!steps.is_empty() && steps.len() <= 150, "native step bound")?;
    let mut started = BTreeSet::new();
    let mut done = BTreeSet::new();
    let mut active = BTreeMap::<String, String>::new();
    for step in steps {
        exact(step, &["role", "request", "parameters"])?;
        let role = step["role"].as_str().ok_or("missing role")?;
        check(
            ["arm", "write"].contains(&role) && !done.contains(role),
            "unknown/reused native operation",
        )?;
        let p = &step["parameters"];
        let q = &step["request"];
        exact(
            p,
            &[
                "action", "thread", "command", "address", "value", "writer", "span", "entry",
                "slot", "target",
            ],
        )?;
        let actor = p["thread"].as_str().ok_or("missing actor")?;
        let phase = p["action"].as_str().ok_or("missing phase")?;
        check(
            p["thread"] == value["roles"][role]["nativeActor"]
                && p["command"] == value["roles"][role]["operation"]
                && p["address"] == "A1"
                && p["value"] == if role == "arm" { "good" } else { "bad" },
            "native/model identity differs",
        )?;
        check(
            p["writer"] == "allowed"
                && p["span"] == 1
                && phases.contains(&phase)
                && ["entry", "slot"]
                    .iter()
                    .all(|k| p[k].as_u64().is_some_and(|v| v <= 4))
                && ["t1", "t2", "noThread"].contains(&p["target"].as_str().unwrap_or("")),
            "native input outside scope",
        )?;
        if !started.contains(role) {
            exact(
                q,
                &[
                    "op", "thread", "command", "address", "value", "writer", "span",
                ],
            )?;
            check(
                q["op"] == "Begin"
                    && !active.contains_key(actor)
                    && phase
                        == if role == "arm" {
                            "Reserve"
                        } else {
                            "WriteBegin"
                        },
                "invalid native begin",
            )?;
            for k in ["thread", "command", "address", "value", "writer", "span"] {
                check(q[k] == p[k], "concrete command differs")?;
            }
            started.insert(role.to_owned());
            active.insert(actor.into(), role.into());
        } else {
            exact(q, &["op", "thread"])?;
            check(
                q["op"] == "Advance"
                    && q["thread"] == actor
                    && active.get(actor).is_some_and(|v| v == role),
                "invalid native advance",
            )?;
        }
        if phase == "CallDone" {
            done.insert(role.to_owned());
            active.remove(actor);
        }
    }
    check(done.len() == 2, "native operations incomplete")
}
#[derive(Default)]
struct Stats {
    acquisitions: AtomicUsize,
    entered: AtomicUsize,
    teardowns: AtomicUsize,
}
fn stats(stats: &Stats) -> Json {
    json!({"acquisitions":stats.acquisitions.load(Ordering::SeqCst),"enteredWorkers":stats.entered.load(Ordering::SeqCst),"teardowns":stats.teardowns.load(Ordering::SeqCst)})
}
struct CounterState {
    count: i64,
    saved: [i64; 2],
    phase: [i64; 2],
}
fn counter_adapter(identity: sc::Identity, stats: Arc<Stats>) -> sc::Adapter {
    sc::Adapter {
        identity,
        actors: vec![
            sc::ActorDeclaration {
                actor: "a".into(),
                operation: "increment-a".into(),
            },
            sc::ActorDeclaration {
                actor: "b".into(),
                operation: "increment-b".into(),
            },
        ],
        checkpoints: vec!["read".into(), "write".into()],
        factory: Arc::new(move |input| {
            let initial = input["initial"].as_i64().ok_or("invalid initial input")?;
            let mode = input["mode"]
                .as_str()
                .ok_or("missing fixture mode")?
                .to_owned();
            check(
                [0, 5].contains(&initial)
                    && [
                        "ok",
                        "mutate",
                        "teardown-fail",
                        "mutate-and-teardown-fail",
                        "unexpected-checkpoint",
                        "cancel",
                        "bad-observation",
                        "denied-negotiation",
                        "reentrant",
                    ]
                    .contains(&mode.as_str()),
                "unsupported counter inputs",
            )?;
            stats.acquisitions.fetch_add(1, Ordering::SeqCst);
            let state = Arc::new(Mutex::new(CounterState {
                count: initial,
                saved: [0, 0],
                phase: [0, 0],
            }));
            let mut workers = vec![];
            for (index, actor) in ["a", "b"].iter().enumerate() {
                let state = state.clone();
                let mode = mode.clone();
                let stats = stats.clone();
                workers.push(sc::Worker {
                    actor: (*actor).into(),
                    execute: Box::new(move |hook| {
                        stats.entered.fetch_add(1, Ordering::SeqCst);
                        let saved = {
                            let mut s = state.lock().unwrap();
                            let saved = s.count;
                            s.saved[index] = saved;
                            s.phase[index] = 1;
                            saved
                        };
                        hook.arrive(if mode == "unexpected-checkpoint" {
                            "wrong"
                        } else {
                            "read"
                        })?;
                        {
                            let mut s = state.lock().unwrap();
                            s.count = saved
                                + if mode == "mutate" || mode == "mutate-and-teardown-fail" {
                                    2
                                } else {
                                    1
                                };
                            s.phase[index] = 2;
                        }
                        hook.arrive("write")?;
                        state.lock().unwrap().phase[index] = 3;
                        Ok(())
                    }),
                });
            }
            let observe = state.clone();
            let stats = stats.clone();
            Ok(sc::Program {
                workers,
                observe: Box::new(move || {
                    let s = observe.lock().unwrap();
                    Ok(
                        json!({"count":{"#bigint":s.count.to_string()},"saved":{"#map":[["a",{"#bigint":s.saved[0].to_string()}],["b",{"#bigint":s.saved[1].to_string()}]]},"phase":{"#map":[["a",{"#bigint":s.phase[0].to_string()}],["b",{"#bigint":s.phase[1].to_string()}]]}}),
                    )
                }),
                teardown: Box::new(move || {
                    stats.teardowns.fetch_add(1, Ordering::SeqCst);
                    check(
                        !["teardown-fail", "mutate-and-teardown-fail"].contains(&mode.as_str()),
                        "deliberate teardown failure",
                    )
                }),
            })
        }),
    }
}
#[derive(Default)]
struct NativeContext {
    transport: Option<Transport>,
    identity: Option<Json>,
    state: Json,
    transcript: Vec<Json>,
    expected_image: String,
    acquisitions: usize,
    cleanups: usize,
    closed: bool,
    quit_acknowledged: bool,
    exit_code: i32,
}
impl NativeContext {
    fn invoke(&mut self, request: Json) -> Result<Json, String> {
        let transport = self.transport.as_mut().ok_or("native transport absent")?;
        transport
            .send(&request.to_string())
            .map_err(|e| e.to_string())?;
        let line = transport
            .recv()
            .map_err(|e| e.to_string())?
            .ok_or("native worker ended")?;
        let reply: Json = serde_json::from_str(&line).map_err(|e| e.to_string())?;
        self.transcript
            .push(json!({"request":request,"reply":reply}));
        check(self.transcript.len() <= 512, "native transcript cap")?;
        if let Some(e) = reply.get("error") {
            return Err(e.to_string());
        }
        let actual = &reply["nativeIdentity"];
        if let Some(identity) = &self.identity {
            check(actual == identity, "native actor/process identity changed")?;
        } else {
            check(
                actual["imageSha256"] == self.expected_image
                    && actual["processId"].as_u64().is_some_and(|p| p > 0)
                    && actual["createdFileTime"]
                        .as_str()
                        .is_some_and(|s| !s.is_empty()),
                "native process/image mismatch",
            )?;
            let actors = &actual["actors"];
            check(
                actors.as_object().is_some_and(|a| a.len() == 2)
                    && ["t1", "t2"]
                        .iter()
                        .all(|k| actors[k].as_u64().is_some_and(|v| v > 0))
                    && actors["t1"] != actors["t2"],
                "native thread identity invalid",
            )?;
            self.identity = Some(actual.clone());
        }
        if let Some(state) = reply.get("state") {
            self.state = state.clone();
        }
        Ok(reply)
    }
    fn start(&mut self, launcher: &str) -> Result<(), String> {
        check(self.acquisitions == 0, "native context single use")?;
        self.transport = Some(mirrorrust::spawn_mirror(launcher).map_err(|e| e.to_string())?);
        self.acquisitions += 1;
        if let Err(e) = self.invoke(json!({"op":"Initialize"})) {
            let _ = self.finish();
            return Err(e);
        }
        Ok(())
    }
    fn finish(&mut self) -> Result<(), String> {
        if self.closed {
            return Ok(());
        }
        self.closed = true;
        self.cleanups += 1;
        let mut failure = None;
        match self.invoke(json!({"op":"Quit"})) {
            Ok(reply) => {
                self.quit_acknowledged = reply["closed"] == true;
                if !self.quit_acknowledged {
                    failure = Some("native quit acknowledgement missing".into());
                }
            }
            Err(e) => failure = Some(e),
        }
        if let Some(mut transport) = self.transport.take() {
            match transport.close() {
                Ok(code) => self.exit_code = code,
                Err(e) => {
                    failure.get_or_insert(e.to_string());
                }
            }
        }
        if let Some(e) = failure {
            return Err(e);
        }
        check(self.exit_code == 0, "native exit failed")
    }
    fn receipt(&self) -> Json {
        json!({"schema":"mirrors.dpm-native-bridge/v1","identity":self.identity,"acquisitions":self.acquisitions,"cleanups":self.cleanups,"closed":self.closed,"quitAcknowledged":self.quit_acknowledged,"exitCode":self.exit_code,"transcript":self.transcript})
    }
}
impl Drop for NativeContext {
    fn drop(&mut self) {
        if self.transport.is_some() {
            let _ = self.finish();
        }
    }
}
fn native_adapter(
    identity: sc::Identity,
    mapping: Json,
    launcher: String,
    context: Arc<Mutex<NativeContext>>,
) -> sc::Adapter {
    let mut commands = BTreeMap::<String, Vec<Json>>::new();
    let mut checkpoints = BTreeSet::new();
    for step in mapping["modelSteps"].as_array().unwrap() {
        commands
            .entry(step["role"].as_str().unwrap().into())
            .or_default()
            .push(step["request"].clone());
        checkpoints.insert(step["parameters"]["action"].as_str().unwrap().to_owned());
    }
    sc::Adapter {
        identity,
        actors: vec![
            sc::ActorDeclaration {
                actor: "arm".into(),
                operation: "native-arm-operation".into(),
            },
            sc::ActorDeclaration {
                actor: "write".into(),
                operation: "native-write-operation".into(),
            },
        ],
        checkpoints: checkpoints.into_iter().collect(),
        factory: Arc::new(move |_| {
            context.lock().unwrap().start(&launcher)?;
            let mut workers = vec![];
            for (actor, commands) in &commands {
                let context = context.clone();
                let commands = commands.clone();
                workers.push(sc::Worker {
                    actor: actor.clone(),
                    execute: Box::new(move |hook| {
                        for request in commands {
                            let actual = context.lock().unwrap().invoke(request)?;
                            hook.arrive(actual["phase"].as_str().ok_or("native phase absent")?)?;
                        }
                        Ok(())
                    }),
                });
            }
            let observe = context.clone();
            let teardown = context.clone();
            Ok(sc::Program {
                workers,
                observe: Box::new(move || Ok(observe.lock().unwrap().state.clone())),
                teardown: Box::new(move || teardown.lock().unwrap().finish()),
            })
        }),
    }
}
struct CounterPort {
    session: Rc<RefCell<BindingSession>>,
    cancel: sc::Cancellation,
    mode: String,
}
impl counter::ScheduledCounterPort for CounterPort {
    fn initialize(&mut self) -> Result<(), BindingError> {
        self.session.borrow_mut().initialize()
    }
    fn read(&mut self, p: counter::ReadInput) -> Result<(), BindingError> {
        if self.mode == "reentrant" {
            let _outer = self.session.borrow_mut();
            let _inner = self.session.borrow_mut();
            return Ok(());
        }
        self.session
            .borrow_mut()
            .advance(&sc::Step::new(&p.actor, "read"))?;
        if self.mode == "cancel" {
            self.cancel.cancel();
        }
        Ok(())
    }
    fn write(&mut self, p: counter::WriteInput) -> Result<(), BindingError> {
        self.session
            .borrow_mut()
            .advance(&sc::Step::new(&p.actor, "write"))
    }
    fn finish(&mut self, p: counter::FinishInput) -> Result<(), BindingError> {
        self.session
            .borrow_mut()
            .advance(&sc::Step::new(&p.actor, "$done"))
    }
    fn observe(&mut self) -> Result<counter::ScheduledCounterObservation, BindingError> {
        let mut raw = self.session.borrow().observation()?;
        if self.mode == "bad-observation" {
            raw["count"] = json!("wrong");
        }
        let state: State = serde_json::from_value(raw).map_err(|e| binding(e.to_string()))?;
        Ok(counter::ScheduledCounterObservation {
            count: counter::NativeCodec::decode(&state["count"])?,
            phase: counter::NativeCodec::decode(&state["phase"])?,
            saved: counter::NativeCodec::decode(&state["saved"])?,
        })
    }
}
struct NativePort {
    session: Rc<RefCell<BindingSession>>,
    mapping: Json,
    index: usize,
    cancel: sc::Cancellation,
    mode: String,
}
impl NativePort {
    fn advance(&mut self, action: &str, p: Json) -> Result<(), BindingError> {
        let next = self.mapping["modelSteps"]
            .as_array()
            .unwrap()
            .get(self.index)
            .ok_or_else(|| binding("extra native callback"))?;
        if p["action"] != action || p != next["parameters"] {
            return Err(binding("generated native input differs from mapping"));
        }
        if self.mode == "cancel" && self.index == 1 {
            self.cancel.cancel();
        }
        let role = next["role"].as_str().unwrap();
        self.session
            .borrow_mut()
            .advance(&sc::Step::new(role, action))?;
        if action == "CallDone" {
            self.session
                .borrow_mut()
                .advance(&sc::Step::new(role, "$done"))?;
        }
        self.index += 1;
        Ok(())
    }
}
macro_rules! native_action{($method:ident,$input:ident,$action:literal)=>{fn $method(&mut self,p:native::$input)->Result<(),BindingError>{self.advance($action,json!({"action":p.action,"thread":p.thread,"command":p.command,"address":p.address,"value":p.value,"writer":p.writer,"span":p.span.to_i64().ok_or_else(||binding("span range"))?,"entry":p.entry.to_i64().ok_or_else(||binding("entry range"))?,"slot":p.slot.to_i64().ok_or_else(||binding("slot range"))?,"target":p.target}))}};}
impl native::WriteSentryMBTPort for NativePort {
    fn initialize(&mut self) -> Result<(), BindingError> {
        self.index = 0;
        self.session.borrow_mut().initialize()
    }
    native_action!(admission_closed, AdmissionClosedInput, "AdmissionClosed");
    native_action!(arm_blocked, ArmBlockedInput, "ArmBlocked");
    native_action!(arm_conflict, ArmConflictInput, "ArmConflict");
    native_action!(arm_finish_lock, ArmFinishLockInput, "ArmFinishLock");
    native_action!(arm_finish_unlock, ArmFinishUnlockInput, "ArmFinishUnlock");
    native_action!(arm_lock, ArmLockInput, "ArmLock");
    native_action!(arm_no_slot, ArmNoSlotInput, "ArmNoSlot");
    native_action!(arm_outcome, ArmOutcomeInput, "ArmOutcome");
    native_action!(arm_reuse, ArmReuseInput, "ArmReuse");
    native_action!(arm_select, ArmSelectInput, "ArmSelect");
    native_action!(arm_target, ArmTargetInput, "ArmTarget");
    native_action!(arm_unlock, ArmUnlockInput, "ArmUnlock");
    native_action!(busy, BusyInput, "Busy");
    native_action!(call_done, CallDoneInput, "CallDone");
    native_action!(context_rejected, ContextRejectedInput, "ContextRejected");
    native_action!(dis_finish_lock, DisFinishLockInput, "DisFinishLock");
    native_action!(dis_finish_unlock, DisFinishUnlockInput, "DisFinishUnlock");
    native_action!(dis_lock, DisLockInput, "DisLock");
    native_action!(dis_no_entry, DisNoEntryInput, "DisNoEntry");
    native_action!(dis_outcome, DisOutcomeInput, "DisOutcome");
    native_action!(dis_select, DisSelectInput, "DisSelect");
    native_action!(dis_target, DisTargetInput, "DisTarget");
    native_action!(dis_unlock, DisUnlockInput, "DisUnlock");
    native_action!(filtered, FilteredInput, "Filtered");
    native_action!(foreign_clear, ForeignClearInput, "ForeignClear");
    native_action!(foreign_stomp, ForeignStompInput, "ForeignStomp");
    native_action!(hit, HitInput, "Hit");
    native_action!(hit_released, HitReleasedInput, "HitReleased");
    native_action!(owner_rejected, OwnerRejectedInput, "OwnerRejected");
    native_action!(publish_even, PublishEvenInput, "PublishEven");
    native_action!(publish_odd, PublishOddInput, "PublishOdd");
    native_action!(publish_payload, PublishPayloadInput, "PublishPayload");
    native_action!(release, ReleaseInput, "Release");
    native_action!(reserve, ReserveInput, "Reserve");
    native_action!(retire_closed, RetireClosedInput, "RetireClosed");
    native_action!(retire_even, RetireEvenInput, "RetireEven");
    native_action!(retire_odd, RetireOddInput, "RetireOdd");
    native_action!(retire_partial, RetirePartialInput, "RetirePartial");
    native_action!(retire_payload, RetirePayloadInput, "RetirePayload");
    native_action!(retire_quiescent, RetireQuiescentInput, "RetireQuiescent");
    native_action!(snapshot_accepted, SnapshotAcceptedInput, "SnapshotAccepted");
    native_action!(
        snapshot_admission_checked,
        SnapshotAdmissionCheckedInput,
        "SnapshotAdmissionChecked"
    );
    native_action!(
        snapshot_admission_lost,
        SnapshotAdmissionLostInput,
        "SnapshotAdmissionLost"
    );
    native_action!(
        snapshot_admission_validated,
        SnapshotAdmissionValidatedInput,
        "SnapshotAdmissionValidated"
    );
    native_action!(snapshot_invalid, SnapshotInvalidInput, "SnapshotInvalid");
    native_action!(snapshot_lease, SnapshotLeaseInput, "SnapshotLease");
    native_action!(
        snapshot_no_admission,
        SnapshotNoAdmissionInput,
        "SnapshotNoAdmission"
    );
    native_action!(snapshot_payload, SnapshotPayloadInput, "SnapshotPayload");
    native_action!(snapshot_probe, SnapshotProbeInput, "SnapshotProbe");
    native_action!(snapshot_seq1, SnapshotSeq1Input, "SnapshotSeq1");
    native_action!(snapshot_seq2, SnapshotSeq2Input, "SnapshotSeq2");
    native_action!(snapshot_torn, SnapshotTornInput, "SnapshotTorn");
    native_action!(trap_entry, TrapEntryInput, "TrapEntry");
    native_action!(write_begin, WriteBeginInput, "WriteBegin");
    native_action!(write_done, WriteDoneInput, "WriteDone");
    fn observe(&mut self) -> Result<native::WriteSentryMBTObservation, BindingError> {
        let state: State = serde_json::from_value(self.session.borrow().observation()?)
            .map_err(|e| binding(e.to_string()))?;
        Ok(native::WriteSentryMBTObservation {
            budget: native::NativeCodec::decode(&state["budget"])?,
            calls: native::NativeCodec::decode(&state["calls"])?,
            disarm_conflict: native::NativeCodec::decode(&state["disarm_conflict"])?,
            dr: native::NativeCodec::decode(&state["dr"])?,
            flags: native::NativeCodec::decode(&state["flags"])?,
            locals: native::NativeCodec::decode(&state["locals"])?,
            mem: native::NativeCodec::decode(&state["mem"])?,
            mutex: native::NativeCodec::decode(&state["mutex"])?,
            operation: native::NativeCodec::decode(&state["operation"])?,
            pc: native::NativeCodec::decode(&state["pc"])?,
            progress: native::NativeCodec::decode(&state["progress"])?,
            reg: native::NativeCodec::decode(&state["reg"])?,
            result: native::NativeCodec::decode(&state["result"])?,
            selected: native::NativeCodec::decode(&state["selected"])?,
            step_count: native::NativeCodec::decode(&state["step_count"])?,
            targets: native::NativeCodec::decode(&state["targets"])?,
            tls: native::NativeCodec::decode(&state["tls"])?,
            trap: native::NativeCodec::decode(&state["trap"])?,
        })
    }
}
fn run() -> Result<Json, String> {
    let mut options = BTreeMap::new();
    let mut args = std::env::args().skip(1);
    while let Some(key) = args.next() {
        check(
            key.starts_with("--") && !options.contains_key(&key),
            "invalid/duplicate option",
        )?;
        let value = if key == "--describe" {
            "true".into()
        } else {
            args.next().ok_or("missing option value")?
        };
        options.insert(key, value);
    }
    let option = |key: &str| {
        options
            .get(key)
            .map(String::as_str)
            .ok_or_else(|| format!("missing {key}"))
    };
    let kind = options
        .get("--kind")
        .map(String::as_str)
        .unwrap_or("counter");
    check(
        ["counter", "native", "explore"].contains(&kind),
        "unknown consumer kind",
    )?;
    let mode = options
        .get("--mode")
        .cloned()
        .unwrap_or_else(|| "ok".into());
    let mapping = load(option("--mapping")?)?;
    if kind == "native" {
        native_mapping(&mapping)?;
    } else {
        check(mapping == counter_mapping(), "unsupported counter mapping")?;
    }
    let semantic = if kind == "native" {
        native::SEMANTIC_DIGEST
    } else {
        counter::SEMANTIC_DIGEST
    };
    let own = sha(std::env::current_exe().map_err(|e| e.to_string())?)?;
    let implementation = if kind == "native" {
        format!(
            "{:x}",
            Sha256::digest(
                format!(
                    "mirrors.dpm-native-implementation/v1\n{own}\n{}\n{}\n",
                    sha(option("--worker")?)?,
                    sha(option("--launcher")?)?
                )
                .as_bytes()
            )
        )
    } else {
        own
    };
    let identity = sc::Identity {
        model_semantic_digest: semantic.into(),
        mapping_sha256: sha(option("--mapping")?)?,
        implementation_sha256: implementation,
    };
    if options.contains_key("--describe") {
        return Ok(json!({"profile":sc::PROFILE,"identity":identity}));
    }
    let counts = Arc::new(Stats::default());
    let cancel = sc::Cancellation::default();
    if kind == "explore" {
        let fixture_mode = options
            .get("--fixture-mode")
            .cloned()
            .unwrap_or_else(|| "ok".into());
        let space = ex::FiniteSpace {
            identity: identity.clone(),
            actors: ["a", "b"]
                .iter()
                .map(|a| ex::ActorChain {
                    actor: sc::ActorDeclaration {
                        actor: (*a).into(),
                        operation: format!("increment-{a}"),
                    },
                    checkpoints: vec!["read".into(), "write".into(), "$done".into()],
                })
                .collect(),
            inputs: vec![
                json!({"initial":0,"mode":fixture_mode}),
                json!({"initial":5,"mode":fixture_mode}),
            ],
            max_preemptions: options
                .get("--preemptions")
                .map(|s| s.parse())
                .transpose()
                .map_err(|_| "preemption value")?
                .unwrap_or(64),
            require_model_comparison: options
                .get("--require-comparison")
                .is_some_and(|v| v == "true"),
            base_variables: vec!["count".into(), "saved".into(), "phase".into()],
            instrumentation_variables: vec![],
        };
        let mut base = ex::local_exploration_runner(
            counter_adapter(identity, counts.clone()),
            sc::Policy::default(),
        );
        let trigger = cancel.clone();
        let mut runner: ex::ExplorationRunner = Box::new(move |p, c| {
            let sample = base(p, c)?;
            if fixture_mode == "cancel" {
                trigger.cancel();
            }
            Ok(sample)
        });
        let number = |key: &str, fallback: usize| -> Result<usize, String> {
            options
                .get(key)
                .map(|s| s.parse().map_err(|_| format!("invalid {key}")))
                .unwrap_or(Ok(fallback))
        };
        let limits = ex::ExplorationLimits {
            max_runs: number("--max-runs", 4096)?,
            max_enumerated_schedules: number("--max-enumerated", 4096)?,
            time_budget: Duration::from_millis(number("--time-ms", 30_000)? as u64),
            max_evidence_bytes: number("--evidence-bytes", 16 * 1_048_576)?,
        };
        let mut result = ex::explore_finite(&space, &mut runner, &limits, &cancel);
        result["sut"] = stats(&counts);
        return Ok(result);
    }
    let schedule = sc::parse_schedule(
        &std::fs::read_to_string(option("--schedule")?).map_err(|e| e.to_string())?,
    )?;
    if kind == "native" {
        let mut expected = vec![];
        for s in mapping["modelSteps"].as_array().unwrap() {
            let actor = s["role"].as_str().unwrap();
            let action = s["parameters"]["action"].as_str().unwrap();
            expected.push(sc::Step::new(actor, action));
            if action == "CallDone" {
                expected.push(sc::Step::new(actor, "$done"));
            }
        }
        check(
            schedule.inputs == json!({}) && schedule.steps == expected,
            "native schedule correspondence differs",
        )?;
    }
    let fixture_mode = schedule.inputs["mode"].as_str().unwrap_or("ok").to_owned();
    let mut native_context = NativeContext::default();
    native_context.exit_code = -1;
    native_context.expected_image = if kind == "native" {
        if mode == "wrong-image" {
            "0".repeat(64)
        } else {
            sha(option("--worker")?)?
        }
    } else {
        String::new()
    };
    let context = Arc::new(Mutex::new(native_context));
    let adapter = if kind == "native" {
        native_adapter(
            identity.clone(),
            mapping.clone(),
            option("--launcher")?.into(),
            context.clone(),
        )
    } else {
        counter_adapter(identity.clone(), counts.clone())
    };
    let session = Rc::new(RefCell::new(BindingSession::new(
        schedule,
        adapter,
        sc::Policy {
            execution_timeout: Duration::from_secs(240),
            cleanup_timeout: Duration::from_secs(15),
            ..sc::Policy::default()
        },
        cancel.clone(),
    )));
    let mut config = ApalacheConfig {
        spec_path: option("--spec")?.into(),
        invariant: if kind == "native" {
            "MBTSafety"
        } else {
            "Safety"
        }
        .into(),
        length_bound: 6,
        const_init: None,
        init_predicate: None,
        next_predicate: None,
        param_vars: None,
    };
    config.param_vars = Some("parameters".into());
    config.init_predicate = Some(if kind == "native" { "MBTInit" } else { "Init" }.into());
    config.next_predicate = Some(if kind == "native" { "MBTNext" } else { "Next" }.into());
    let target = if kind == "native" {
        "mirrorrust-v2"
    } else {
        "mirrorrust-v1"
    };
    let mut metadata = if kind == "native" {
        native::model_interface()
    } else {
        counter::model_interface()
    };
    if fixture_mode == "denied-negotiation" {
        metadata.semantic_digest = "f".repeat(64);
    }
    let digest = SemanticDigest::from_hex(semantic).map_err(|e| e.to_string())?;
    let selected =
        SemanticDigest::from_hex(&metadata.semantic_digest).map_err(|e| e.to_string())?;
    let owner = session.clone();
    let mapping_owner = mapping.clone();
    let native_mode = mode.clone();
    let counter_mode = fixture_mode.clone();
    let cancellation = cancel.clone();
    let is_native = kind == "native";
    let mut registry = CompiledAdapterRegistry::new(vec![CompiledAdapterRegistration {
        key: CompiledAdapterKey {
            semantic_digest: selected,
            adapter_id: "dpm".into(),
            target_profile: target.into(),
            state_computer_contract_version: mirrorrust::STATE_COMPUTER_CONTRACT_VERSION.into(),
        },
        factory: Box::new(move |authority| {
            let mut local = if is_native {
                native::bind_write_sentry_m_b_t(
                    NativePort {
                        session: owner.clone(),
                        mapping: mapping_owner.clone(),
                        index: 0,
                        cancel: cancellation.clone(),
                        mode: native_mode.clone(),
                    },
                    authority.effective_config(),
                )?
                .into_local_binding()?
            } else {
                counter::bind_scheduled_counter(
                    CounterPort {
                        session: owner.clone(),
                        cancel: cancellation.clone(),
                        mode: counter_mode.clone(),
                    },
                    authority.effective_config(),
                )?
                .into_local_binding()?
            };
            local.semantic_digest = digest;
            let dispose = owner.clone();
            local.dispose = Box::new(move || dispose.borrow_mut().dispose());
            Ok(local)
        }),
    }]);
    let mut selection = CompiledAdapterSelection {
        metadata,
        adapter_id: "dpm".into(),
        target_profile: target.into(),
        state_computer_contract_version: mirrorrust::STATE_COMPUTER_CONTRACT_VERSION.into(),
        registry: &mut registry,
        policy: NegotiationPolicy::Require,
        fallback_factory: None,
    };
    let repeats: usize = options
        .get("--repeats")
        .map(|s| s.parse())
        .transpose()
        .map_err(|_| "bad repeat count")?
        .unwrap_or(1);
    check((1..=4).contains(&repeats), "repeat bound")?;
    let result = replay_with_traces(
        mirrorrust::spawn_mirror(option("--mirror")?).map_err(|e| e.to_string())?,
        config,
        vec![option("--trace")?.into(); repeats],
        &mut selection,
        session.clone(),
    );
    let mut evidence = result.evidence;
    evidence["actualIdentity"] = json!(identity);
    evidence["mode"] = json!(if is_native { mode } else { fixture_mode });
    evidence["sut"] = stats(&counts);
    if is_native {
        evidence["native"] = context.lock().unwrap().receipt();
        evidence["profile"] = json!("dpm-writesentry-two-operation/v1");
        evidence["fullProductionQualified"] = json!(false);
    }
    Ok(evidence)
}
fn main() {
    match run() {
        Ok(result) => {
            let args: Vec<_> = std::env::args().collect();
            if let Some(i) = args.iter().position(|v| v == "--out") {
                if let Err(e) = std::fs::write(
                    &args[i + 1],
                    serde_json::to_string_pretty(&result).unwrap() + "\n",
                ) {
                    eprintln!("{e}");
                    std::process::exit(2);
                }
            } else {
                println!("{result}");
            }
        }
        Err(e) => {
            eprintln!("{e}");
            std::process::exit(2);
        }
    }
}

#[cfg(test)]
#[allow(dead_code, unused_imports, unused_variables)]
mod generated_v2_codecs {
    include!("generated/native/WriteSentryMBTMirror.generated.rs");
    #[test]
    fn integer_maps_roundtrip_without_precision_loss() {
        let huge = "1208925819614629174706176".parse::<BigInt>().unwrap();
        let value = Value::Map(vec![
            (Value::Int(huge.clone()), Value::Int(7.into())),
            (Value::Int((-1).into()), Value::Int(3.into())),
        ]);
        let decoded = MirrorIntMap::<BigInt>::decode(&value).unwrap();
        assert_eq!(decoded.0[&huge], BigInt::from(7));
        assert_eq!(
            MirrorIntMap::<BigInt>::decode(&decoded.encode().unwrap())
                .unwrap()
                .0,
            decoded.0
        );
    }
    #[test]
    fn map_codecs_refuse_wrong_domains_and_duplicate_keys() {
        assert!(MirrorIntMap::<BigInt>::decode(&Value::Map(vec![(
            Value::Str("1".into()),
            Value::Int(7.into())
        )]))
        .is_err());
        assert!(MirrorIntMap::<BigInt>::decode(&Value::Map(vec![
            (Value::Int(1.into()), Value::Int(7.into())),
            (Value::Int(1.into()), Value::Int(8.into()))
        ]))
        .is_err());
        assert!(MirrorMap::<BigInt>::decode(&Value::Map(vec![(
            Value::Int(1.into()),
            Value::Int(7.into())
        )]))
        .is_err());
    }
    #[test]
    fn literal_map_projection_is_typed_and_checks_all_keys() {
        let text = "-1208925819614629174706176";
        let value = Value::Map(vec![(Value::Int(text.parse().unwrap()), Value::Bool(true))]);
        assert_eq!(
            read_path(&value, &[Segment::MapInt("-1208925819614629174706176")]).unwrap(),
            &Value::Bool(true)
        );
        assert!(read_path(&value, &[Segment::MapInt("1")]).is_err());
        assert!(read_path(&value, &[Segment::MapStr("-1208925819614629174706176")]).is_err());
        let duplicate = Value::Map(vec![
            (Value::Int(1.into()), Value::Bool(true)),
            (Value::Int(2.into()), Value::Bool(false)),
            (Value::Int(2.into()), Value::Bool(true)),
        ]);
        assert!(read_path(&duplicate, &[Segment::MapInt("1")]).is_err());
        let ordinary = Value::Map(vec![(Value::Str("__proto__".into()), Value::Int(7.into()))]);
        assert_eq!(
            read_path(&ordinary, &[Segment::MapStr("__proto__")]).unwrap(),
            &Value::Int(7.into())
        );
    }
}
