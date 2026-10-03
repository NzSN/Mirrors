#![allow(dead_code, unused_variables, unused_mut)]
use mirrorrust::{ApalacheConfig, BindingError, FallibleStateComputer, State};
use num_bigint::BigInt;
use serde_json::{json, Value as Json};
use std::{cell::RefCell, rc::Rc};
mod portable { include!(concat!(env!("MITL_GENERATED"), "/rust/Portable/PortableMirror.generated.rs")); }
mod recording { include!(concat!(env!("MITL_GENERATED"), "/rust/Recording/RecordingMirror.generated.rs")); }

fn rows(root: &str, name: &str) -> Vec<Json> {
    std::fs::read_to_string(format!("{root}/{name}")).unwrap().lines()
        .filter(|line| !line.is_empty()).map(|line| serde_json::from_str(line).unwrap()).collect()
}
fn lower(name: &str) -> String { format!("{}{}", name[..1].to_lowercase(), &name[1..]) }
fn bigint(value: &BigInt) -> Json { json!({"#bigint": value.to_string()}) }
fn config(valid: bool) -> ApalacheConfig {
    serde_json::from_value(json!({"specPath":"Counter.tla", "invariant":"TraceComplete", "lengthBound":3,
        "paramVars":if valid {"parameters"} else {"wrong"}})).unwrap()
}
fn emit(family: &str, id: &Json, mut result: Json) {
    result["family"] = json!(family); result["id"] = id.clone(); println!("{result}");
}
#[derive(Default)]
struct PortableState { saved: Option<portable::InitializeInput>, effects: usize, mutation: String }
struct PortablePort(Rc<RefCell<PortableState>>);
impl portable::PortablePort for PortablePort {
    fn initialize(&mut self, input: portable::InitializeInput) -> Result<(), BindingError> {
        let mut state=self.0.borrow_mut();state.effects+=1;state.saved=Some(input);Ok(())
    }
    fn observe(&mut self) -> Result<portable::PortableObservation, BindingError> {
        use portable::NativeCodec;
        let mut state=self.0.borrow_mut();state.effects+=1;
        let saved=state.saved.as_ref().unwrap();
        // Record/tuple/variant declarations for distinct positions are nominal
        // Rust types. The public generated codecs bridge those native positions.
        macro_rules! copy { ($field:ident) => { NativeCodec::decode(&saved.$field.encode()?)? }; }
        let mut result=portable::PortableObservation {
            boolean:copy!(boolean), choice:copy!(choice), empty_record:copy!(empty_record),
            empty_tuple:copy!(empty_tuple), empty_variants:copy!(empty_variants), integer:copy!(integer), integers:copy!(integers),
            marker_record:copy!(marker_record),
            nested:copy!(nested), nested_sets:copy!(nested_sets), null:copy!(null), pair:copy!(pair),
            record:copy!(record), sequence:copy!(sequence), string_map:copy!(string_map), text:copy!(text),
        };
        if state.mutation=="duplicate-set" {result.integers=portable::MirrorSet(vec![1.into(),1.into()]);}
        if state.mutation=="duplicate-nested-set" {result.nested_sets=portable::MirrorSet(vec![
            portable::MirrorSet(vec![1.into(),2.into()]),portable::MirrorSet(vec![2.into(),1.into()])]);}
        Ok(result)
    }
}
fn roundtrip(defaults: &Json, type_id: &str, value: &Json, mutation: &str) -> Json {
    let state=Rc::new(RefCell::new(PortableState {mutation:mutation.into(),..Default::default()}));
    let mut binding=portable::bind_portable(PortablePort(state.clone()),&config(true)).unwrap();
    let mut payload=defaults.clone();payload[lower(type_id)]=value.clone();
    let payload:State=serde_json::from_value(payload).unwrap();
    match binding.compute("init",&payload,&State::new()) {
        Ok(result)=>{
            let again=binding.compute("init",&result,&State::new()).unwrap();
            json!({"accepted":true,"output":serde_json::to_value(&result).unwrap()[lower(type_id)],
                   "again":serde_json::to_value(&again).unwrap()[lower(type_id)],"effects":state.borrow().effects})
        },
        Err(error)=>{
            let before=state.borrow().effects;
            let again=binding.compute("init",&serde_json::from_value(defaults.clone()).unwrap(),&State::new());
            let poisoned=matches!(again,Err(ref error) if error.code=="binding_poisoned")&&state.borrow().effects==before;
            json!({"accepted":false,"error":error.code,"effects":state.borrow().effects,"poisoned":poisoned})
        }
    }
}
macro_rules! path_module {
    ($module:ident,$name:literal,$trait:ident,$observation:ident,$bind:ident) => {
        mod $module {
            include!(concat!(env!("MITL_GENERATED"),"/rust/",$name,"/",$name,"Mirror.generated.rs"));
            use std::{cell::RefCell,rc::Rc};
            struct Port {saved:Option<InitializeInput>,effects:Rc<RefCell<usize>>}
            impl $trait for Port {
                fn initialize(&mut self,input:InitializeInput)->Result<(),BindingError> {
                    *self.effects.borrow_mut()+=1;self.saved=Some(input);Ok(())
                }
                fn observe(&mut self)->Result<$observation,BindingError> {
                    *self.effects.borrow_mut()+=1;Ok($observation{value:NativeCodec::decode(&self.saved.as_ref().unwrap().value.encode()?)?})
                }
            }
            pub fn execute(value:&serde_json::Value)->serde_json::Value {
                use mirrorrust::FallibleStateComputer;
                let effects=Rc::new(RefCell::new(0));
                let mut binding=$bind(Port{saved:None,effects:effects.clone()},&super::config(true)).unwrap();
                let state=serde_json::from_value(if $name=="PathRootRecord" {value.clone()} else {serde_json::json!({"root":value})}).unwrap();
                match binding.compute("init",&state,&State::new()) {
                    Ok(result)=>serde_json::json!({"accepted":true,"output":serde_json::to_value(result).unwrap()["value"],"effects":*effects.borrow()}),
                    Err(error)=>serde_json::json!({"accepted":false,"error":error.code,"effects":*effects.borrow()}),
                }
            }
        }
    }
}
path_module!(root_record,"PathRootRecord",PathRootRecordPort,PathRootRecordObservation,bind_path_root_record);
path_module!(record_field,"PathRecordField",PathRecordFieldPort,PathRecordFieldObservation,bind_path_record_field);
path_module!(tuple_index,"PathTupleIndex",PathTupleIndexPort,PathTupleIndexObservation,bind_path_tuple_index);
path_module!(sequence_index,"PathSequenceIndex",PathSequenceIndexPort,PathSequenceIndexObservation,bind_path_sequence_index);
path_module!(sequence_range,"PathSequenceOutOfRange",PathSequenceOutOfRangePort,PathSequenceOutOfRangeObservation,bind_path_sequence_out_of_range);
path_module!(variant_projection,"PathVariantProjection",PathVariantProjectionPort,PathVariantProjectionObservation,bind_path_variant_projection);
path_module!(variant_tag,"PathVariantWrongTag",PathVariantWrongTagPort,PathVariantWrongTagObservation,bind_path_variant_wrong_tag);
path_module!(nested_projection,"PathNestedProjection",PathNestedProjectionPort,PathNestedProjectionObservation,bind_path_nested_projection);

#[derive(Default)]
struct RecordingState {events:Vec<Json>,count:BigInt,mode:String}
struct RecordingPort(Rc<RefCell<RecordingState>>);
impl recording::RecordingPort for RecordingPort {
    fn initialize(&mut self)->Result<(),BindingError> {
        let mut s=self.0.borrow_mut();s.events.push(json!({"event":"action","id":"Initialize","inputs":{}}));
        if s.mode=="adapter_failure" {return Err(BindingError::new("custom","deliberate adapter failure"));}
        s.count=0.into();Ok(())
    }
    fn tick(&mut self,input:recording::TickInput)->Result<(),BindingError> {
        let mut s=self.0.borrow_mut();s.events.push(json!({"event":"action","id":"Tick","inputs":{"Enabled":input.enabled,"Stride":bigint(&input.stride)}}));
        if s.mode=="adapter_failure" {return Err(BindingError::new("custom","deliberate adapter failure"));}
        if input.enabled {s.count+=input.stride;}Ok(())
    }
    fn observe(&mut self)->Result<recording::RecordingObservation,BindingError> {
        let mut s=self.0.borrow_mut();
        if s.mode=="observer_failure" {s.events.push(json!({"event":"observe_failure"}));return Err(BindingError::new("custom","deliberate observer failure"));}
        let count=s.count.clone();s.events.push(json!({"event":"observe","values":{"Count":bigint(&count)}}));
        // This typed construction witnesses the complete native count field.
        Ok(recording::RecordingObservation{count})
    }
}
fn main() {
    let root=std::env::args().nth(1).expect("fixture directory");
    for (name,identity) in [("Portable",portable::model_interface()),("Recording",recording::model_interface())] {
        emit("identity",&json!(name),json!({"semanticDigest":identity.semantic_digest,"contract":serde_json::from_str::<Json>(&identity.contract_json).unwrap()}));
    }
    let mut defaults=json!({});
    for row in rows(&root,"mitl-types.jsonl") {if row["portable"]==true {defaults[lower(row["id"].as_str().unwrap())]=row["default"].clone();}}
    for row in rows(&root,"mitl-values.jsonl") {emit("value",&row["id"],roundtrip(&defaults,row["typeId"].as_str().unwrap(),&row["value"],""));}
    for row in rows(&root,"mitl-equivalence.jsonl") {emit("equivalence",&row["id"],json!({
        "left":roundtrip(&defaults,row["typeId"].as_str().unwrap(),&row["left"],""),
        "right":roundtrip(&defaults,row["typeId"].as_str().unwrap(),&row["right"],"")}));}
    for row in rows(&root,"native-encoding.jsonl") {let field=row["field"].as_str().unwrap();emit("encode",&row["id"],roundtrip(&defaults,field,&defaults[lower(field)],row["mutation"].as_str().unwrap()));}
    for row in rows(&root,"mitl-paths.jsonl") {
        if row["static"]==false||row["generatedPortable"]==false {continue;}
        let result=match row["id"].as_str().unwrap() {
            "RootRecord"=>root_record::execute(&row["value"]),"RecordField"=>record_field::execute(&row["value"]),"TupleIndex"=>tuple_index::execute(&row["value"]),
            "SequenceIndex"=>sequence_index::execute(&row["value"]),"SequenceOutOfRange"=>sequence_range::execute(&row["value"]),
            "VariantProjection"=>variant_projection::execute(&row["value"]),"VariantWrongTag"=>variant_tag::execute(&row["value"]),
            "NestedProjection"=>nested_projection::execute(&row["value"]),id=>panic!("unknown path {id}"),
        };emit("path",&row["id"],result);
    }
    for row in rows(&root,"counter-binding-events.jsonl") {
        if row.get("targets").is_some() {continue;}
        let state=Rc::new(RefCell::new(RecordingState::default()));let mut errors=vec![];let mut wire_frames=vec![];let mut coverage=json!({"Initialize":0,"Tick":0});
        match recording::bind_recording(RecordingPort(state.clone()),&config(row["configValid"].as_bool().unwrap())) {
            Err(error)=>errors.push(json!(error.code)),
            Ok(mut binding)=>{
                for step in row["steps"].as_array().unwrap() {
                    state.borrow_mut().mode=step["mode"].as_str().unwrap().into();
                    let payload=serde_json::from_value(step["payload"].clone()).unwrap();
                    match binding.compute(step["action"].as_str().unwrap(),&payload,&State::new()) {
                        Ok(result)=>{
                            wire_frames.push(mirrorrust::encode_client_message(&mirrorrust::ClientMessage::ReportState {state:result.clone()}));
                            state.borrow_mut().events.push(json!({"event":"report","state":result}));errors.push(Json::Null);
                        }
                        Err(error)=>errors.push(json!(error.code)),
                    }
                }coverage=serde_json::to_value(binding.coverage()).unwrap();
            }
        }
        emit("recording",&row["id"],json!({"events":state.borrow().events,"errors":errors,"coverage":coverage,"wireFrames":wire_frames}));
    }
}
