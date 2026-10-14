/-! Pure admission and search ordering for finite, oracle-backed DPM catalogs. -/
namespace Core.Dpm

structure Step where
  actor : String
  checkpoint : String
  deriving Repr, BEq, DecidableEq, Inhabited

structure Chain where
  actor : String
  checkpoints : List String
  deriving Repr, BEq, DecidableEq

structure Candidate where
  id : String
  inputRank : Nat
  steps : List Step
  deriving Repr, BEq, DecidableEq

def projection (steps : List Step) (actor : String) : List String :=
  (steps.filter (fun s => s.actor == actor)).map (·.checkpoint)

def actors (candidate : Candidate) : List String :=
  (candidate.steps.map (·.actor)).eraseDups

def preemptions : List Step → Nat
  | [] | [_] => 0
  | first :: second :: rest =>
      (if first.actor != second.actor && first.checkpoint != "$done" then 1 else 0) +
        preemptions (second :: rest)

def cost (candidate : Candidate) : List Nat :=
  [(actors candidate).length, candidate.inputRank, preemptions candidate.steps,
    candidate.steps.length]

def lexLess : List Nat → List Nat → Bool
  | [], [] => false
  | [], _ :: _ => true
  | _ :: _, [] => false
  | a :: as, b :: bs => if a == b then lexLess as bs else a < b

def precedes (a b : Candidate) : Bool :=
  lexLess (cost a) (cost b) || (cost a == cost b && a.id < b.id)

def validIdentifier (value : String) : Bool :=
  !value.isEmpty && value.toUTF8.size ≤ 128 && value.toList.all fun c =>
    c.isAlphanum && c.toNat < 128 || c == '-' || c == '_' || c == '.' || c == '/'

def validate (chains : List Chain) (candidates : List Candidate)
    (baseline : String) : Except String Unit := do
  if chains.isEmpty || chains.length > 16 ||
      (chains.map (·.actor)).eraseDups.length != chains.length then
    throw "invalid or duplicate actor declarations"
  for chain in chains do
    if !validIdentifier chain.actor || chain.checkpoints.isEmpty ||
        chain.checkpoints.length > 256 || chain.checkpoints.getLast? != some "$done" ||
        (chain.checkpoints.filter (· == "$done")).length != 1 ||
        !chain.checkpoints.all (fun c => c == "$done" || validIdentifier c) then
      throw "actor chain must end in exactly one completion"
  if candidates.isEmpty || candidates.length > 4096 ||
      (candidates.map (·.id)).eraseDups.length != candidates.length ||
      !candidates.any (·.id == baseline) then
    throw "invalid catalog size, duplicate candidate or missing baseline"
  for candidate in candidates do
    if !validIdentifier candidate.id || candidate.inputRank > 1000000 ||
        candidate.steps.isEmpty || candidate.steps.length > 4096 then
      throw "candidate outside finite bounds"
    for actor in actors candidate do
      let some chain := chains.find? (·.actor == actor)
        | throw "candidate contains undeclared actor"
      if projection candidate.steps actor != chain.checkpoints then
        throw "candidate does not preserve complete actor-local chain"

def ordered (candidates : List Candidate) : List Candidate :=
  candidates.mergeSort precedes

/-- Removing other actors preserves a selected actor's chain exactly. -/
theorem projection_filter (steps : List Step) (selected : List String)
    (actor : String) (h : actor ∈ selected) :
    projection (steps.filter (fun s => selected.contains s.actor)) actor =
      projection steps actor := by
  have predicate : (fun s : Step => s.actor == actor && selected.contains s.actor) =
      (fun s : Step => s.actor == actor) := by
    funext step
    by_cases same : step.actor = actor
    · simp [same, h]
    · simp [same]
  simp only [projection, List.filter_filter, predicate]

end Core.Dpm
