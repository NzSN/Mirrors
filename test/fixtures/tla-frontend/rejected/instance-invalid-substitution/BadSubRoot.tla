---- MODULE BadSubRoot ----

CONSTANT RootLimit
VARIABLE rootState

I == INSTANCE BadSubChild WITH ChildLimit <- RootLimit, missingSymbol <- rootState

RootOp == I!ChildOp

====
