---- MODULE BadSubChild ----

CONSTANT ChildLimit
VARIABLE childState

ChildOp == childState' = ChildLimit

====
