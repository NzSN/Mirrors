---- MODULE AcceptQuantifiers ----

EXTENDS Integers

S == {1, 2, 3}

AllPositive == \A u \in S : u > 0
SomeLarge == \E u \in S : u > 2
Nested == \A u \in S : \E v \in S : u + v > 1

====
