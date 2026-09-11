---- MODULE AcceptTemporal ----

EXTENDS Integers

VARIABLE x

Init == x = 0
Next == x' = x + 1
Fair == WF_x(Next) /\ SF_x(Next)
Always == [](x >= 0)
Eventually == <>(x = 3)
Leadsto == (x = 0) ~> (x = 3)
Both == []<>(x = 0) /\ <>[](x >= 0)
Spec == Init /\ [][Next]_x /\ Fair

====
