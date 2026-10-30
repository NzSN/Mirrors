---- MODULE ControlledWitnessCase ----
EXTENDS ControlledMutexFifo
ConstInit ==
  /\ WitnessActors = <<"producer","producer","producer","producer","producer","consumer","consumer","producer","producer","consumer","consumer","consumer","consumer","consumer">>
  /\ WitnessOperations = <<"start","lock","checkpoint","unlock","send","start","receive","send","$done","receive","lock","checkpoint","unlock","$done">>
  /\ WitnessResources = <<"","mutex","critical","mutex","queue","","queue","queue","","queue","mutex","critical","mutex","">>
  /\ WitnessValues = <<0,0,0,0,10,0,10,20,0,20,0,0,0,0>>
  /\ WitnessEnabled = <<{"consumer","producer"},{"consumer","producer"},{"consumer","producer"},{"consumer","producer"},{"consumer","producer"},{"consumer"},{"consumer"},{"producer"},{"consumer","producer"},{"consumer"},{"consumer"},{"consumer"},{"consumer"},{"consumer"}>>
  /\ WitnessCounts = <<0,0,1,1,1,1,1,1,1,1,1,2,2,2,2>>
  /\ WitnessReceived = <<<<>>,<<>>,<<>>,<<>>,<<>>,<<>>,<<>>,<<10>>,<<10>>,<<10>>,<<10,20>>,<<10,20>>,<<10,20>>,<<10,20>>,<<10,20>>>>
====
