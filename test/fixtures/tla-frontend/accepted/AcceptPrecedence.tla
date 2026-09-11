---- MODULE AcceptPrecedence ----

EXTENDS Integers

CONSTANT A, B, C

Arithmetic == A + B * C
Comparison == A + B < C * 2
Membership == A \in {B} /\ C = C
Implication == (A /\ B) => C
Disjunction == (A \/ B) => C
Negation == ~ A /\ B
Range == 1..C
Grouping == (A => B) => C

====
