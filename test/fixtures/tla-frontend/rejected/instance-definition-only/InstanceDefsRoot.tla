---- MODULE InstanceDefsRoot ----

EXTENDS Integers

CONSTANT RootLimit

I == INSTANCE InstanceDefsChild WITH ChildLimit <- RootLimit

RootOp == I!ChildOp

====
