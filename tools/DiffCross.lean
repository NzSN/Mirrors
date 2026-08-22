import Core.Diff
import Codec.Json
import Lean.Data.Json

/-!
# Differential test: Lean diff engine vs Haskell (design doc section 8, Phase 1 exit)

Reads test/fixtures/diff_cases.jsonl — QuickCheck-generated pairs of
state valuations with the *Haskell* Engine.Core.diffState verdict
recorded by tools/fixtures/GenDiffCases.hs (deterministic seed, pinned
ModelMirrors commit) — replays each pair through the Lean
Core.Diff.diffState, and compares:

* the match/mismatch verdict, and
* the produced DiffHint list, rendered to JSON exactly like the
  Haskell ToJSON DiffHint instance and compared as *ordered lists*:
  the Lean engine reproduces the Haskell sorted-key interleave
  (Core.Diff.sortHintsByKey), so the wire bytes agree exactly.

Exit 0 = no divergence between the two implementations.
-/



/-- Render a path segment exactly like the Haskell wire format. -/
def jPathSeg : _root_.PathSeg → Lean.Json
  | .field f => Lean.Json.mkObj [("field", Lean.Json.str f)]
  | .index i => Lean.Json.mkObj [("index", Lean.Json.num i)]

/-- Render a hint exactly like the Haskell ToJSON DiffHint instance. -/
def jHint : _root_.DiffHint → Lean.Json
  | .hValueMismatch p e a =>
      Lean.Json.mkObj [("kind", "value_mismatch"), ("path", jPath p),
        ("expected", Codec.encValue e), ("actual", Codec.encValue a)]
  | .hMissing p e =>
      Lean.Json.mkObj [("kind", "missing"), ("path", jPath p),
        ("expected", Codec.encValue e)]
  | .hExtra p a =>
      Lean.Json.mkObj [("kind", "extra"), ("path", jPath p),
        ("actual", Codec.encValue a)]
  | .hMissingElem p e =>
      Lean.Json.mkObj [("kind", "missing_elem"), ("path", jPath p),
        ("expected", Codec.encValue e)]
  | .hExtraElem p a =>
      Lean.Json.mkObj [("kind", "extra_elem"), ("path", jPath p),
        ("actual", Codec.encValue a)]
  | .hTypeMismatch p e a =>
      Lean.Json.mkObj [("kind", "type_mismatch"), ("path", jPath p),
        ("expected", Codec.encValue e), ("actual", Codec.encValue a)]
  | .hTruncated p =>
      Lean.Json.mkObj [("kind", "truncated"), ("path", jPath p)]
where
  jPath p := Lean.Json.arr (List.map jPathSeg p |>.toArray)

/-- Decode a JSON state object into a ValueMap (the codec decodes plain
objects as vrecord). -/
def stateMapOf (j : Lean.Json) : Except String ValueMap :=
  match Codec.decodeValue j with
  | .error e => .error (reprStr e)
  | .ok (.vrecord m) => .ok m
  | .ok _ => .error "state object did not decode to vrecord"

/-- Canonical compressed string form, for ordered comparison. -/
def canonHint (h : _root_.DiffHint) : String := Lean.Json.compress (jHint h)

def objVal (j : Lean.Json) (k : String) : Option Lean.Json :=
  (j.getObjVal? k).toOption

def strVal (j : Lean.Json) : String :=
  match j with
  | .str s => s
  | _ => "?"


def checkCase (idx : Nat) (line : String) : IO (Option String) := do
  match Lean.Json.parse line with
  | .error e => return some s!"case {idx}: JSON parse error: {e}"
  | .ok j =>
    let some expJson := objVal j "expected" | return some s!"case {idx}: malformed case record"
    let some actJson := objVal j "actual" | return some s!"case {idx}: malformed case record"
    let some hsk := objVal j "haskell" | return some s!"case {idx}: malformed case record"
    let some hTag := objVal hsk "tag" | return some s!"case {idx}: malformed case record"
      match stateMapOf expJson, stateMapOf actJson with
      | .error e, _ | _, .error e => return some s!"case {idx}: state decode: {e}"
      | .ok em, .ok am =>
        let leanDiff := diffState em am
        let leanTag : String := match leanDiff with
          | .statesMatch => "match"
          | .stateMismatch _ _ _ => "mismatch"
        if leanTag != strVal hTag then
          return some s!"case {idx}: verdict divergence: lean={leanTag} haskell={strVal hTag}"
        if strVal hTag == "mismatch" then
          match objVal hsk "hints" with
          | .none => return some s!"case {idx}: missing haskell hints"
          | .some (.arr hsArr) =>
            let hs := hsArr.toList.map Lean.Json.compress
            let ls := (diffHints leanDiff).map canonHint
            if hs != ls then
              let onlyLean := ls.filter (fun s => !(s ∈ hs)) |>.take 3
              let onlyHs := hs.filter (fun s => !(s ∈ ls)) |>.take 3
              return some s!"case {idx}: hint divergence ({ls.length} lean vs {hs.length} haskell) lean-only: {onlyLean} haskell-only: {onlyHs}"
            return none
          | _ => return some s!"case {idx}: haskell hints not an array"
        else
          let leanHints := diffHints leanDiff
          if !leanHints.isEmpty then
            return some s!"case {idx}: lean produced hints where Haskell matched"
          return none

def main : IO UInt32 := do
  -- Optional corpus override via the DIFF_CROSS_CORPUS environment
  -- variable (used for the larger regeneration sweeps); default is the
  -- checked-in 500-case corpus.
  let mcorpus ← IO.getEnv "DIFF_CROSS_CORPUS"
  let corpus :=
    match mcorpus.getD "" with
    | "" => "test/fixtures/diff_cases.jsonl"
    | p => p
  let content ← IO.FS.readFile corpus
  let mut fails : List String := []
  let mut idx := 0
  let mut n := 0
  for line in content.splitOn "\n" do
    if !line.isEmpty then
      idx := idx + 1
      n := n + 1
      match ← checkCase idx line with
      | some err => fails := err :: fails
      | none => pure ()
  match fails.reverse with
  | [] =>
    IO.println s!"DIFF ENGINE DIFFERENTIAL ({corpus}): {n}/{n} cases agree with Haskell"
    return 0
  | fs =>
    for f in fs.take 20 do IO.println ("FAIL " ++ f)
    IO.println s!"DIFF ENGINE DIFFERENTIAL: {n - fs.length}/{n} cases agree with Haskell"
    return 1
