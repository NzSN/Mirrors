---- MODULE InstanceStateRoot ----

VARIABLE parentState

I == INSTANCE InstanceStateChild WITH childState <- parentState

RootOp == I!ChildOp

====
