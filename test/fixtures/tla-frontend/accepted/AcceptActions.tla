---- MODULE AcceptActions ----

EXTENDS Integers

VARIABLE x
VARIABLE y

Init == x = 0 /\ y = 0
Increment == x' = x + 1 /\ UNCHANGED y
Stutter == UNCHANGED <<x, y>>
Enabled == ENABLED Increment
Angle == <<Increment>>_<<x, y>>
Step == Increment \/ Stutter
Spec == Init /\ [][Step]_<<x, y>>

====
