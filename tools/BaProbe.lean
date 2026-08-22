import Lean
#check @ByteArray.mkEmpty
#check @ByteArray.push
#check @ByteArray.append
#check @ByteArray.extract
#check @ByteArray.get!
#check @ByteArray.size
#check @ByteArray.copySlice
#check @String.fromUTF8?
#check @String.toUTF8
#check @Nat.fromHexString?
#check @USize.size
example : IO ByteArray := do
  let b <- ByteArray.mkEmpty 10
  let b := b.push 65
  return b
