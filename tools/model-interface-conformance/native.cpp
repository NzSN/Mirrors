#include "PortableMirror.generated.hpp"
#include "RecordingMirror.generated.hpp"
#include "PathRootRecordMirror.generated.hpp"
#include "PathRecordFieldMirror.generated.hpp"
#include "PathTupleIndexMirror.generated.hpp"
#include "PathSequenceIndexMirror.generated.hpp"
#include "PathSequenceOutOfRangeMirror.generated.hpp"
#include "PathVariantProjectionMirror.generated.hpp"
#include "PathVariantWrongTagMirror.generated.hpp"
#include "PathNestedProjectionMirror.generated.hpp"
#include <fstream>
#include <iostream>
#include <optional>
#include <type_traits>

using Json = nlohmann::json;
using namespace mirrorcpp;
namespace portable = mirrors_generated::portable;
namespace recording = mirrors_generated::recording;

// The observation's field exists on every value of the native type, including
// default-constructed C++ aggregates. Raw JSON's missing/extra/wrong-type shapes
// are instead exercised through every target's generated closed-record codec.
static_assert(std::is_same_v<decltype(recording::RecordingObservation::count), Value::Int>);

std::vector<Json> rows(const std::string& root, const char* name) {
  std::ifstream file(root + "/" + name);
  if (!file) throw std::runtime_error(std::string("missing corpus ") + name);
  std::vector<Json> result;
  for (std::string line; std::getline(file,line);) if (!line.empty()) result.push_back(Json::parse(line));
  return result;
}
std::string lower(std::string name) { name[0] = static_cast<char>(std::tolower(name[0])); return name; }
Json bigint(const Value::Int& value) { return {{"#bigint",value.str()}}; }
ApalacheConfig config(bool valid=true) {
  ApalacheConfig result; result.param_vars=valid?"parameters":"wrong"; return result;
}
void emit(const char* family, const Json& id, Json result) {
  result["family"]=family;result["id"]=id;std::cout << result.dump() << '\n';
}
#define PORTABLE_FIELDS(X) X(boolean) X(choice) X(emptyRecord) X(emptyTuple) X(emptyVariants) X(integer) X(integers) X(markerRecord) X(nested) X(nestedSets) X(null) X(pair) X(record) X(sequence) X(stringMap) X(text)
struct PortablePort final : portable::PortablePort {
  std::optional<portable::InitializeInput> saved;
  int effects=0;
  std::string mutation;
  void initialize(const portable::InitializeInput& input) override { ++effects;saved=input; }
  portable::PortableObservation observe() override {
    ++effects;
    portable::PortableObservation result;
#define COPY(name) result.name=saved->name;
    PORTABLE_FIELDS(COPY)
#undef COPY
    if(mutation=="duplicate-set") result.integers.values={Value::Int(1),Value::Int(1)};
    if(mutation=="duplicate-nested-set") result.nestedSets.values={{{Value::Int(1),Value::Int(2)}},{{Value::Int(2),Value::Int(1)}}};
    return result;
  }
};
Json roundtrip(const Json& defaults,const std::string& type,const Json& value,const std::string& mutation="") {
  PortablePort port;port.mutation=mutation;
  auto binding=portable::bind_portable(port,config());
  Json payload=defaults;payload[lower(type)]=value;
  try {
    const auto result=encode_state(binding.computer("init",decode_state(payload),{}));
    const auto again=encode_state(binding.computer("init",decode_state(result),{}));
    return {{"accepted",true},{"output",result.at(lower(type))},{"again",again.at(lower(type))},{"effects",port.effects}};
  } catch(const ModelInterfaceBindingError& error) {
    const auto before=port.effects;bool poisoned=false;
    try { binding.computer("init",decode_state(defaults),{}); }
    catch(const ModelInterfaceBindingError& next) { poisoned=next.code()=="binding_poisoned" && port.effects==before; }
    return {{"accepted",false},{"error",error.code()},{"effects",port.effects},{"poisoned",poisoned}};
  }
}

#define DEFINE_PATH(Module, space) \
Json path_##Module(const Json& value) { \
  namespace generated=mirrors_generated::space; \
  struct Port final : generated::Module##Port { \
    std::optional<generated::InitializeInput> saved; int effects=0; \
    void initialize(const generated::InitializeInput& input) override {++effects;saved=input;} \
    generated::Module##Observation observe() override {++effects;return {saved->value};} \
  } port; \
  auto binding=generated::bind_##space(port,config()); \
  try { auto state=binding.computer("init",decode_state(std::string(#Module)=="PathRootRecord"?value:Json{{"root",value}}),{}); \
    return {{"accepted",true},{"output",encode_state(state).at("value")},{"effects",port.effects}}; \
  } catch(const ModelInterfaceBindingError& error) {return {{"accepted",false},{"error",error.code()},{"effects",port.effects}};} \
}
DEFINE_PATH(PathRootRecord,pathRootRecord)
DEFINE_PATH(PathRecordField,pathRecordField)
DEFINE_PATH(PathTupleIndex,pathTupleIndex)
DEFINE_PATH(PathSequenceIndex,pathSequenceIndex)
DEFINE_PATH(PathSequenceOutOfRange,pathSequenceOutOfRange)
DEFINE_PATH(PathVariantProjection,pathVariantProjection)
DEFINE_PATH(PathVariantWrongTag,pathVariantWrongTag)
DEFINE_PATH(PathNestedProjection,pathNestedProjection)

struct RecordingPort final : recording::RecordingPort {
  Json events=Json::array(); Value::Int count=0; std::string mode="ok";
  void initialize() override {
    events.push_back({{"event","action"},{"id","Initialize"},{"inputs",Json::object()}});
    if(mode=="adapter_failure") throw std::runtime_error("deliberate adapter failure");
    count=0;
  }
  void tick(const recording::TickInput& input) override {
    events.push_back({{"event","action"},{"id","Tick"},{"inputs",{{"Enabled",input.enabled},{"Stride",bigint(input.stride)}}}});
    if(mode=="adapter_failure") throw std::runtime_error("deliberate adapter failure");
    if(input.enabled) count+=input.stride;
  }
  recording::RecordingObservation observe() override {
    if(mode=="observer_failure") {events.push_back({{"event","observe_failure"}});throw std::runtime_error("deliberate observer failure");}
    events.push_back({{"event","observe"},{"values",{{"Count",bigint(count)}}}});
    return {count};
  }
};
int main(int argc,char** argv) {
  try {
    if(argc!=2) throw std::runtime_error("expected fixture directory");
    emit("identity","Portable",{{"semanticDigest",portable::PortableModelInterface.semantic_digest},{"contract",Json::parse(portable::PortableModelInterface.contract_json)}});
    emit("identity","Recording",{{"semanticDigest",recording::RecordingModelInterface.semantic_digest},{"contract",Json::parse(recording::RecordingModelInterface.contract_json)}});
    const std::string root=argv[1]; Json defaults=Json::object();
    for(const auto& row:rows(root,"mitl-types.jsonl")) if(row.at("portable")==true) defaults[lower(row.at("id"))]=row.at("default");
    for(const auto& row:rows(root,"mitl-values.jsonl")) emit("value",row.at("id"),roundtrip(defaults,row.at("typeId"),row.at("value")));
    for(const auto& row:rows(root,"mitl-equivalence.jsonl")) emit("equivalence",row.at("id"),{
      {"left",roundtrip(defaults,row.at("typeId"),row.at("left"))},
      {"right",roundtrip(defaults,row.at("typeId"),row.at("right"))}});
    for(const auto& row:rows(root,"native-encoding.jsonl")) emit("encode",row.at("id"),roundtrip(defaults,row.at("field"),defaults.at(lower(row.at("field"))),row.at("mutation")));
    for(const auto& row:rows(root,"mitl-paths.jsonl")) {
      if(!row.value("static",true)||!row.value("generatedPortable",true)) continue;
      const auto id=row.at("id").get<std::string>();Json result;
#define PATH_CASE(Id) if(id==#Id) result=path_Path##Id(row.at("value")); else
      PATH_CASE(RootRecord) PATH_CASE(RecordField) PATH_CASE(TupleIndex) PATH_CASE(SequenceIndex)
      PATH_CASE(SequenceOutOfRange) PATH_CASE(VariantProjection) PATH_CASE(VariantWrongTag)
      PATH_CASE(NestedProjection) throw std::runtime_error("unknown generated path fixture: "+id);
#undef PATH_CASE
      emit("path",id,result);
    }
    for(const auto& row:rows(root,"counter-binding-events.jsonl")) {
      if(row.contains("targets")) continue;
      RecordingPort port; Json errors=Json::array(),wireFrames=Json::array(),coverage={{"Initialize",0},{"Tick",0}};
      try {
        auto binding=recording::bind_recording(port,config(row.at("configValid")));
        for(const auto& step:row.at("steps")) {
          port.mode=step.at("mode");
          try {
            auto state=binding.computer(step.at("action").get<std::string>(),decode_state(step.at("payload")),{});
            wireFrames.push_back(encode_client_message(ReportState{state}));
            port.events.push_back({{"event","report"},{"state",encode_state(state)}});errors.push_back(nullptr);
          } catch(const ModelInterfaceBindingError& error) {errors.push_back(error.code());}
        }
        coverage=binding.coverage();
      } catch(const ModelInterfaceBindingError& error) {errors.push_back(error.code());}
      emit("recording",row.at("id"),{{"events",port.events},{"errors",errors},{"coverage",coverage},{"wireFrames",wireFrames}});
    }
    return 0;
  } catch(const std::exception& error) {std::cerr<<error.what()<<'\n';return 1;}
}
