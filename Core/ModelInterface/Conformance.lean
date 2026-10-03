import Core.ModelInterface.Preflight

/-!
# Executable model-interface language judgments

These decisions share the compiler's structural types and preflight's input
checks. Type-indexed equality rejects ill-typed values before using the proved
extensional `Core.valEq`; it does not change raw protocol equality.
-/

namespace Core.ModelInterface.Conformance

def typeWellFormed (type : ModelType) : Bool :=
  type.wellFormed && modelTypeDepth type ≤ maxStructuralTypeDepthV1 &&
    modelTypeNodeCount type ≤ maxNormalizedTypeNodesV1 &&
    (modelTypeWireNames type).all (fun name => name.toUTF8.size ≤ maxStableNameBytesV1)

mutual
  private def portableShape : ModelType → Bool
    | .int | .bool | .str | .null => true
    | .set element | .seq element => portableShape element
    | .tuple elements => portableShapes elements
    | .record fields => portableFields fields
    | .map .str value => portableShape value
    | .variant cases => portableCases cases
    | _ => false
  private def portableShapes : List ModelType → Bool
    | [] => true
    | type :: rest => portableShape type && portableShapes rest
  private def portableFields : List ModelField → Bool
    | [] => true
    | field :: rest => portableShape field.type && portableFields rest
  private def portableCases : List VariantCase → Bool
    | [] => true
    | item :: rest => portableShape item.payload && portableCases rest
end

/-- The common v1 generated type baseline, including structural well-formedness.
Target-specific native identifier restrictions are checked by each emitter. -/
def portableType (type : ModelType) : Bool := typeWellFormed type && portableShape type

def valueWellTyped (type : ModelType) (value : Value) : Bool :=
  typeWellFormed type && valueHasType value type

def equivalent (type : ModelType) (left right : Value) : Bool :=
  valueWellTyped type left && valueWellTyped type right && valEq left right

/-- A path judgment never accepts an ill-formed root type. -/
def pathType (root : ModelType) (path : List PathSegment) : Except String ModelType := do
  if !typeWellFormed root then throw "ill-formed root type"
  if path.length > maxPathSegmentsV1 then throw "path exceeds the versioned segment bound"
  match resolvePathType root path with
  | .ok type => pure type
  | .error failure => throw failure.reason

/-- Dynamic bounds and variant tags are checked even after static path typing. -/
def evaluatePath (root : ModelType) (value : Value) (path : List PathSegment) :
    Except String Value := do
  let expected ← pathType root path
  if !valueWellTyped root value then throw "root value does not match its type"
  let projected ← projectValue value path
  if !valueWellTyped expected projected then throw "projected value does not match its type"
  pure projected

theorem equivalent_implies_left_typed {type left right}
    (h : equivalent type left right = true) : valueWellTyped type left = true := by
  simp only [equivalent, Bool.and_eq_true] at h
  exact h.1.1

theorem equivalent_implies_right_typed {type left right}
    (h : equivalent type left right = true) : valueWellTyped type right = true := by
  simp only [equivalent, Bool.and_eq_true] at h
  exact h.1.2

theorem equivalent_refl {type value}
    (h : valueWellTyped type value = true) : equivalent type value value = true := by
  simp [equivalent, h, valEq_refl]

theorem equivalent_symm {type left right}
    (h : equivalent type left right = true) : equivalent type right left = true := by
  simp only [equivalent, Bool.and_eq_true] at h ⊢
  exact ⟨⟨h.1.2, h.1.1⟩, valEq_symm left right h.2⟩

theorem equivalent_trans {type left middle right}
    (first : equivalent type left middle = true)
    (second : equivalent type middle right = true) : equivalent type left right = true := by
  simp only [equivalent, Bool.and_eq_true] at first second ⊢
  exact ⟨⟨first.1.1, second.1.2⟩, valEq_trans left middle right first.2 second.2⟩

end Core.ModelInterface.Conformance
