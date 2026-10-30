---- MODULE ControlledWitnessCase ----
EXTENDS ControlledMutexFifo
ConstInit ==
  /\ WitnessActors = <<"consumer","producer","producer","producer","producer","producer","consumer","producer","consumer","consumer","consumer","consumer","consumer","producer">>
  /\ WitnessOperations = <<"start","start","lock","checkpoint","unlock","send","receive","send","receive","lock","checkpoint","unlock","$done","$done">>
  /\ WitnessResources = <<"","","mutex","critical","mutex","queue","queue","queue","queue","mutex","critical","mutex","","">>
  /\ WitnessValues = <<0,0,0,0,0,10,10,20,20,0,0,0,0,0>>
  /\ WitnessEnabled = <<{"consumer","producer"},{"producer"},{"producer"},{"producer"},{"producer"},{"producer"},{"consumer"},{"producer"},{"consumer","producer"},{"consumer","producer"},{"consumer","producer"},{"consumer","producer"},{"consumer","producer"},{"producer"}>>
  /\ WitnessCounts = <<0,0,0,2,2,2,2,2,2,2,3,3,3,3,3>>
  /\ WitnessReceived = <<<<>>,<<>>,<<>>,<<>>,<<>>,<<>>,<<>>,<<10>>,<<10>>,<<10,20>>,<<10,20>>,<<10,20>>,<<10,20>>,<<10,20>>,<<10,20>>>>
====
