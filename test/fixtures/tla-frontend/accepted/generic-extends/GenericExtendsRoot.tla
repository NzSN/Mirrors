---- MODULE GenericExtendsRoot ----

EXTENDS GenericExtendsBase

VARIABLES rootA, rootB

RootNext ==
    /\ baseA' = baseA + BaseLimit
    /\ rootA' = rootA + baseB
    /\ UNCHANGED <<baseB, baseC, rootB>>

====
