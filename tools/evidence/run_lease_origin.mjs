#!/usr/bin/env node
import assert from "node:assert/strict";
import { writeFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";
import { resolve } from "node:path";

const ecma = process.env.MIRRORECMA_ROOT;
assert(ecma, "MIRRORECMA_ROOT is required");
const [flag, receipt] = process.argv.slice(2);
assert(flag === "--receipt" && receipt, "--receipt NEW_FILE is required");
delete process.env.APALACHE_MC;
const { loadApplication, evaluateLocal } = await import(pathToFileURL(resolve(ecma, "examples/application-validation/suite.mjs")));
const app = await loadApplication("lease-service");
const baseline = await evaluateLocal(app, "correct");
assert.equal(baseline.classification, "passed");
assert.equal(baseline.cleanup.status, "confirmed");
const fault = await evaluateLocal(app, "expired-token");
assert.equal(fault.classification, "mismatch");
assert.equal(fault.failure.code, "replay_mismatch");
assert.equal(fault.failure.action, "write");
assert.equal(fault.failure.stateIndex, 5);
assert.equal(fault.cleanup.status, "confirmed");
const result = {
  schema: "mirrors.lease-reduction-origin/v1",
  baseline: { outcome: baseline.classification, cleanup: baseline.cleanup },
  fault: { outcome: fault.classification, failure: fault.failure, cleanup: fault.cleanup, suiteResult: fault.suiteResult },
  suiteId: app.suite.id ?? app.suite.suiteId,
};
const bytes = JSON.stringify(result, (_key, value) => typeof value === "bigint" ? {"#bigint": String(value)} : value, 2) + "\n";
await writeFile(receipt, bytes, {flag: "wx", mode: 0o600});
console.log(bytes);
