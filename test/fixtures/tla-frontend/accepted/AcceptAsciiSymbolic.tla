---- MODULE AcceptAsciiSymbolic ----

EXTENDS Integers

CONSTANT S, T

And == S /\ T
Or == S \/ T
Not == ~ S
Iff == S <=> T
Member == S \in {S, T}
Subset == {S} \subseteq {S, T}
Union == {S} \union {T}
Intersect == {S} \intersect {T}
NotEqual == S # T
Leq == 1 <= 2

====
