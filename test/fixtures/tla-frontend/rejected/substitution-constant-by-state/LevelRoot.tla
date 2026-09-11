---- MODULE LevelRoot ----

EXTENDS Integers

VARIABLE rootState

I == INSTANCE LevelChild WITH ChildLimit <- rootState

RootOp == I!ChildOp

====
