---------------------- MODULE ControlledMutexFifo ----------------------
EXTENDS Integers, Sequences

CONSTANTS
  \* @type: Seq(Str);
  WitnessActors,
  \* @type: Seq(Str);
  WitnessOperations,
  \* @type: Seq(Str);
  WitnessResources,
  \* @type: Seq(Int);
  WitnessValues,
  \* @type: Seq(Set(Str));
  WitnessEnabled,
  \* @type: Seq(Int);
  WitnessCounts,
  \* @type: Seq(Seq(Int));
  WitnessReceived

VARIABLES
  \* @type: Int;
  index,
  \* @type: Int;
  producerPc,
  \* @type: Int;
  consumerPc,
  \* @type: Str;
  owner,
  \* @type: Seq(Int);
  queue,
  \* @type: Int;
  count,
  \* @type: Seq(Int);
  received,
  \* @type: Bool;
  valid

vars == <<index, producerPc, consumerPc, owner, queue, count, received, valid>>

Init == /\ index = 0 /\ producerPc = 0 /\ consumerPc = 0
        /\ owner = "" /\ queue = <<>> /\ count = 0 /\ received = <<>> /\ valid = TRUE

ProducerEnabled == CASE producerPc \in {0, 2, 6} -> TRUE
  [] producerPc = 1 -> owner = ""
  [] producerPc = 3 -> owner = "producer"
  [] producerPc \in {4, 5} -> Len(queue) < 1
  [] OTHER -> FALSE

ConsumerEnabled == CASE consumerPc \in {0, 4, 6} -> TRUE
  [] consumerPc \in {1, 2} -> Len(queue) > 0
  [] consumerPc = 3 -> owner = ""
  [] consumerPc = 5 -> owner = "consumer"
  [] OTHER -> FALSE

Enabled == (IF ProducerEnabled THEN {"producer"} ELSE {}) \cup
           (IF ConsumerEnabled THEN {"consumer"} ELSE {})

Apply(actor, operation, resource, value, nextProducer, nextConsumer,
      nextOwner, nextQueue, nextCount, nextReceived) ==
  /\ index' = index + 1
  /\ valid' = (valid /\ WitnessActors[index+1] = actor
      /\ WitnessOperations[index+1] = operation
      /\ WitnessResources[index+1] = resource /\ WitnessValues[index+1] = value)
  /\ producerPc' = nextProducer /\ consumerPc' = nextConsumer
  /\ owner' = nextOwner /\ queue' = nextQueue /\ count' = nextCount
  /\ received' = nextReceived

ProducerStep == CASE
  producerPc = 0 -> Apply("producer", "start", "", 0, 1, consumerPc, owner, queue, count, received)
  [] producerPc = 1 -> Apply("producer", "lock", "mutex", 0, 2, consumerPc, "producer", queue, count+1, received)
  [] producerPc = 2 -> Apply("producer", "checkpoint", "critical", 0, 3, consumerPc, owner, queue, count, received)
  [] producerPc = 3 -> Apply("producer", "unlock", "mutex", 0, 4, consumerPc, "", queue, count, received)
  [] producerPc = 4 -> Apply("producer", "send", "queue", 10, 5, consumerPc, owner, Append(queue, 10), count, received)
  [] producerPc = 5 -> Apply("producer", "send", "queue", 20, 6, consumerPc, owner, Append(queue, 20), count, received)
  [] OTHER -> Apply("producer", "$done", "", 0, 7, consumerPc, owner, queue, count, received)

ConsumerStep == CASE
  consumerPc = 0 -> Apply("consumer", "start", "", 0, producerPc, 1, owner, queue, count, received)
  [] consumerPc = 1 -> Apply("consumer", "receive", "queue", Head(queue), producerPc, 2, owner, Tail(queue), count, Append(received, Head(queue)))
  [] consumerPc = 2 -> Apply("consumer", "receive", "queue", Head(queue), producerPc, 3, owner, Tail(queue), count, Append(received, Head(queue)))
  [] consumerPc = 3 -> Apply("consumer", "lock", "mutex", 0, producerPc, 4, "consumer", queue, count+1, received)
  [] consumerPc = 4 -> Apply("consumer", "checkpoint", "critical", 0, producerPc, 5, owner, queue, count, received)
  [] consumerPc = 5 -> Apply("consumer", "unlock", "mutex", 0, producerPc, 6, "", queue, count, received)
  [] OTHER -> Apply("consumer", "$done", "", 0, producerPc, 7, owner, queue, count, received)

RefuseDisabled == /\ index' = index+1 /\ valid' = FALSE
                  /\ UNCHANGED <<producerPc, consumerPc, owner, queue, count, received>>

Next == IF index = Len(WitnessActors) THEN UNCHANGED vars
        ELSE IF WitnessActors[index+1] \notin Enabled THEN RefuseDisabled
        ELSE IF WitnessActors[index+1] = "producer" THEN ProducerStep ELSE ConsumerStep

Conforms == /\ valid /\ count = WitnessCounts[index+1]
            /\ received = WitnessReceived[index+1]
            /\ (IF index < Len(WitnessActors)
                THEN WitnessEnabled[index+1] = Enabled
                ELSE producerPc = 7 /\ consumerPc = 7 /\ count = 2 /\ received = <<10,20>>)
=============================================================================
