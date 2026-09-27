#!/usr/bin/env node
// R0-to-bundle materializer for `framework.reproduction`.
//
// Reads a finalized private R0 evidence envelope plus its suite-result artifact,
// obtains the reproduction identities through MirrorECMA's public identity
// authority, builds the bundle from the recorded failure fields, and validates
// it with the public bundle validators before writing reproduction-bundle.json.
import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import {
  inspectProjectReproductionWithCatalog,
  validateReproductionBundle,
  encodeReproductionBundle,
} from "mirrorecma";

function fail(message) {
  console.error(`reproduction capture failed: ${message}`);
  process.exit(2);
}

function argument(name) {
  const index = process.argv.indexOf(name);
  if (index < 0 || index + 1 >= process.argv.length)
    fail(`missing ${name}`);
  return process.argv[index + 1];
}

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function resolveInstallation(installation, base) {
  return {
    ...installation,
    executables: installation.executables.map((item) => ({
      ...item,
      path: resolve(base, item.path),
    })),
    packages: installation.packages.map((item) => ({
      ...item,
      root: resolve(base, item.root),
      manifest: { ...item.manifest, path: resolve(base, item.manifest.path) },
    })),
    runtimeTrees: installation.runtimeTrees.map((item) => ({
      ...item,
      root: resolve(base, item.root),
    })),
  };
}

function inlineCapture(role, mediaType, bytes) {
  return {
    role,
    kind: "inline",
    mediaType,
    bytes: bytes.byteLength,
    sha256: sha256(bytes),
    base64: Buffer.from(bytes).toString("base64"),
  };
}

const envelopePath = argument("--envelope");
const suiteResultPath = argument("--suite-result");
const projectPath = argument("--project");
const frameworkInputPath = argument("--framework-input");
const combinationId = argument("--combination");
const outPath = argument("--out");

const envelopeBytes = await readFile(envelopePath);
const envelope = JSON.parse(envelopeBytes.toString("utf8"));
if (envelope.schemaVersion !== "mirrors.evidence-envelope/v1.0")
  fail("R0 artifact is not a mirrors evidence envelope");
if (envelope.projectionKind !== "private")
  fail("R0 envelope must be the private projection");
if (typeof envelope.runId !== "string" || envelope.runId.length === 0)
  fail("R0 envelope lacks a run id");
const producerResults = Array.isArray(envelope.producerResults)
  ? envelope.producerResults
  : [];
const suiteProducer = producerResults.find(
  (entry) => entry.schemaVersion === "mirrorecma.suite-result/v1",
);
if (suiteProducer === undefined)
  fail("R0 envelope lacks a suite-result producer result");
const suiteArtifact = (Array.isArray(envelope.artifacts) ? envelope.artifacts : []).find(
  (entry) => entry.artifactId === suiteProducer.artifactId,
);
if (suiteArtifact === undefined)
  fail("R0 suite-result artifact does not resolve");
if (suiteArtifact.location?.kind !== "bundle")
  fail("R0 suite-result artifact is not retained in its bundle");
const suiteBytes = await readFile(suiteResultPath);
if (sha256(suiteBytes) !== suiteArtifact.sha256 || suiteBytes.byteLength !== suiteArtifact.bytes)
  fail("R0 suite-result bytes differ from the envelope artifact identity");
const suite = JSON.parse(suiteBytes.toString("utf8"));
if (suite.schema !== "mirrorecma.suite-result/v1")
  fail("R0 artifact is not a suite result");
if (suite.outcome !== "mismatch" || suite.failure?.kind !== "mismatch")
  fail("R0 suite result is not the recorded mismatch");
const { traceIndex, stateIndex, action } = suite.failure;
if (!Number.isSafeInteger(traceIndex) || !Number.isSafeInteger(stateIndex))
  fail("R0 mismatch coordinates are incomplete");
if (typeof action !== "string" || action.length === 0)
  fail("R0 mismatch action is unavailable");
const cleanupStatus = suite.cleanup?.status;
if (typeof cleanupStatus !== "string" || cleanupStatus.length === 0)
  fail("R0 cleanup status is unavailable");

const frameworkInput = JSON.parse((await readFile(frameworkInputPath)).toString("utf8"));
if (
  typeof frameworkInput.catalogRaw !== "string" ||
  typeof frameworkInput.selectionRef !== "object" ||
  typeof frameworkInput.observed !== "object" ||
  typeof frameworkInput.installation !== "object"
)
  fail("framework input is not a mirrors installed-framework input");
const installation = resolveInstallation(
  frameworkInput.installation,
  dirname(resolve(frameworkInputPath)),
);
const authority = await inspectProjectReproductionWithCatalog(projectPath, {
  combinationId,
  catalogSelection: frameworkInput.selectionRef,
  catalogRaw: frameworkInput.catalogRaw,
  frameworkObserved: frameworkInput.observed,
  ...(frameworkInput.approval === undefined ? {} : { frameworkApproval: frameworkInput.approval }),
  installation,
});

const bundle = validateReproductionBundle({
  schema: "mirrorecma.reproduction-bundle/v1",
  evidenceLinks: {
    runRef: {
      schemaVersion: envelope.schemaVersion,
      runId: envelope.runId,
      envelopeSha256: sha256(envelopeBytes),
      projectionKind: envelope.projectionKind,
    },
    componentRefs: envelope.components,
    artifactRefs: [suiteArtifact],
    catalogSelectionRef: envelope.catalogSelectionRef,
  },
  identities: authority.identities,
  signature: {
    primary: {
      kind: "behavioral_mismatch",
      code: "replay_mismatch",
      traceIndex,
      stateIndex,
      action,
    },
    cleanup: { status: cleanupStatus },
  },
  captures: [
    inlineCapture("evidence-envelope", "application/json", envelopeBytes),
    inlineCapture("suite-result", "application/json", suiteBytes),
  ],
  // Governance decision pending: these are the documented MirrorECMA test-fixture
  // policy identifiers, and reproduction preflight never consults them.
  handling: {
    consentPolicyId: "fixture-consent/v1",
    redactionProfileId: "fixture-redaction/v1",
    accessPolicyId: "fixture-access/v1",
    retentionUntil: "2026-12-31T00:00:00Z",
    deletionPolicyId: "fixture-delete/v1",
  },
});

await writeFile(outPath, encodeReproductionBundle(bundle), { mode: 0o600, flag: "wx" });
console.log(JSON.stringify({
  status: "captured",
  bundle: outPath,
  runId: envelope.runId,
  selection: bundle.evidenceLinks.catalogSelectionRef.selectionValue,
  identities: Object.keys(bundle.identities).sort(),
}));
