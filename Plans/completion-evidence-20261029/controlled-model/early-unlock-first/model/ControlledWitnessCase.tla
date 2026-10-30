---- MODULE ControlledWitnessCase ----
EXTENDS ControlledMutexFifo
ConstInit ==
  /\ WitnessActors = <<"consumer","producer","producer","producer","producer","producer","consumer","producer","consumer","consumer","consumer","consumer","consumer","producer">>
  /\ WitnessOperations = <<"start","start","lock","unlock","checkpoint","send","receive","send","receive","lock","checkpoint","unlock","$done","$done">>
  /\ WitnessResources = <<"","","mutex","mutex","critical","queue","queue","queue","queue","mutex","critical","mutex","","">>
  /\ WitnessValues = <<0,0,0,0,0,10,10,20,20,0,0,0,0,0>>
  /\ WitnessEnabled = <<{"consumer","producer"},{"producer"},{"producer"},{"producer"},{"producer"},{"producer"},{"consumer"},{"producer"},{"consumer","producer"},{"consumer","producer"},{"consumer","producer"},{"consumer","producer"},{"consumer","producer"},{"producer"}>>
  /\ WitnessCounts = <<0,0,0,1,1,1,1,1,1,1,2,2,2,2,2>>
  /\ WitnessReceived = <<<<>>,<<>>,<<>>,<<>>,<<>>,<<>>,<<>>,<<10>>,<<10>>,<<10,20>>,<<10,20>>,<<10,20>>,<<10,20>>,<<10,20>>,<<10,20>>>>
====
