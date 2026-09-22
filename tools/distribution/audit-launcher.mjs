import assert from "node:assert/strict";
import { access, readdir } from "node:fs/promises";
import { spawn } from "node:child_process";

const [hiddenJson, executable, ...args] = process.argv.slice(2);
const hidden = JSON.parse(hiddenJson);
for (const path of hidden) {
  try {
    const entries = await readdir(path);
    assert.deepEqual(entries, [], "forbidden directory contents remained readable: " + path);
  } catch (error) {
    if (error?.code !== "ENOENT" && error?.code !== "ENOTDIR") throw error;
  }
}
for (const path of ["/usr/bin/node", "/usr/bin/npm", "/usr/local/bin/node"]) {
  let visible = true;
  try { await access(path); } catch { visible = false; }
  assert.equal(visible, false, "forbidden path remained readable: " + path);
}
const child = spawn(executable, args, { stdio: "inherit", env: process.env });
const code = await new Promise((resolve, reject) => {
  child.once("error", reject);
  child.once("exit", (value, signal) => resolve(signal ? 128 : value ?? 1));
});
process.exitCode = code;
