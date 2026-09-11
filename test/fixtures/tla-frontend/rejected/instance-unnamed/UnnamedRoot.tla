---- MODULE UnnamedRoot ----

VARIABLE rootState

INSTANCE UnnamedChild WITH childState <- rootState

RootOp == rootState' = rootState

====
