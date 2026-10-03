import CounterMirror
import TypesMirror
import EmptyVariantsMirror

open MirrorLean MirrorLean.ModelInterface

private def require (ok : Bool) (label : String) : IO Unit :=
  unless ok do throw (IO.userError label)

private def unwrap (result : Except BindingError α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw (IO.userError s!"{error.code}: {error.message}")

private def codeIs (result : Except BindingError α) (code : String) : Bool :=
  match result with | .error error => error.code == code | .ok _ => false

private def config : ApalacheConfig := {
  specPath := "specs/Counter.tla", paramVars := some "parameters"
  invariant := "TraceComplete", lengthBound := 3 }
private def empty : State := State.ofList []
private def params (stride : Value) : State :=
  State.ofList [("parameters", .record #[("stride", stride)])]

private structure Sut where
  count : Int := 0
  events : Array String := #[]
  mode : Nat := 0

private def port (sut : IO.Ref Sut) : CounterMirror.Port where
  «initialize» := do
    sut.modify fun s => { s with count := 0, events := s.events.push "Initialize" }
    pure (.ok ())
  tick input := do
    sut.modify fun s => { s with events := s.events.push "Tick" }
    if (← sut.get).mode == 1 then return .error { code := "custom", message := "adapter failed" }
    if (← sut.get).mode == 2 then throw (IO.userError "adapter threw")
    sut.modify fun s => { s with count := s.count + input.stride }
    pure (.ok ())
  observe := do
    sut.modify fun s => { s with events := s.events.push "Observe" }
    let state ← sut.get
    if state.mode == 3 then return .error { code := "custom", message := "observer failed" }
    if state.mode == 4 then throw (IO.userError "observer threw")
    pure (.ok { count := if state.mode == 5 then state.count + 1 else state.count })

private def binding : IO (CounterMirror.Binding × IO.Ref Sut) := do
  let sut ← IO.mkRef ({} : Sut)
  let bound ← unwrap (← CounterMirror.bind (port sut) config)
  pure (bound, sut)

private def lifecycleTests : IO Unit := do
  let (bound, sut) ← binding
  require (codeIs (← bound.assertAllActionsCovered) "uncovered_action") "fresh coverage"
  let initial ← unwrap (← bound.computer "init" empty empty)
  require (initial.get? "count" == some (.int 0)) "initial report"
  let reported ← unwrap (← bound.computer "tick" (params (.int 2))
    (State.ofList [("count", .int 999)]))
  require (reported.get? "count" == some (.int 2)) "native handler and previous-state isolation"
  require ((← sut.get).events == #["Initialize", "Observe", "Tick", "Observe"]) "callback order"
  require ((← bound.coverage) == #[("Initialize", 1), ("Tick", 1)]) "stable coverage"
  let _ ← unwrap (← bound.assertAllActionsCovered)
  let _ ← unwrap (← bound.computer "init" empty empty)
  require ((← sut.get).count == 0) "reinitialization"
  for (action, payload, code) in [
      ("tick", params (.int 1), "transition_before_initialization"),
      ("unknown", empty, "unknown_action")] do
    let (b, s) ← binding
    require (codeIs (← b.computer action payload empty) code) code
    require (codeIs (← b.computer "init" empty empty) "binding_poisoned") "poisoned retry"
    require ((← s.get).events.isEmpty) "no effects before initialization"
  let (bad, badSut) ← binding
  let _ ← unwrap (← bad.computer "init" empty empty)
  require (codeIs (← bad.computer "tick" (params (.bool true)) empty) "input_shape_mismatch") "strict input"
  require ((← badSut.get).events == #["Initialize", "Observe"]) "decode before action"
  require (codeIs (← bad.computer "tick" (params (.int 1)) empty) "binding_poisoned") "decode poisons"
  for mode in [1, 2, 3, 4] do
    let (b, s) ← binding
    let _ ← unwrap (← b.computer "init" empty empty)
    s.modify fun x => { x with mode }
    let code := if mode < 3 then "adapter_failure" else "observation_shape_mismatch"
    require (codeIs (← b.computer "tick" (params (.int 1)) empty) code) s!"failure stage {mode}"
    require (codeIs (← b.computer "init" empty empty) "binding_poisoned") "failure poison"
    require ((← b.coverage) == #[("Initialize", 1), ("Tick", 0)]) "failed action not covered"
    require ((← s.get).events.size == if mode < 3 then 3 else 4) "failure effect boundary"
  let fresh ← IO.mkRef ({} : Sut)
  require (codeIs (← CounterMirror.bind (port fresh) { config with paramVars := none })
    "configuration_mismatch") "effective config required"
  require ((← fresh.get).events.isEmpty) "configuration failure has no port effects"
  let (wrong, wrongSut) ← binding
  let _ ← unwrap (← wrong.computer "init" empty empty)
  wrongSut.modify fun s => { s with mode := 5 }
  let incorrect ← unwrap (← wrong.computer "tick" (params (.int 2)) empty)
  require (incorrect.get? "count" == some (.int 3)) "wrong observation is reported honestly"
  let (first, _) ← binding
  let (second, secondSut) ← binding
  let _ ← unwrap (← first.computer "init" empty empty)
  require (codeIs (← second.computer "tick" (params (.int 1)) empty)
    "transition_before_initialization") "factory state is fresh"
  require ((← secondSut.get).events.isEmpty) "fresh binding isolates SUT"
  let recursive ← IO.mkRef (none : Option CounterMirror.Binding)
  let reentry ← IO.mkRef ""
  let observed ← IO.mkRef false
  let guarded ← unwrap (← CounterMirror.bind {
    «initialize» := do
      if let some b ← recursive.get then
        match ← b.computer "init" empty empty with
        | .error error => reentry.set error.code
        | .ok _ => reentry.set "unexpected-success"
      pure (.ok ())
    tick _ := pure (.ok ())
    observe := do
      observed.set true
      pure (.ok { count := 0 })
  } config)
  recursive.set (some guarded)
  require (codeIs (← guarded.computer "init" empty empty) "binding_poisoned") "reentrant callback poisons"
  require ((← reentry.get) == "adapter_failure" && !(← observed.get)) "poison prevents subsequent observation"

private def structuralValue : Value := .record #[
  ("bool", .bool true), ("integer", .int 123456789012345678901234567890),
  ("map", .map #[(.str "key", .seq #[.int 2])]), ("null", .null),
  ("record", .record #[("tag", .str "ordinary")]), ("seq", .seq #[.int 1, .int 2]),
  ("set", .set #[.set #[.int 1, .int 2], .set #[.int 3]]),
  ("tuple", .tuple #[.bool false, .str "text"]), ("variant", .variant "some" (.int 7))]

private def replace (key : String) (value : Value) : Value :=
  match structuralValue with
  | .record fields => .record (fields.map fun (name, old) => (name, if name == key then value else old))
  | _ => structuralValue

private def structuralTests : IO Unit := do
  let native : TypesMirror.MiTypeA0I0 ← unwrap (NativeCodec.decode structuralValue)
  let roundtrip ← unwrap (NativeCodec.encode native)
  require (equivalent structuralValue roundtrip) "all portable native types round trip"
  for bad in [
      replace "integer" (.bool true), replace "null" (.str ""),
      replace "seq" (.tuple #[.int 1]), replace "tuple" (.seq #[.bool false, .str "text"]),
      replace "tuple" (.tuple #[.bool false]),
      replace "map" (.map #[(.int 1, .seq #[])]),
      replace "map" (.map #[(.str "k", .seq #[]), (.str "k", .seq #[])]),
      replace "set" (.set #[.set #[.int 1, .int 2], .set #[.int 2, .int 1]]),
      replace "record" (.record #[("tag", .str "a"), ("tag", .str "b")]),
      replace "record" (.record #[("extra", .str "a")]),
      replace "variant" (.variant "bad" (.int 7)),
      replace "variant" (.variant "some" (.bool true)),
      replace "integer" (.unserializable "opaque")] do
    require (!(NativeCodec.decode (α := TypesMirror.MiTypeA0I0) bad).isOk)
      s!"strict structural rejection: {repr bad}"
  let badSet := { native with field6 := { items := #[{ items := #[1, 2] }, { items := #[2, 1] }] } }
  require (!(NativeCodec.encode badSet).isOk) "native duplicate set observation rejected"
  let badMap := { native with field2 := { entries := #[("k", { items := #[] }), ("k", { items := #[] })] } }
  require (!(NativeCodec.encode badMap).isOk) "native duplicate map observation rejected"
  let observations ← IO.mkRef (none : Option TypesMirror.Observation)
  let events ← IO.mkRef (#[] : Array String)
  let bound ← unwrap (← TypesMirror.bind {
    «initialize» input := do
      events.modify (·.push "Initialize")
      let value ← unwrap (NativeCodec.encode input.payload)
      let payload ← unwrap (NativeCodec.decode value)
      observations.set (some { payload })
      pure (.ok ())
    observe := do
      events.modify (·.push "Observe")
      match ← observations.get with
      | some observation => pure (.ok observation)
      | none => pure (.error shape)
  } config)
  let state := State.ofList [("payload", structuralValue), ("#meta", .int 9),
    ("parameters", .int 8), ("action_taken", .str "reset")]
  let report ← unwrap (← bound.computer "reset" state empty)
  require (report.get? "payload" |>.any (equivalent structuralValue)) "alias and structural binding"
  require ((← events.get) == #["Initialize", "Observe"]) "structural callback order"
  let observation ← observations.get
  if let some o := observation then
    observations.set (some { payload := { o.payload with
      field6 := { items := #[{ items := #[1] }, { items := #[1] }] } } })
  let invalidPort : TypesMirror.Port := {
    «initialize» _ := pure (.ok ())
    observe := do
      match ← observations.get with
      | some o => pure (.ok o)
      | none => pure (.error shape) }
  let invalid ← unwrap (← TypesMirror.bind invalidPort config)
  require (codeIs (← invalid.computer "init" state empty) "observation_shape_mismatch")
    "generated native observation validation"
  require ((← invalid.coverage) == #[("Initialize", 0)]) "bad native observation not covered"
  require (codeIs (← invalid.computer "reset" state empty) "binding_poisoned") "observation poisons"

private def emptyVariantTests : IO Unit := do
  let empty : MirrorSeq EmptyVariantsMirror.MiTypeA0I0Item ← unwrap
    (NativeCodec.decode (.seq #[]))
  require ((← unwrap (NativeCodec.encode empty)) == .seq #[]) "empty-variant sequence round trip"
  require (!(NativeCodec.decode (α := MirrorSeq EmptyVariantsMirror.MiTypeA0I0Item)
    (.seq #[.variant "impossible" .null])).isOk) "empty variant has no values"
  let called ← IO.mkRef false
  let bound ← unwrap (← EmptyVariantsMirror.bind {
    «initialize» input := do
      require input.payload.items.isEmpty "empty-variant native input"
      called.set true
      pure (.ok ())
    observe := pure (.ok { payload := { items := #[] } })
  } config)
  let report ← unwrap (← bound.computer "init" (State.ofList [("payload", .seq #[])]) emptyState)
  require ((← called.get) && report.get? "payload" == some (.seq #[])) "empty-variant generated binding"
where
  emptyState : State := State.ofList []

def main : IO Unit := do
  lifecycleTests
  structuralTests
  emptyVariantTests
  IO.println "mirrorlean generated native acceptance: lifecycle, strict codecs, coverage, wrong observation, freshness PASS"
