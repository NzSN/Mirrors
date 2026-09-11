---- MODULE AcceptOperators ----

EXTENDS Integers

Double(v) == 2 * v

a \oplus b == a + b

a \prec b == a < b

Apply(F(_), v) == F(v)

Nullary == 42

====
