---- MODULE AcceptPrecedenceJunctions ----

CONSTANT A, B, C, D

ConjunctionChain == A /\ B /\ C
DisjunctionChain == A \/ B \/ C
LeftGroupedConjunction == (A /\ B) \/ C
RightGroupedDisjunction == A /\ (B \/ C)
LeftGroupedDisjunction == (A \/ B) /\ C
RightGroupedConjunction == A \/ (B /\ C)
AsciiConjunctionChain == A /\ B \land C
AsciiDisjunctionChain == A \/ B \lor C

ListBody == /\ A
            /\ B
            \/ C

====
