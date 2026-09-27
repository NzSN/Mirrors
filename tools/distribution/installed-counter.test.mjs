import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { bindInstalledCounter } from "./installed-counter.mjs";

const generatedDigest = "193d6cc187d05c18f02ad483a44f8ad0c1634b02083df241df08b9281b045d1c";

function modelFor(variantAssertion) {
  return {
    semanticDigest: generatedDigest,
    bindLocal(port) {
      variantAssertion(port);
      return {
        semanticDigest: undefined,
        assertCompatibleConfig() {},
        computer() {},
        dispose() {},
      };
    },
  };
}

test("installed counter binding uses the generated module digest", () => {
  let correctCount;
  const correct = bindInstalledCounter(modelFor((port) => {
    port.actions.Initialize();
    port.actions.Tick({ Stride: 2n });
    correctCount = port.observe().Count;
  }), "correct");
  assert.equal(correct.semanticDigest, generatedDigest);
  assert.equal(correctCount, 2n);

  let faultyCount;
  const faulty = bindInstalledCounter(modelFor((port) => {
    port.actions.Initialize();
    port.actions.Tick({ Stride: 2n });
    faultyCount = port.observe().Count;
  }), "faulty");
  assert.equal(faulty.semanticDigest, generatedDigest);
  assert.notEqual(faulty.semanticDigest, undefined);
  assert.equal(faultyCount, 1n);
});

test("installed counter driver no longer supplies a digest-less factory", () => {
  const source = readFileSync(new URL("./counter-driver.mjs", import.meta.url), "utf8");
  assert.match(source, /runSuite\(/);
  assert.equal(source.includes("runSuiteWithFactory"), false);
  assert.match(source, /installedCounterPort/);
});
