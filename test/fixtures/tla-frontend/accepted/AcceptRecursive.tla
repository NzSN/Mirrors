---- MODULE AcceptRecursive ----

EXTENDS Integers

RECURSIVE Fact(_)
Fact(n) == IF n = 0 THEN 1 ELSE n * Fact(n - 1)

RECURSIVE SumTo(_, _)
SumTo(n, acc) == IF n = 0 THEN acc ELSE SumTo(n - 1, acc + n)

====
