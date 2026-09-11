---- MODULE AcceptLevels ----

EXTENDS Integers

CONSTANT N
VARIABLE x

ConstantOp == N + 1
StateOp == x + N
ActionOp == x' = x + 1
TemporalOp == [][ActionOp]_x
Spec == x = 0 /\ [][ActionOp]_x

====
