import { Counter } from "./src/counter.mjs";

export function createAdapter() {
  const counter = new Counter();
  return {
    actions: {
      Initialize: () => { counter.reset(); },
      Tick: ({ Stride }) => { counter.increment(Stride); },
    },
    observe: () => ({ Count: counter.read() }),
  };
}
