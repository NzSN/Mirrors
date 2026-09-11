---- MODULE AcceptAssumptions ----

EXTENDS Integers

CONSTANT N

ASSUME N \in Int
ASSUMPTION N + 0 = N
AXIOM N * 1 = N

====
