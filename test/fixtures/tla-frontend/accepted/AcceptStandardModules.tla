---- MODULE AcceptStandardModules ----

EXTENDS Integers, Naturals, Sequences, FiniteSets, TLC

Positive == {n \in Nat : n > 0}
Sequence == Append(<<1>>, 2)
Size == Cardinality({1, 2})
Sum == 1 + 2

====
