---- MODULE AcceptAnnotations ----

EXTENDS Integers

CONSTANT N

\* @type: Int;
TypedConstant == N + 1

\* @type: () => Bool;
Predicate == TypedConstant > 0

====
