---- MODULE AcceptTrivia ----

(* A block comment
   (* with a nested comment *)
   mentioning EXTENDS Phantom and INSTANCE Phantom *)

\* A line comment mentioning EXTENDS Phantom and "quoted INSTANCE"

EXTENDS Integers

VARIABLE x   \* trailing line comment

Init == x = 0
Next == x' = x + 1

(* trailing block comment *)
====
