// Generated DPM wiring only. Application behavior stays handwritten.
import type { ScheduleStep, ScheduleActor } from 'mirrorecma';
export const modelSemanticDigest = "d54bd0b831cdfffd1b42ec41e0cd9c71e4ad9374dce7719932a67120faeff3da";
export const mappingSha256 = "5c37b697b199019fdb8210686c063a155b2841494fa506a92db0b3b57c2067c3";
const actorIds: readonly string[] = Object.freeze(["a","b"]);
export const actors: readonly ScheduleActor[] = Object.freeze([Object.freeze({actor:"a",operation:"increment-a"}),Object.freeze({actor:"b",operation:"increment-b"})]);
export const checkpoints: readonly string[] = Object.freeze(["read","write"]);
export function stepFor(actionId: string, actor?: string): ScheduleStep {
  switch (actionId) {
    case "Finish": {
      const selected = actor;
      if (typeof selected !== 'string' || !actorIds.includes(selected)) throw new Error('undeclared kit actor');
      return {actor: selected, checkpoint: "$done"};
    }
    case "Read": {
      const selected = actor;
      if (typeof selected !== 'string' || !actorIds.includes(selected)) throw new Error('undeclared kit actor');
      return {actor: selected, checkpoint: "read"};
    }
    case "Write": {
      const selected = actor;
      if (typeof selected !== 'string' || !actorIds.includes(selected)) throw new Error('undeclared kit actor');
      return {actor: selected, checkpoint: "write"};
    }
    default: throw new Error('unmapped kit action');
  }
}
