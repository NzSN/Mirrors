import Lean

namespace Ffi

/-- Fresh, initialized storage for a native output parameter. A closed pure
array expression may be shared by the native compiler, so construct the
buffer inside an effectful factory before lending it to a C shim. -/
@[noinline] def freshBuffer (size : Nat) : BaseIO ByteArray := do
  let mut bytes := ByteArray.emptyWithCapacity size
  for _ in [0:size] do
    bytes := bytes.push 0
  return bytes

end Ffi
