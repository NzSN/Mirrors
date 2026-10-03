#!/usr/bin/env python3
"""Author the reviewed MITL examples; execution gates never regenerate goldens."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[2] / "test/fixtures/model-interface/language"
ROOT.mkdir(parents=True, exist_ok=True)

def write(name, rows):
    (ROOT / name).write_text("".join(json.dumps(row, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n" for row in rows))

def t(kind, **rest): return {"kind": kind, **rest}
def integer(n): return {"#bigint": str(n)}
def seq(*values): return list(values)
def tup(*values): return {"#tup": list(values)}
def aset(*values): return {"#set": list(values)}
def amap(*entries): return {"#map": [list(entry) for entry in entries]}
def variant(tag, value): return {"tag": tag, "value": value}
def field(name, ty): return {"wireName": name, "type": ty}

I, B, S, N = map(t, ("int", "bool", "str", "null"))
types = [
    ("Integer", I, integer(0)), ("Boolean", B, False), ("Text", S, ""), ("Null", N, None),
    ("Integers", t("set", element=I), aset()),
    ("NestedSets", t("set", element=t("set", element=I)), aset()),
    ("Sequence", t("seq", element=S), []),
    ("Pair", t("tuple", elements=[I, B]), tup(integer(0), False)),
    ("EmptyTuple", t("tuple", elements=[]), tup()),
    ("EmptyVariants", t("seq", element=t("variant", cases=[])), []),
    ("Record", t("record", fields=[field("text", S), field("number", I)]), {"text": "", "number": integer(0)}),
    ("EmptyRecord", t("record", fields=[]), {}),
    ("MarkerRecord", t("record", fields=[field("#set", t("seq", element=I)), field("ordinary", B)]), {"#set": [], "ordinary": False}),
    ("StringMap", t("map", key=S, value=t("seq", element=I)), amap()),
    ("Choice", t("variant", cases=[{"tag": "some", "payload": I}, {"tag": "none", "payload": N}]), variant("none", None)),
    ("Nested", t("record", fields=[field("items", t("seq", element=t("variant", cases=[{"tag": "flag", "payload": B}])))]), {"items": [variant("flag", False)]}),
]
type_rows = [{"id": name, "type": ty, "wellFormed": True, "portable": True, "default": value} for name, ty, value in types]
type_rows += [
    {"id": "IntegerMapExcluded", "type": t("map", key=I, value=I), "wellFormed": True, "portable": False},
    {"id": "OpaqueExcluded", "type": t("opaqueItf", description="handle"), "wellFormed": True, "portable": False},
    {"id": "DuplicateRecordField", "type": t("record", fields=[field("x", I), field("x", B)]), "wellFormed": False, "portable": False},
    {"id": "EmptyRecordField", "type": t("record", fields=[field("", I)]), "wellFormed": False, "portable": False},
    {"id": "DuplicateVariantTag", "type": t("variant", cases=[{"tag": "x", "payload": I}, {"tag": "x", "payload": B}]), "wellFormed": False, "portable": False},
    {"id": "EmptyVariantTag", "type": t("variant", cases=[{"tag": "", "payload": I}]), "wellFormed": False, "portable": False},
    {"id": "EmptyOpaque", "type": t("opaqueItf", description=""), "wellFormed": False, "portable": False},
]
write("mitl-types.jsonl", type_rows)

values = []
def value(id, ty, v, accepted=True): values.append({"id": id, "typeId": ty, "value": v, "accepted": accepted})
for name, _, default in types: value(name + "Default", name, default)
value("HugePositive", "Integer", integer(10**90 + 7))
value("HugeNegative", "Integer", integer(-(10**90 + 9)))
value("UnicodeEscapes", "Text", 'λ\n"\\\0尾')
value("IntegerWrong", "Integer", "2", False)
value("BooleanWrong", "Boolean", integer(1), False)
value("TextWrong", "Text", False, False)
value("NullTuple", "Null", tup(), False)
value("NullRecord", "Null", {}, False)
value("TupleNull", "EmptyTuple", None, False)
value("RecordTuple", "EmptyRecord", tup(), False)
value("SetOrder", "Integers", aset(integer(3), integer(1), integer(2)))
value("DuplicateSet", "Integers", aset(integer(1), integer(1)), False)
value("WrongSetMember", "Integers", aset(integer(1), "2"), False)
value("NestedSetOrder", "NestedSets", aset(aset(integer(2), integer(1)), aset(integer(3))))
value("NestedSemanticDuplicate", "NestedSets", aset(aset(integer(1), integer(2)), aset(integer(2), integer(1))), False)
value("NestedInvalidMember", "NestedSets", aset(aset(integer(1), integer(1))), False)
value("SequenceOrder", "Sequence", ["first", "second", "first"])
value("SequenceSet", "Sequence", aset("x"), False)
value("PairValue", "Pair", tup(integer(2**100), True))
value("PairArity", "Pair", tup(integer(1)), False)
value("PairSequence", "Pair", [integer(1), True], False)
value("EmptyVariantImpossibleElement", "EmptyVariants", [variant("impossible", None)], False)
value("ClosedRecord", "Record", {"number": integer(7), "text": "ok"})
value("RecordMissing", "Record", {"number": integer(7)}, False)
value("RecordExtra", "Record", {"number": integer(7), "text": "ok", "extra": False}, False)
value("RecordWrong", "Record", {"number": "7", "text": "ok"}, False)
value("EmptyRecordExtra", "EmptyRecord", {"extra": None}, False)
value("OrdinaryMarkerRecord", "MarkerRecord", {"#set": [integer(7)], "ordinary": True})
value("MarkerRecordMissing", "MarkerRecord", {"ordinary": True}, False)
value("MapValue", "StringMap", amap(("z", [integer(2)]), ("a", [])))
value("MapDuplicateKey", "StringMap", amap(("a", []), ("a", [integer(2)])), False)
value("MapWrongKey", "StringMap", amap((integer(1), [])), False)
value("MapWrongValue", "StringMap", amap(("a", [False])), False)
value("VariantSome", "Choice", variant("some", integer(9)))
value("VariantUnknown", "Choice", variant("other", None), False)
value("VariantWrongPayload", "Choice", variant("some", False), False)
value("NestedValue", "Nested", {"items": [variant("flag", True), variant("flag", False)]})
value("NestedWrong", "Nested", {"items": [variant("flag", "true")]}, False)
write("mitl-values.jsonl", values)

equivalences = []
def eq(id, ty, left, right, result, leftAccepted=True, rightAccepted=True):
    equivalences.append({"id": id, "typeId": ty, "left": left, "right": right, "equivalent": result,
                         "leftAccepted": leftAccepted, "rightAccepted": rightAccepted})
eq("IntegerEqual", "Integer", integer(10**90), integer(10**90), True)
eq("IntegerDifferent", "Integer", integer(1), integer(2), False)
eq("SetPermutation", "Integers", aset(integer(1), integer(2)), aset(integer(2), integer(1)), True)
eq("SetDifferent", "Integers", aset(integer(1)), aset(integer(2)), False)
eq("DuplicateNotEqual", "Integers", aset(integer(1), integer(1)), aset(integer(1)), False, leftAccepted=False)
eq("NestedSetPermutation", "NestedSets", aset(aset(integer(1), integer(2)), aset(integer(3))), aset(aset(integer(3)), aset(integer(2), integer(1))), True)
eq("SequencePermutation", "Sequence", ["a", "b"], ["b", "a"], False)
eq("TupleEqual", "Pair", tup(integer(1), True), tup(integer(1), True), True)
eq("RecordEqual", "Record", {"text": "x", "number": integer(2)}, {"number": integer(2), "text": "x"}, True)
eq("MarkerOrdinaryField", "MarkerRecord", {"#set": [], "ordinary": False}, {"#set": [], "ordinary": True}, False)
eq("MapPermutation", "StringMap", amap(("b", []), ("a", [integer(1)])), amap(("a", [integer(1)]), ("b", [])), True)
eq("MapDuplicateNotEqual", "StringMap", amap(("a", []), ("a", [])), amap(("a", [])), False, leftAccepted=False)
eq("VariantTag", "Choice", variant("some", integer(0)), variant("none", None), False)
eq("NullConstructor", "Null", None, tup(), False, rightAccepted=False)
eq("EmptyConstructors", "EmptyTuple", tup(), {}, False, rightAccepted=False)
write("mitl-equivalence.jsonl", equivalences)

paths = [
    {"id": "RootRecord", "typeId": "Record", "value": {"text": "x", "number": integer(7)}, "path": [], "type": t("record", fields=[field("text", S), field("number", I)]), "result": {"text": "x", "number": integer(7)}, "stateRoot": True},
    {"id": "RecordField", "typeId": "Record", "value": {"text": "x", "number": integer(7)}, "path": [{"field": "number"}], "type": I, "result": integer(7)},
    {"id": "MissingField", "typeId": "Record", "value": {"text": "x", "number": integer(7)}, "path": [{"field": "absent"}], "static": False},
    {"id": "TupleIndex", "typeId": "Pair", "value": tup(integer(7), True), "path": [{"index": 1}], "type": B, "result": True},
    {"id": "TupleOutOfRange", "typeId": "Pair", "value": tup(integer(7), True), "path": [{"index": 2}], "static": False},
    {"id": "SequenceIndex", "typeId": "Sequence", "value": ["x"], "path": [{"index": 0}], "type": S, "result": "x"},
    {"id": "SequenceOutOfRange", "typeId": "Sequence", "value": [], "path": [{"index": 0}], "type": S, "dynamic": False},
    {"id": "VariantProjection", "typeId": "Choice", "value": variant("some", integer(8)), "path": [{"variantValue": "some"}], "type": I, "result": integer(8)},
    {"id": "VariantWrongTag", "typeId": "Choice", "value": variant("none", None), "path": [{"variantValue": "some"}], "type": I, "dynamic": False},
    {"id": "NestedProjection", "typeId": "Nested", "value": {"items": [variant("flag", True)]}, "path": [{"field": "items"}, {"index": 0}, {"variantValue": "flag"}], "type": B, "result": True},
    {"id": "MapProjection", "typeId": "StringMap", "value": amap(("a", [integer(9)])), "path": [{"mapKey": {"kind": "str", "value": "a"}}, {"index": 0}], "type": I, "result": integer(9), "generatedPortable": False},
    {"id": "MapMissing", "typeId": "StringMap", "value": amap(), "path": [{"mapKey": {"kind": "str", "value": "a"}}], "type": t("seq", element=I), "dynamic": False, "generatedPortable": False},
]
write("mitl-paths.jsonl", paths)

def payload(n=2, enabled=True): return {"parameters": {"stride": integer(n), "meta": [variant("flag", enabled)]}}
def step(action, payload=None, mode="ok"):
    return {"action": action, "payload": payload or {}, "mode": mode}
def action(id, inputs=None): return {"event": "action", "id": id, "inputs": inputs or {}}
def observe(n): return {"event": "observe", "values": {"Count": integer(n)}}
def report(n): return {"event": "report", "state": {"count": integer(n)}}
def initial(): return [action("Initialize"), observe(0), report(0)]
def tick(n, count, enabled=True): return [action("Tick", {"Enabled": enabled, "Stride": integer(n)}), observe(count), report(count)]
rows = []
def recording(id, steps, events, errors, init=0, ticks=0, config=True, targets=None):
    # These bytes are authored from the reviewed expected reports, never from a
    # consumer's actual state. Consumers must return their SDK encoder's frame.
    frames = [json.dumps({"proto_step": "report_state", "state": event["state"]},
                         sort_keys=True, separators=(",", ":")) for event in events if event["event"] == "report"]
    row = {"id": id, "configValid": config, "steps": steps, "expected": {"events": events, "errors": errors, "coverage": {"Initialize": init, "Tick": ticks}, "wireFrames": frames}}
    if targets: row["targets"] = targets
    rows.append(row)
recording("Counter", [step("init"), step("tick", payload(2)), step("tick", payload(3))], initial() + tick(2,2) + tick(3,5), [None]*3, 1, 2)
recording("AliasesAndReset", [step("reset"), step("increment", payload(3)), step("init"), step("tick", payload(2,False))], initial()+tick(3,3)+initial()+tick(2,0,False), [None]*4, 2, 2)
recording("TransitionBeforeInit", [step("tick",payload()),step("init")], [], ["transition_before_initialization","binding_poisoned"])
recording("UnknownAction", [step("unknown"),step("init")], [], ["unknown_action","binding_poisoned"])
for id, bad in [
    ("MissingStride", {"parameters":{"meta":[variant("flag",True)]}}),
    ("WrongStride", {"parameters":{"stride":"2","meta":[variant("flag",True)]}}),
    ("MissingMeta", {"parameters":{"stride":integer(2)}}),
    ("EmptyMeta", {"parameters":{"stride":integer(2),"meta":[]}}),
    ("WrongVariant", {"parameters":{"stride":integer(2),"meta":[variant("wrong",True)]}}),
    ("WrongEnabled", {"parameters":{"stride":integer(2),"meta":[variant("flag","true")]}}),
]: recording(id, [step("init"),step("tick",bad),step("init")], initial(), [None,"input_shape_mismatch","binding_poisoned"], 1)
extra=payload(); extra["parameters"]["unprojected"]="kept"; extra["unrelated"]=True
recording("UnprojectedFields", [step("init"),step("tick",extra)], initial()+tick(2,2), [None,None], 1,1)
recording("InitAdapterFailure", [step("init",mode="adapter_failure"),step("init")], [action("Initialize")], ["adapter_failure","binding_poisoned"])
recording("TickAdapterFailure", [step("init"),step("tick",payload(),"adapter_failure"),step("init")], initial()+[action("Tick",{"Enabled":True,"Stride":integer(2)})], [None,"adapter_failure","binding_poisoned"],1)
recording("ObserverFailure", [step("init",mode="observer_failure"),step("init")], [action("Initialize"),{"event":"observe_failure"}], ["observation_shape_mismatch","binding_poisoned"])
recording("ConfigurationMismatch", [], [], ["configuration_mismatch"], config=False)
for mode in ["missing_observation", "extra_observation", "mistyped_observation"]:
    recording(mode.title().replace("_",""),[step("init",mode=mode),step("init")],[action("Initialize"),observe(0)],["observation_shape_mismatch","binding_poisoned"],targets=["ts","async"])
write("counter-binding-events.jsonl", rows)

write("native-encoding.jsonl", [
    {"id": "NativeDuplicateSet", "field": "Integers", "mutation": "duplicate-set", "error": "observation_shape_mismatch"},
    {"id": "NativeNestedDuplicateSet", "field": "NestedSets", "mutation": "duplicate-nested-set", "error": "observation_shape_mismatch"},
])
