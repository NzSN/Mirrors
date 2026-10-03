/** Public synthetic implementation. It owns mutable cells; expected model
 * states, trace locations and the private descriptor never enter this module. */
export function createAdapter({ faulty = false, disposeFailure = false, onDispose = () => {} } = {}) {
  let cells;
  let closed = false;
  const active = () => { if (closed) throw new Error("adapter is disposed"); };
  const fresh = () => ({ count: 0n, labels: new Set(["fresh"]), weights: new Map([["seen", 0n], ["updates", 0n]]) });
  return {
    actions: {
      Initialize() { active(); cells = [fresh(), fresh()]; },
      Update({ Index, Delta, Labels, Weights }) {
        active();
        if (typeof Index !== "bigint" || Index < 0n || Index > 1n || typeof Delta !== "bigint" ||
            !(Labels instanceof Set) || !(Weights instanceof Map)) throw new TypeError("native collection bridge failed");
        const cell = cells[Number(Index)];
        cell.count += Delta;
        cell.labels = new Set(Labels);
        cell.weights = new Map(Weights);
      },
    },
    observe() {
      active();
      return { Cells: cells.map((cell, index) => ({ entry: {
        count: cell.count + (faulty && index === 0 ? 1n : 0n),
        labels: new Set(cell.labels), weights: new Map(cell.weights),
      } })) };
    },
    dispose() { if (closed) return; closed = true; cells = undefined; onDispose(); if (disposeFailure) throw new Error("synthetic cleanup failure"); },
  };
}
