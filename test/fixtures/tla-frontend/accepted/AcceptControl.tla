---- MODULE AcceptControl ----

EXTENDS Integers

CONSTANT N

Sign == IF N > 0 THEN 1 ELSE 0
Classify == CASE N > 10 -> "large" [] N > 0 -> "small" [] OTHER -> "zero"
Local == LET doubled == 2 * N IN doubled + 1
Chosen == CHOOSE k \in {0, 1} : k = 0

====
