---- MODULE AcceptComprehensions ----

EXTENDS Integers

S == {1, 2, 3}

Positives == {u \in S : u > 0}
Squares == {u * u : u \in S}
Pairs == {<<u, v>> : u \in S, v \in S}
Functions == [u \in S |-> {v \in S : v >= u}]

====
