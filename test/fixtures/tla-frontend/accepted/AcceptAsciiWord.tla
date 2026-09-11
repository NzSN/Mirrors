---- MODULE AcceptAsciiWord ----

EXTENDS Integers

CONSTANT S, T

And == S \land T
Or == S \lor T
Not == \lnot S
Iff == S \equiv T
Member == S \in {S, T}
Subset == {S} \subseteq {S, T}
Union == {S} \cup {T}
Intersect == {S} \cap {T}
Leq == 1 \leq 2

====
