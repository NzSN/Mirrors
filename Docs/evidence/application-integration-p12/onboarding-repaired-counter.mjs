/** Independent application state; no model, fixture, or Mirrors dependency. */
export class Counter {
  #count = 0n;

  reset() {
    this.#count = 0n;
  }

  increment(stride) {
    if (typeof stride !== "bigint") throw new TypeError("stride must be bigint");
    this.#count += stride;
  }

  read() {
    return this.#count;
  }
}
