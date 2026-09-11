---- MODULE RejectPrecedenceChain ----

CONSTANT A, B, C

ImplicationChain == A => B => C
EquivalenceChain == A <=> B <=> C

====
