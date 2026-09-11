---- MODULE AcceptFunctions ----

EXTENDS Integers

S == {1, 2, 3}
F == [u \in S |-> u * u]
G == [S -> S]
D == DOMAIN F
V == F[1]
R == [key |-> 1, other |-> 2]
K == R.key
Updated == [F EXCEPT ![2] = 9]
Nested == [R EXCEPT !.key = @ + 1, !.other = 0]

====
