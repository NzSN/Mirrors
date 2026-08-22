import Lean
#check @Json.num
example : Json := (3 : Json)
#check @Json.ofInt
#check @Json.ofNat
example : Json := Json.num ⟨5, 0⟩
