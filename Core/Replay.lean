import Core.Diff
import Core.Protocol
import Core.Trace

/-! The admitted synchronous replay of a finite bundle. A program describes
outgoing messages and reads in the order in which the transport executes them.
The cursor constructs one step at a time, including across trace boundaries. -/

namespace Core.Replay

abbrev Control := (p : Phase) × Session p
abbrev Input := Except String ValueMap

inductive Output where
  | validated
  | initialState (action : String) (vars : ValueMap)
  | nextStep (action : String) (params : ValueMap)
  | stepOk
  | allStepsDone
  | mismatch (expected actual : ValueMap) (hints : List DiffHint)
  | protocolError (message : String)

def prompt (st : Step) : Output :=
  if st.idx == 0 then .initialState st.act st.vars else .nextStep st.act st.params

inductive Program where
  | stop (control : Control)
  | send (output : Output) (next : Program)
  | receive (next : Input → Program)

/-- The interpreter used by the session shell. Only the two transport primitives
are parameters. A failed or blocked operation cannot run its continuation. -/
def Program.run [Monad m] (send : Output → m Unit) (receive : m Input) :
    Program → m Control
  | .stop control => pure control
  | .send output next => do send output; next.run send receive
  | .receive next => do (next (← receive)).run send receive

private structure Cursor where
  index : Nat
  current : TraceState
  rest : List TraceState
  traces : List ItfTrace

private def first : List ItfTrace → Option Cursor
  | [] => none
  | trace :: traces =>
    match trace.traceStates with
    | [] => first traces
    | st :: rest => some ⟨0, st, rest, traces⟩

private def Cursor.advance (c : Cursor) : Option Cursor :=
  match c.rest with
  | [] => first c.traces
  | st :: rest => some ⟨c.index + 1, st, rest, c.traces⟩

private def Cursor.remaining (c : Cursor) : List Step :=
  traceStepsAux c.index (c.current :: c.rest) ++ c.traces.flatMap traceSteps

private def remaining : Option Cursor → List Step
  | none => []
  | some c => c.remaining

private theorem first_remaining (traces : List ItfTrace) :
    remaining (first traces) = traces.flatMap traceSteps := by
  induction traces with
  | nil => rfl
  | cons t ts ih =>
    cases h : t.traceStates with
    | nil => simp [first, h, traceSteps, traceStepsAux, ih]
    | cons st rest => simp [first, h, remaining, Cursor.remaining, traceSteps]

private theorem advance_remaining (c : Cursor) :
    c.remaining = stepOf c.index c.current :: remaining c.advance := by
  cases c with
  | mk i st rest traces =>
    cases rest with
    | nil => simp [Cursor.advance, Cursor.remaining, traceStepsAux, first_remaining]
    | cons head tail => rfl

/-- A decoded input error or a mismatch ends this session. Only the final
matching report enables completion. The session phase is threaded through the
same protocol transition used for registration. -/
private def round (st : Step) (last : Bool) (control : Control)
    (onMatch : Control → Program) : Program :=
  .send (prompt st) (.receive fun input =>
    match input with
    | .error message => .send (.protocolError message) (.stop control)
    | .ok reported =>
      let diff := diffState st.vars reported
      let matchesReport := match diff with
        | .statesMatch => true
        | .stateMismatch .. => false
      match _root_.step ⟨true⟩ control.2 (.reportState matchesReport last) with
      | .error (.outOfOrder message) => .send (.protocolError message) (.stop control)
      | .ok ⟨phase, session, _⟩ =>
        let next : Control := ⟨phase, session⟩
        match diff with
        | .statesMatch => .send .stepOk (onMatch next)
        | .stateMismatch expected actual hints =>
          .send (.mismatch expected actual hints) (.stop next))

private def play (c : Cursor) (control : Control) : Program :=
  match _h : c.advance with
  | none => round (stepOf c.index c.current) true control
      (fun next => .send .allStepsDone (.stop next))
  | some tail => round (stepOf c.index c.current) false control (play tail ·)
termination_by c.remaining.length
decreasing_by
  have eq := advance_remaining c
  rw [_h] at eq
  simp [eq, remaining]

def session (traces : List ItfTrace) (control : Control) : Program :=
  .send .validated (match first traces with
    | none => .stop control
    | some c => play c control)

/-- Both registration routes enter the phase required by the replay theorem
when their validation and negotiation have admitted the bundle. -/
theorem admitted_phase {p p' : Phase} (s : Session p) (s' : Session p')
    (registration : ClientMessage) (out : List MirrorMessage)
    (route : registration = .register ∨ registration = .registerTraces)
    (admitted : _root_.step ⟨true⟩ s registration = .ok ⟨p', s', out⟩) :
    p' = .stepping := by
  rcases route with rfl | rfl <;> cases p <;> simp [_root_.step] at admitted <;>
    exact admitted.1.symm

inductive Event where
  | sent (output : Output)
  | received (input : Input)

/-- Every observable finite prefix, including an interrupted read or write.
An operation contributes its event when it is observed at the transport. -/
inductive Prefix : Program → List Event → Prop where
  | nil : Prefix p []
  | send : Prefix next events → Prefix (.send output next) (.sent output :: events)
  | receive : Prefix (next input) events →
      Prefix (.receive next) (.received input :: events)

/-- The transport history after an operation, including one that raised. -/
def endState : EStateM.Result ε σ α → σ
  | .ok _ w | .error _ w => w

/-- A transport recording relates typed events to their external observations
one-to-one, in order. The relation can retain raw inputs and encoded payloads. -/
inductive Recording (represents : Event → α → Prop) : List Event → List α → Prop where
  | nil : Recording represents [] []
  | cons : represents event observation → Recording represents events observations →
      Recording represents (event :: events) (observation :: observations)

theorem Recording.event_of_mem (recorded : Recording represents events observations)
    (seen : observation ∈ observations) : ∃ event ∈ events, represents event observation := by
  induction recorded with
  | nil => cases seen
  | cons head tail ih =>
    rcases List.mem_cons.mp seen with rfl | later
    · exact ⟨_, .head _, head⟩
    · obtain ⟨event, atEvent, rep⟩ := ih later
      exact ⟨event, .tail _ atEvent, rep⟩

/-- Run the production interpreter against any transport with observable
history. Each successful primitive records its own event. A send that raises
can already have delivered its line. A failed receive supplies no input. -/
theorem Program.run_prefix {ε σ α : Type} (represents : Event → α → Prop)
    (history : σ → List α) (send : Output → EStateM ε σ Unit) (receive : EStateM ε σ Input)
    (sendSpec : ∀ o w, match send o w with
      | .ok _ w' => ∃ obs, represents (.sent o) obs ∧ history w' = history w ++ [obs]
      | .error _ w' => history w' = history w ∨
          ∃ obs, represents (.sent o) obs ∧ history w' = history w ++ [obs])
    (receiveSpec : ∀ w, match receive w with
      | .ok input w' => ∃ obs, represents (.received input) obs ∧ history w' = history w ++ [obs]
      | .error _ w' => history w' = history w)
    (p : Program) (w : σ) :
    ∃ events observations, history (endState (p.run send receive w)) = history w ++ observations ∧
      Prefix p events ∧ Recording represents events observations := by
  induction p generalizing w with
  | stop => exact ⟨[], [], by simp [Program.run, pure, EStateM.pure, endState], .nil, .nil⟩
  | send o next ih =>
    have spec := sendSpec o w
    cases h : send o w with
    | error e w' =>
      rw [h] at spec
      rcases spec with noWrite | ⟨obs, rep, wrote⟩
      · exact ⟨[], [], by simpa [Program.run, bind, EStateM.bind, h, endState] using noWrite,
          .nil, .nil⟩
      · exact ⟨_, [obs], by simpa [Program.run, bind, EStateM.bind, h, endState] using wrote,
          .send .nil, .cons rep .nil⟩
    | ok u w' =>
      obtain ⟨events, observations, trace, pre, recording⟩ := ih w'
      rw [h] at spec
      obtain ⟨obs, rep, wrote⟩ := spec
      exact ⟨_, obs :: observations, by simpa [Program.run, bind, EStateM.bind, h, wrote] using trace,
        .send pre, .cons rep recording⟩
  | receive next ih =>
    have spec := receiveSpec w
    cases h : receive w with
    | error e w' =>
      rw [h] at spec
      exact ⟨[], [], by simpa [Program.run, bind, EStateM.bind, h, endState] using spec, .nil, .nil⟩
    | ok input w' =>
      obtain ⟨events, observations, trace, pre, recording⟩ := ih input w'
      rw [h] at spec
      obtain ⟨obs, rep, read⟩ := spec
      exact ⟨_, obs :: observations, by simpa [Program.run, bind, EStateM.bind, h, read] using trace,
        .receive pre, .cons rep recording⟩

def Completed (program : Program) (events : List Event) : Prop :=
  Prefix program events ∧ Event.sent .allStepsDone ∈ events

private theorem completed_send (output : Output) (h : output ≠ .allStepsDone) :
    Completed (.send output next) events ↔
      ∃ tail, events = .sent output :: tail ∧ Completed next tail := by
  constructor
  · rintro ⟨pre, done⟩
    cases pre with
    | nil => cases done
    | send p =>
      exact ⟨_, rfl, p, (List.mem_cons.mp done).resolve_left (fun eq => h (Event.sent.inj eq).symm)⟩
  · rintro ⟨tail, rfl, pre, done⟩
    exact ⟨.send pre, List.mem_cons_of_mem _ done⟩

private theorem completed_receive :
    Completed (.receive next) events ↔
      ∃ input tail, events = .received input :: tail ∧ Completed (next input) tail := by
  constructor
  · rintro ⟨pre, done⟩
    cases pre with
    | nil => cases done
    | receive p => exact ⟨_, _, rfl, p, (List.mem_cons.mp done).resolve_left (by simp)⟩
  · rintro ⟨_, _, rfl, pre, done⟩
    exact ⟨.receive pre, List.mem_cons_of_mem _ done⟩

private theorem not_completed_stop : ¬ Completed (.stop s) events := by
  rintro ⟨pre, done⟩
  cases pre
  cases done

private theorem completed_finish :
    Completed (.send .allStepsDone (.stop s)) events ↔ events = [.sent .allStepsDone] := by
  constructor
  · rintro ⟨pre, done⟩
    cases pre with
    | nil => cases done
    | send tail => cases tail; rfl
  · rintro rfl
    exact ⟨.send .nil, by simp⟩

private theorem prompt_ne_done (st : Step) : prompt st ≠ .allStepsDone := by
  unfold prompt
  split <;> simp

/-- The wire contract for a prompt, indexed within its own trace. -/
def PromptFor (st : Step) (output : Output) : Prop :=
  match st.idx with
  | 0 => output = .initialState st.act st.vars
  | _ + 1 => output = .nextStep st.act st.params

theorem promptFor_iff (st : Step) (output : Output) :
    PromptFor st output ↔ output = prompt st := by
  cases idx : st.idx <;> simp [PromptFor, prompt, idx]

/-- The independent success specification pairs each planned step with one
decoded report and one acknowledgement, ending in exactly one completion. -/
inductive Accepted : List Step → List Event → Prop where
  | done : Accepted [] [.sent .allStepsDone]
  | step (request : PromptFor st output) (matchReport : diffState st.vars report = .statesMatch)
      (rest : Accepted steps tail) :
      Accepted (st :: steps) (.sent output :: .received (.ok report) :: .sent .stepOk :: tail)

private theorem accepted_cons :
    Accepted (st :: steps) events ↔ ∃ report tail,
      events = .sent (prompt st) :: .received (.ok report) :: .sent .stepOk :: tail ∧
      diffState st.vars report = .statesMatch ∧ Accepted steps tail := by
  constructor
  · intro h
    cases h with
    | step request matched rest =>
      obtain rfl := (promptFor_iff _ _).mp request
      exact ⟨_, _, rfl, matched, rest⟩
  · rintro ⟨_, _, rfl, matched, rest⟩
    exact .step ((promptFor_iff _ _).mpr rfl) matched rest

private theorem accepted_nil : Accepted [] events ↔ events = [.sent .allStepsDone] := by
  constructor
  · intro h; cases h; rfl
  · rintro rfl; exact .done

/-- One exchange in the specification. A malformed input preserves the
stepping phase. A mismatch returns the exact diff payload and ends replay. -/
private def specifyRound (s : Session .stepping) (st : Step) (onMatch : Unit → Program) :
    Program :=
  .send (prompt st) (.receive fun input =>
    match input with
    | .error message => .send (.protocolError message) (.stop ⟨.stepping, s⟩)
    | .ok report =>
      match diffState st.vars report with
      | .statesMatch => .send .stepOk (onMatch ())
      | .stateMismatch e a hints => .send (.mismatch e a hints) (.stop ⟨.done, ⟨s.flow⟩⟩))

/-- Reference behavior on the steps of an admitted bundle, including its
terminal reply. The empty suffix is reached after the last matching report. -/
def specification (s : Session .stepping) : List Step → Program
  | [] => .send .allStepsDone (.stop ⟨.done, ⟨s.flow⟩⟩)
  | st :: rest => specifyRound s st (fun _ => specification s rest)

private theorem round_stepping (st : Step) (s : Session .stepping)
    (last : Bool) (next : Control → Program) :
    round st last ⟨.stepping, s⟩ next = specifyRound s st (fun _ =>
      next (if last then ⟨.done, ⟨s.flow⟩⟩ else ⟨.stepping, s⟩)) := by
  unfold round specifyRound
  congr 1
  apply congrArg Program.receive
  funext input
  cases input with
  | error => rfl
  | ok report => cases h : diffState st.vars report <;> cases last <;> simp [h, _root_.step]

private theorem play_eq_specification (c : Cursor) (s : Session .stepping) :
    play c ⟨.stepping, s⟩ = specification s c.remaining := by
  rw [play, advance_remaining]
  split
  next h => simp [h, remaining, round_stepping, specification]
  next tail h => simp [h, remaining, round_stepping, specification, play_eq_specification tail s]
termination_by c.remaining.length
decreasing_by
  have eq := advance_remaining c
  simp_all [remaining]

/-- Equality of interaction programs covers every report, malformed read,
mismatch and interruption point, including the final phase and reply payloads. -/
theorem session_eq_specification (traces : List ItfTrace) (s : Session .stepping)
    (nonempty : traces.flatMap traceSteps ≠ []) :
    session traces ⟨.stepping, s⟩ = .send .validated (specification s (traces.flatMap traceSteps)) := by
  unfold session
  rw [← first_remaining] at nonempty ⊢
  cases h : first traces with
  | none => exact (nonempty (by rw [h]; rfl)).elim
  | some c => simp [remaining, play_eq_specification]

private theorem specification_completed (s : Session .stepping) (steps : List Step)
    (events : List Event) : Completed (specification s steps) events ↔ Accepted steps events := by
  induction steps generalizing events with
  | nil => rw [specification, completed_finish, accepted_nil]
  | cons st rest ih =>
    rw [specification, specifyRound, completed_send _ (prompt_ne_done st), accepted_cons]
    constructor
    · rintro ⟨_, rfl, read⟩
      obtain ⟨input, _, rfl, result⟩ := completed_receive.mp read
      cases input with
      | error msg =>
        obtain ⟨_, _, stop⟩ := (completed_send _ (by simp)).mp result
        exact (not_completed_stop stop).elim
      | ok report =>
        cases h : diffState st.vars report with
        | stateMismatch e a hints =>
          simp only [h] at result
          obtain ⟨_, _, stop⟩ := (completed_send _ (by simp)).mp result
          exact (not_completed_stop stop).elim
        | statesMatch =>
          simp only [h] at result
          obtain ⟨_, rfl, tail⟩ := (completed_send _ (by simp)).mp result
          exact ⟨report, _, rfl, h, (ih _).mp tail⟩
    · rintro ⟨report, tail, rfl, matched, accepted⟩
      refine ⟨_, rfl, completed_receive.mpr ⟨.ok report, _, rfl, ?_⟩⟩
      simp only [matched]
      exact (completed_send _ (by simp)).mpr ⟨_, rfl, (ih _).mpr accepted⟩

/-- For any observable prefix of an admitted synchronous replay, seeing
completion is equivalent to the exact successful transcript of the entire
bundle in trace order. Even a prefix ending in a transport failure is covered. -/
theorem session_completed_iff (traces : List ItfTrace) (s : Session .stepping)
    (events : List Event) :
    Completed (session traces ⟨.stepping, s⟩) events ↔
      traces.flatMap traceSteps ≠ [] ∧
      ∃ body, events = .sent .validated :: body ∧ Accepted (traces.flatMap traceSteps) body := by
  unfold session
  rw [completed_send _ (by simp), ← first_remaining]
  cases h : first traces with
  | none => simp [remaining, not_completed_stop]
  | some c =>
    have nonempty : c.remaining ≠ [] := by rw [advance_remaining]; simp
    simp [remaining, nonempty, play_eq_specification, specification_completed]

/-- The actual reports read by this session in reception order. -/
def reports : List Event → List ValueMap
  | [] => []
  | .received (.ok report) :: rest => report :: reports rest
  | _ :: rest => reports rest

private theorem Accepted.report_count (accepted : Accepted steps events) :
    (reports events).length = steps.length := by
  induction accepted with
  | done => rfl
  | step request matched rest ih => simp only [reports, List.length_cons, ih]

private theorem Accepted.report_at (accepted : Accepted steps events) (i : Nat)
    (atStep : steps[i]? = some st) :
    ∃ report, (reports events)[i]? = some report ∧ diffState st.vars report = .statesMatch := by
  induction accepted generalizing i with
  | done => simp at atStep
  | step request matched rest ih =>
    cases i with
    | zero =>
      simp only [List.getElem?_cons_zero, Option.some.injEq] at atStep
      subst st
      exact ⟨_, rfl, matched⟩
    | succ i => exact ih i atStep

/-- Lift an accepted transcript to snapshots supplied independently by the
application. Index zero is the first initialization. -/
theorem Accepted.faithful_states {AppState : Type u} (accepted : Accepted steps events)
    (observableState : AppState → ValueMap) (snapshot : Nat → AppState)
    (wellFormed : ∀ (i : Nat) report, (reports events)[i]? = some report →
      NodupKeys (filterMeta report) ∧ ∀ p ∈ filterMeta report, WfValue p.2)
    (faithful : ∀ (i : Nat) report, (reports events)[i]? = some report →
      stateEq (filterMeta report) (filterMeta (observableState (snapshot i)))) :
    (reports events).length = steps.length ∧
    ∀ (i : Nat) st, steps[i]? = some st →
      stateEq (filterMeta st.vars) (filterMeta (observableState (snapshot i))) := by
  refine ⟨accepted.report_count, ?_⟩
  intro i st atStep
  obtain ⟨report, atReport, matched⟩ := accepted.report_at i atStep
  obtain ⟨keys, values⟩ := wellFormed i report atReport
  exact (diffState_sound keys values matched).trans (faithful i report atReport)

/-- At the wire boundary, an accepted body can be related directly to the
decoded ITF states, including their original observable variable bindings. -/
theorem Accepted.faithful_trace_states {AppState : Type u} (traces : List ItfTrace)
    (accepted : Accepted (traces.flatMap traceSteps) events)
    (observableState : AppState → ValueMap) (snapshot : Nat → AppState)
    (wellFormed : ∀ (i : Nat) report, (reports events)[i]? = some report →
      NodupKeys (filterMeta report) ∧ ∀ p ∈ filterMeta report, WfValue p.2)
    (faithful : ∀ (i : Nat) report, (reports events)[i]? = some report →
      stateEq (filterMeta report) (filterMeta (observableState (snapshot i)))) :
    (reports events).length = (traces.flatMap ItfTrace.traceStates).length ∧
    ∀ (i : Nat) state, (traces.flatMap ItfTrace.traceStates)[i]? = some state →
      stateEq (filterMeta state.stateVars) (filterMeta (observableState (snapshot i))) := by
  obtain ⟨count, agrees⟩ := accepted.faithful_states observableState snapshot wellFormed faithful
  have projections := traceSteps_bundle_observables traces
  refine ⟨count.trans (by simpa using congrArg List.length projections), ?_⟩
  intro i state atState
  have atIndex := congrArg (fun (xs : List ValueMap) => xs[i]?) projections
  simp only [List.getElem?_map, atState, Option.map_some] at atIndex
  cases h : (traces.flatMap traceSteps)[i]? with
  | none => simp [h] at atIndex
  | some st =>
    simp only [h, Option.map_some, Option.some.injEq] at atIndex
    rw [← atIndex]
    exact agrees i st h

/-- A completed replay has one report per step. With a faithful adapter,
the expected state at each index agrees with the observable application
snapshot at that same index. Snapshot zero is the first initialization. -/
theorem session_completed_faithful {AppState : Type u}
    (observableState : AppState → ValueMap) (snapshot : Nat → AppState)
    (traces : List ItfTrace) (s : Session .stepping) (events : List Event)
    (completed : Completed (session traces ⟨.stepping, s⟩) events)
    (wellFormed : ∀ (i : Nat) report, (reports events)[i]? = some report →
      NodupKeys (filterMeta report) ∧ ∀ p ∈ filterMeta report, WfValue p.2)
    (faithful : ∀ (i : Nat) report, (reports events)[i]? = some report →
      stateEq (filterMeta report) (filterMeta (observableState (snapshot i)))) :
    (reports events).length = (traces.flatMap traceSteps).length ∧
    ∀ (i : Nat) st, (traces.flatMap traceSteps)[i]? = some st →
      stateEq (filterMeta st.vars) (filterMeta (observableState (snapshot i))) := by
  obtain ⟨_, body, rfl, accepted⟩ := (session_completed_iff traces s events).mp completed
  exact accepted.faithful_states observableState snapshot wellFormed faithful

end Core.Replay
