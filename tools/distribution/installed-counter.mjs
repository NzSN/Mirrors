/** Installed Counter port and the generated-module digest binding. */

export function installedCounterPort(variant) {
  if (variant !== "correct" && variant !== "faulty") {
    throw new Error("installed counter variant must be correct or faulty");
  }
  let count = 0n;
  return {
    actions: {
      Initialize() {
        count = 0n;
      },
      Tick({ Stride }) {
        count += Stride + (variant === "faulty" ? -1n : 0n);
      },
    },
    observe() {
      return { Count: count };
    },
  };
}

/**
 * Negotiation compares this digest with the generated module. A raw factory
 * object has no digest and fails closed as binding_digest_mismatch.
 */
export function bindInstalledCounter(model, variant, config = {}) {
  if (typeof model.semanticDigest !== "string" || model.semanticDigest.length !== 64) {
    throw new Error("generated Counter semantic digest is missing");
  }
  const bound = model.bindLocal(installedCounterPort(variant), config);
  return { ...bound, semanticDigest: model.semanticDigest };
}
