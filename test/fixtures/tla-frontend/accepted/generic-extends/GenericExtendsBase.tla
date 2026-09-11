---- MODULE GenericExtendsBase ----

EXTENDS Integers

CONSTANT BaseLimit

VARIABLES baseA, baseB, baseC

BaseNext ==
    /\ baseA' = baseA + 1
    /\ UNCHANGED <<baseB, baseC>>

====
