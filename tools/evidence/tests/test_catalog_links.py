from __future__ import annotations

import copy
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


EVIDENCE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(EVIDENCE))

import catalog_links  # noqa: E402
import finalize  # noqa: E402
import qualification_scope  # noqa: E402
import verify  # noqa: E402


class CatalogLinkTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.repository = self.root / "repository"
        self.repository.mkdir()
        subprocess.run(["git", "init", "-q", str(self.repository)], check=True)
        subprocess.run(["git", "-C", str(self.repository), "config", "user.email", "fixture@example.invalid"], check=True)
        subprocess.run(["git", "-C", str(self.repository), "config", "user.name", "Fixture"], check=True)
        subprocess.run(["git", "-C", str(self.repository), "remote", "add", "origin", "https://example.invalid/fixture.git"], check=True)
        (self.repository / "source.txt").write_text("source\n")
        subprocess.run(["git", "-C", str(self.repository), "add", "."], check=True)
        subprocess.run(["git", "-C", str(self.repository), "commit", "-qm", "fixture"], check=True)
        self.store = self.root / "store"
        revision = subprocess.check_output(
            ["git", "-C", str(self.repository), "rev-parse", "HEAD"], text=True
        ).strip()
        self.components = [
            {"componentId": component_id,
             "repository": f"https://example.invalid/{component_id}.git",
             "revision": revision, "dirty": False}
            for component_id in ("mirrors", "mirrorecma", "mirrorgate")
        ]
        self.selection = {"schemaVersion":"mirrors.framework-catalog/v1",
                          "selectionKind":"sha256","selectionValue":"a" * 64}
        self.run_count = 0
        self.registry = self.root / "commands.json"
        self.registry.write_text(json.dumps({
            "schemaVersion":"mirrors.evidence-command-registry/v1","commands":[{
                "commandId":"mirrors.local-no-model","tierId":"mirrors.required",
                "requirement":"required","argvPrefix":[sys.executable],
                "defaultTimeoutSeconds":10}]}))

    def tearDown(self):
        self.temporary.cleanup()

    def _finalized(self, commands, components, extras=(), cleanup=(), mutate=None):
        self.run_count += 1
        run_id = f"fixture-run-{self.run_count}"
        document = json.loads((EVIDENCE / "fixtures/envelope-private.valid.json").read_text())
        document["runId"] = run_id
        document["catalogSelectionRef"] = copy.deepcopy(self.selection)
        document["components"] = copy.deepcopy(components)
        artifacts = []
        command_records = []
        tier_artifacts = {}
        payloads = {}
        for index, (command_id, tier_id) in enumerate(commands):
            artifact_id = f"command-{index}"
            data = f"{command_id}: passed\n".encode()
            payloads[artifact_id] = data
            artifacts.append((artifact_id, "command-log", data, None))
            command_records.append({"commandId":command_id,"tierId":tier_id,
                "requirement":"required","argv":["fixture",command_id],
                "cwd":"/private/fixture","exit":{"kind":"code","code":0},
                "logArtifactId":artifact_id})
            tier_artifacts.setdefault(tier_id, []).append(artifact_id)
        self.assertEqual(len(command_records), 1)
        selected_entry = {"commandId":command_records[0]["commandId"],
            "tierId":command_records[0]["tierId"],"requirement":"required",
            "argvPrefix":command_records[0]["argv"],"argvLength":len(command_records[0]["argv"]),
            "requiredCwd":command_records[0]["cwd"],"defaultTimeoutSeconds":10,
            "registryOwnerComponentId":components[0]["componentId"]}
        registry_raw = json.dumps({
            "schemaVersion":"mirrors.evidence-command-registry/v1",
            "commands":[selected_entry],
        }, sort_keys=True, separators=(",", ":"))
        context = {"schemaVersion":"mirrors.evidence-command-context/v1",
            "registry":{"schemaVersion":"mirrors.evidence-command-registry/v1",
                "sha256":hashlib.sha256(registry_raw.encode()).hexdigest(),
                "rawUtf8":registry_raw,"ownerComponentRef":components[0],
                "selectedEntry":selected_entry},
            "command":{"commandId":command_records[0]["commandId"],
                "argv":command_records[0]["argv"],"cwd":command_records[0]["cwd"],
                "effectiveEnvironment":[],"environmentFiles":[]},
            "executable":{"requested":"fixture","resolution":"available",
                "resolvedPath":"/fixture","bytes":1,"sha256":"8"*64}}
        artifacts.append(("command-context","diagnostic",finalize.canonical_json(context),None))
        artifacts.extend(extras)
        document["commands"] = command_records
        document["tiers"] = [{"tierId":tier_id,"requirement":"required","status":"passed",
            "reasonCode":"passed","artifactIds":ids} for tier_id, ids in tier_artifacts.items()]
        document["artifacts"] = []
        document["producerResults"] = []
        staging = self.store / "staging" / run_id
        private = staging / "artifacts/private"
        private.mkdir(mode=0o700, parents=True)
        for directory in (self.store, self.store / "staging", staging,
                          staging / "artifacts", private):
            os.chmod(directory, 0o700)
        for artifact_id, role, data, producer_schema in artifacts:
            filename = f"{artifact_id}.dat"
            target = private / filename
            target.write_bytes(data); os.chmod(target, 0o600)
            document["artifacts"].append({"artifactId":artifact_id,
                "mediaType":"application/json" if role != "command-log" else "text/plain",
                "role":role,"bytes":len(data),"sha256":hashlib.sha256(data).hexdigest(),
                "visibility":"private","requirement":"required",
                "location":{"kind":"bundle","path":f"artifacts/private/{filename}"}})
            if producer_schema is not None:
                document["producerResults"].append({"producer":producer_schema[0],
                    "schemaVersion":producer_schema[1],"artifactId":artifact_id})
        required = [artifact["artifactId"] for artifact in document["artifacts"]]
        document["releaseRequirements"] = {"requiredArtifactIds":required,
            "requiredStructuralRoles":["public-summary","private-index"],
            "requiredCleanupScopes":[entry["scope"] for entry in cleanup
                                      if entry["requirement"] == "required"]}
        document["outcomes"] = {"behavior":{"status":"passed","classification":{
            "namespace":"fixture","code":"passed"}},
            "cleanup":list(cleanup) or [{"scope":"local-cooperative",
                "requirement":"not-applicable","status":"not_applicable","artifactIds":[]}],
            "persistence":{"requirement":"required","status":"incomplete",
                "reasonCode":"awaiting-final-index","requiredArtifactIds":required,
                "missingArtifactIds":[]}}
        if document["producerResults"]:
            document["outcomes"]["behavior"]["producerResult"] = document["producerResults"][0]
        document["qualification"] = {"status":"incomplete","reasonCodes":["awaiting-final-index"]}
        if mutate is not None:
            mutate(document)
        envelope_path = staging / "envelope.staging.json"
        envelope_path.write_bytes(finalize.canonical_json(document)); os.chmod(envelope_path, 0o600)
        bundle, _ = finalize.finalize(staging, self.store)
        return bundle, verify.verify(bundle)

    def _distribution_payloads(self, mutate=None):
        artifact = {"artifactId":"fixture-package","path":"artifacts/fixture.tgz",
            "kind":"archive","mediaType":"application/gzip","bytes":1,"sha256":"1"*64,
            "mode":"0644","source":{"kind":"component-build","id":"fixture-package"}}
        manifest = {"schemaVersion":"mirrors.reference-distribution-manifest/v1",
            "distributionId":"fixture-distribution","catalogSelectionRef":self.selection,
            "profileId":"checked-replay-gate","componentRefs":self.components,
            "buildInputs":[
                {"inputId":"profiles-lock","path":"distribution/reference-node/profiles.json","bytes":1,"sha256":"d"*64},
                {"inputId":"component-lock","path":"distribution/reference-node/component-lock.json","bytes":1,"sha256":"e"*64},
                {"inputId":"dependency-lock","path":"distribution/reference-node/dependency-lock.json","bytes":1,"sha256":"f"*64}],
            "buildProvenance":{"snapshotIndexSha256":"2"*64,"tools":[
                {"toolId":"git","version":"fixture","bytes":1,"sha256":"3"*64},
                {"toolId":"lake","version":"fixture","bytes":1,"sha256":"4"*64},
                {"toolId":"framework-catalog-bootstrap","version":"fixture","bytes":1,"sha256":"5"*64}],
                "trees":[
                    {"inputId":"typescript-node-modules","algorithm":"mirrors-runtime-tree-v1","digest":"6"*64,"entryCount":1,"bytes":1},
                    {"inputId":"evidence-wheels","algorithm":"mirrors-runtime-tree-v1","digest":"7"*64,"entryCount":1,"bytes":1}]},
            "artifacts":[artifact],"runtimeTrees":[],"hostRequirements":[],"publication":"unclaimed"}
        if mutate is not None:
            mutate(manifest)
        manifest_raw = finalize.canonical_json(manifest)
        cache = {"schemaVersion":"mirrors.reference-cache-index/v1",
            "profileId":manifest["profileId"],"catalogSelectionRef":self.selection,
            "distributionManifestSha256":hashlib.sha256(
                qualification_scope._canonical_framework_json(manifest)).hexdigest(),
            "entries":[{key:artifact[key] for key in ("artifactId","path","bytes","sha256","mode")}]}
        return [("distribution-manifest","distribution-manifest",manifest_raw,None),
                ("cache-index","cache-index",finalize.canonical_json(cache),None)]

    def bundle(self, mutate_staging=None, full_profile=True, mutate_scope=None,
               mutate_distribution=None, mismatch_reduction_input=False):
        if not full_profile:
            return self._finalized([("mirrors.local-no-model","mirrors.required")],
                                   [self.components[0]], mutate=mutate_staging)
        distribution, distribution_verification = self._finalized(
            [("framework.install-diagnostics","qualification.install")], self.components,
            self._distribution_payloads(mutate_distribution))
        _other_distribution, other_distribution_verification = self._finalized(
            [("fixture.install-diagnostic","fixture.install")], self.components,
            self._distribution_payloads(
                lambda manifest: manifest.__setitem__("distributionId", "fixture-other")))
        runs = []
        def add(phase, commands, components, *, extras=(), cleanup=(), dependencies=(), distribution_bound=True):
            bundle, checked = self._finalized(commands, components, extras, cleanup)
            node = {"phase":phase,"evidenceUse":"qualification-credit",
                "privateRunRef":checked["privateRunRef"],"publicRunRef":checked["publicRunRef"],
                "distributionRunId":distribution_verification["runId"] if distribution_bound else None,
                "dependsOnRunIds":([distribution_verification["runId"]] if distribution_bound else []) + list(dependencies)}
            runs.append((bundle, checked, node))
            return bundle, checked, node
        for command_id, tier_id, component_ids in [
            ("mirrors.local-no-model","mirrors.required",["mirrors"]),
            ("mirrors.remote-model-check","mirrors.remote-model-check",["mirrors"]),
            ("mirrors.interop","mirrors.interop",["mirrors","mirrorecma","mirrorgate"]),
            ("mirrorecma.project-check","mirrorecma.project",["mirrors","mirrorecma"]),
            ("mirrorecma.test","mirrorecma.required",["mirrors","mirrorecma"]),
            ("mirrorgate.required","mirrorgate.required",["mirrors","mirrorgate"])]:
            add("source-gate", [(command_id,tier_id)],
                [item for item in self.components if item["componentId"] in component_ids],
                distribution_bound=False)
        add("source-gate", [("mirrors.local-no-model","mirrors.required")],
            [self.components[0]], distribution_bound=False)
        runs[-1][2]["evidenceUse"] = "retained-attempt"
        add("installed-diagnostic", [("fixture.installed","fixture.installed")], self.components,
            extras=[("producer","producer-result",b"{}\n",("fixture","fixture.result/v1"))])
        add("replay", [("framework.replay-correct","qualification.replay")], self.components,
            extras=[("cleanup","cleanup-receipt",b"{}\n",None)],
            cleanup=[{"scope":"local-cooperative","requirement":"required","status":"confirmed",
                      "artifactIds":["cleanup"]}])
        add("replay", [("framework.replay-faulty","qualification.replay")], self.components)
        _origin_bundle, origin_checked, _origin_node = add(
            "origin", [("mirrorgate.application-campaign.lease-service",
                        "mirrorgate.application-campaign")], self.components)
        _retry_bundle, retry_checked, _retry_node = add(
            "origin", [("mirrorgate.application-campaign.lease-service",
                        "mirrorgate.application-campaign")], self.components)
        _retry_node["evidenceUse"] = "retained-attempt"
        reproduction_data = finalize.canonical_json({"evidenceLinks":{
            "runRef":origin_checked["privateRunRef"]}})
        _reproduction_bundle, reproduction_checked, _ = add(
            "reproduction", [("framework.reproduction","qualification.reproduction")], self.components,
            extras=[("reproduction","reproduction-input",reproduction_data,None)],
            dependencies=[origin_checked["runId"]])
        add("reduction", [("framework.reduction","qualification.reduction")], self.components,
            extras=[("reproduction","reproduction-input",
                     reproduction_data + (b" " if mismatch_reduction_input else b""),None)],
            dependencies=[reproduction_checked["runId"]])
        add("mutation", [("framework.mutation-local","qualification.mutation-local")], self.components)
        add("mutation", [("framework.mutation-gate","qualification.mutation-gate")], self.components,
            extras=[("gate-cleanup","cleanup-receipt",b"{}\n",None)],
            cleanup=[{"scope":"gate-physical","requirement":"required","status":"confirmed",
                      "artifactIds":["gate-cleanup"]}])
        recovery_data = finalize.canonical_json({"original":{
            "runRef":origin_checked["privateRunRef"]}})
        add("recovery", [("mirrorgate.recovery","qualification.recovery")], self.components,
            extras=[("recovery","recovery-receipt",recovery_data,None)],
            cleanup=[{"scope":"gate-recovery","requirement":"required","status":"confirmed",
                      "artifactIds":["recovery"]}],
            dependencies=[origin_checked["runId"]])
        scope = {"schemaVersion":"mirrors.qualification-scope/v1","scopeId":"fixture-scope",
            "qualificationClass":"release-candidate","selectedCatalogRef":self.selection,
            "distributionBindingRunId":distribution_verification["runId"],
            "nodes":[{"phase":"distribution","evidenceUse":"qualification-credit",
                "privateRunRef":distribution_verification["privateRunRef"],
                "publicRunRef":distribution_verification["publicRunRef"],
                "distributionRunId":None,"dependsOnRunIds":[]},
                {"phase":"distribution","evidenceUse":"supporting-diagnostic",
                "privateRunRef":other_distribution_verification["privateRunRef"],
                "publicRunRef":other_distribution_verification["publicRunRef"],
                "distributionRunId":None,"dependsOnRunIds":[]},
                *[node for _bundle, _checked, node in runs]]}
        if mutate_scope is not None:
            mutate_scope(scope)
        scope_raw = finalize.canonical_json(scope)
        return self._finalized([("evidence.offline-verify","qualification.evidence")],
            self.components, extras=[("qualification-scope","producer-result",scope_raw,
                (qualification_scope.SCOPE_PRODUCER,qualification_scope.SCOPE_PRODUCER_SCHEMA))],
            mutate=mutate_staging)

    def scope_from_bundle(self, bundle):
        envelope = json.loads((bundle / "envelope.json").read_text())
        artifact = next(item for item in envelope["artifacts"]
                        if item["artifactId"] == "qualification-scope")
        return json.loads((bundle / artifact["location"]["path"]).read_text())

    def catalog(self, bundle: Path, verification: dict, *, visibility="public"):
        envelope = json.loads((bundle / "envelope.json").read_text())
        components = copy.deepcopy(envelope["components"])
        catalog = {
            "schemaVersion": "mirrors.framework-catalog/v1",
            "catalogId": "fixture-linked",
            "visibility": visibility,
            "components": [{
                "componentRef": component,
                "product": {"name": component["componentId"], "version": "1.0.0"},
                "records": [{"recordId": "source", "path": "source.txt", "recordKind": "source"}],
            } for component in components],
            "evidenceRefs": [{"evidenceId": "run-fixture", "runRef": copy.deepcopy(verification["publicRunRef"])}],
            "capabilities": [{
                "capabilityId": "fixture.capability",
                "ownerComponentId": components[0]["componentId"],
                "description": "Fixture capability",
                "declaration": {"state": "available", "constraints": []},
                "sourceImplementation": {"state": "present", "locations": [{"path": "source.txt", "symbol": "fixture"}]},
                "observations": {
                    "sourceTested": {"state": "accepted", "evidenceId": "run-fixture"},
                    "locallyAccepted": {"state": "accepted", "evidenceId": "run-fixture"},
                    "installedConsumerAccepted": {"state": "accepted", "evidenceId": "run-fixture"},
                    "hostedCiAccepted": {"state": "notRun"},
                    "published": {"state": "unknown"},
                },
            }],
            "distributionProfiles": [{
                "profileId": "fixture-local",
                "platform": {"os": "linux", "osRelease": "ubuntu-24.04", "architecture": "x86_64", "backend": "local-process"},
                "requiredCapabilityIds": ["fixture.capability"],
                "optionalCapabilityIds": [],
                "requiredObservationDimensions": ["installedConsumerAccepted"],
                "dependencies": [],
            }],
            "combinations": [{
                "combinationId": "fixture-combination",
                "componentIds": [component["componentId"] for component in components],
                "platform": {"os": "linux", "osRelease": "ubuntu-24.04", "architecture": "x86_64", "backend": "local-process"},
                "capabilityIds": ["fixture.capability"],
                "distributionProfileIds": ["fixture-local"],
                "declaredState": "candidate",
                "evidenceIds": ["run-fixture"],
            }],
            "extensions": {"org.nzsn.catalog-lineage": {"previousSelectionRef": envelope["catalogSelectionRef"]}},
        }
        path = self.root / f"catalog-{len(list(self.root.glob('catalog-*.json')))}.json"
        path.write_text(json.dumps(catalog, indent=2) + "\n")
        return path, catalog

    def private_profile(self):
        profile = json.loads((EVIDENCE / "qualification-profiles.json").read_text())
        next(item for item in profile["profiles"] if item["profileId"] == "release-candidate")["catalogVisibility"] = "private"
        path = self.root / "private-profile.json"
        path.write_text(json.dumps(profile))
        return path

    def evaluate(self, catalog_path, bundle, verification, profiles_path=catalog_links.DEFAULT_PROFILES):
        return catalog_links.evaluate_catalog_link(
            catalog_path, bundle, verification, "release-candidate", profiles_path
        )

    def test_distribution_manifest_digest_uses_framework_canonical_json(self):
        vectors = json.loads((Path("test/fixtures/framework-catalog/canonicalization-vectors.json")).read_text())
        for vector in vectors["vectors"]:
            with self.subTest(vector=vector["name"]):
                self.assertEqual(
                    catalog_links._framework_canonical(vector["value"]).decode(),
                    vector["canonical"],
                )

    def evaluate_profile(self, profile_id, catalog_path, bundle, verification):
        return catalog_links.evaluate_catalog_link(
            catalog_path, bundle, verification, profile_id, catalog_links.DEFAULT_PROFILES
        )

    def test_valid_link_is_deterministic_and_contains_no_private_locator(self):
        bundle, verification = self.bundle()
        catalog_path, _ = self.catalog(bundle, verification)
        envelope = json.loads((bundle / "envelope.json").read_text())
        scope_result = qualification_scope.attached_scope(
            bundle, envelope, self.store)
        credited_ids = [command["commandId"] for command in scope_result["commands"]]
        self.assertEqual(
            credited_ids.count("mirrorgate.application-campaign.lease-service"), 1)
        self.assertNotIn("fixture.install-diagnostic", credited_ids)
        first = self.evaluate(catalog_path, bundle, verification)
        self.assertEqual(first["qualification"], "accepted")
        self.assertEqual(first["selectedCatalogRef"]["selectionValue"], "a" * 64)
        self.assertEqual(first["approvalCatalogRef"]["selectionValue"], first["catalogSha256"])
        self.assertRegex(first["distributionManifestSha256"], r"^[0-9a-f]{64}$")
        self.assertRegex(first["cacheIndexSha256"], r"^[0-9a-f]{64}$")
        self.assertEqual(first["integrity"], "verified")
        self.assertEqual(first["executionProvenance"], "evidence-observed")
        rendered = json.dumps(first, sort_keys=True)
        self.assertNotIn(str(bundle), rendered)
        self.assertNotIn("/tmp/", rendered)
        cli = subprocess.run([
            sys.executable, str(EVIDENCE / "verify.py"), "--offline",
            "--catalog", str(catalog_path), "--profile", "release-candidate", str(bundle),
        ], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertEqual(cli.returncode, 0, cli.stderr.decode())
        self.assertEqual(json.loads(cli.stdout)["catalogLink"], first)

    def test_digest_mismatch_and_missing_public_projection_are_rejected(self):
        bundle, verification = self.bundle()
        catalog_path, catalog = self.catalog(bundle, verification)
        catalog["evidenceRefs"][0]["runRef"]["envelopeSha256"] = "0" * 64
        catalog_path.write_text(json.dumps(catalog))
        with self.assertRaisesRegex(ValueError, "matching finalized public runRef"):
            self.evaluate(catalog_path, bundle, verification)
        (bundle / "public-summary.json").unlink()
        with self.assertRaises((OSError, ValueError)):
            verify.verify(bundle)

    def test_component_revision_and_dirty_state_mismatch_are_rejected(self):
        bundle, verification = self.bundle()
        catalog_path, catalog = self.catalog(bundle, verification)
        catalog["components"][0]["componentRef"]["revision"] = "b" * 40
        catalog_path.write_text(json.dumps(catalog))
        with self.assertRaisesRegex(ValueError, "component identity differs"):
            self.evaluate(catalog_path, bundle, verification)

        catalog_path, catalog = self.catalog(bundle, verification, visibility="private")
        reference = catalog["components"][0]["componentRef"]
        reference["dirty"] = True
        reference["dirtyContent"] = {
            "algorithm": "sha256", "digest": "c" * 64,
            "method": "git-diff-and-untracked-manifest-v1", "includedPaths": [], "excludedPaths": [],
        }
        catalog_path.write_text(json.dumps(catalog))
        with self.assertRaisesRegex(ValueError, "component identity differs"):
            self.evaluate(catalog_path, bundle, verification, self.private_profile())

    def test_required_skip_and_unconfirmed_cleanup_are_rejected(self):
        def skip(document):
            document["tiers"][0]["status"] = "skipped"
            document["tiers"][0]["reasonCode"] = "required-skip"
            document["outcomes"]["behavior"] = {
                "status": "not_run", "classification": {"namespace": "fixture", "code": "required-skip"}
            }

        bundle, verification = self.bundle(skip)
        catalog_path, _ = self.catalog(bundle, verification)
        with self.assertRaisesRegex(ValueError, "required tier did not pass"):
            self.evaluate(catalog_path, bundle, verification)

        self.tearDown(); self.setUp()

        def cleanup(document):
            document["releaseRequirements"]["requiredCleanupScopes"] = ["local-cooperative"]
            document["outcomes"]["cleanup"] = [{
                "scope": "local-cooperative", "requirement": "required",
                "status": "unconfirmed", "reasonCode": "fixture-unconfirmed", "artifactIds": [],
            }]

        bundle, verification = self.bundle(cleanup)
        catalog_path, _ = self.catalog(bundle, verification)
        with self.assertRaisesRegex(ValueError, "required cleanup is not confirmed"):
            self.evaluate(catalog_path, bundle, verification)

    def test_private_catalog_and_newer_lineage_are_rejected(self):
        bundle, verification = self.bundle()
        catalog_path, _ = self.catalog(bundle, verification, visibility="private")
        with self.assertRaisesRegex(ValueError, "catalog visibility"):
            self.evaluate(catalog_path, bundle, verification)

        catalog_path, catalog = self.catalog(bundle, verification)
        catalog["extensions"]["org.nzsn.catalog-lineage"]["previousSelectionRef"]["selectionValue"] = "d" * 64
        catalog_path.write_text(json.dumps(catalog))
        with self.assertRaisesRegex(ValueError, "exact pre-run catalog selection"):
            self.evaluate(catalog_path, bundle, verification)

    def test_persistence_failure_cannot_finalize_or_link(self):
        registry = json.loads(self.registry.read_text())
        registry["commands"][0]["argvPrefix"] = [sys.executable]
        registry["commands"][0]["argvLength"] = 3
        self.registry.write_text(json.dumps(registry))
        result = subprocess.run([
            sys.executable, str(EVIDENCE / "collect.py"),
            "--store", str(self.store), "--registry", str(self.registry),
            "--command-id", "mirrors.local-no-model", "--cwd", str(self.repository),
            "--component", f"fixture={self.repository}",
            "--catalog-selection-kind", "sha256", "--catalog-selection-value", "a" * 64,
            "--max-output-bytes", "1", "--", sys.executable, "-c", "print('too large')",
        ], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertEqual(result.returncode, 0)
        staging = next((self.store / "staging").iterdir())
        with self.assertRaisesRegex(ValueError, "missing required artifacts"):
            finalize.finalize(staging, self.store)

    def test_lake_only_bundle_cannot_qualify_installed_or_release_profile(self):
        bundle, verification = self.bundle(full_profile=False)
        catalog_path, _ = self.catalog(bundle, verification)
        with self.assertRaisesRegex(ValueError, "Q bundle must contain only"):
            self.evaluate(catalog_path, bundle, verification)

    def test_release_profile_requires_separate_remote_model_check(self):
        def retain_remote_probe(scope):
            for node in scope["nodes"]:
                envelope_path = (self.store / "runs" /
                                 node["privateRunRef"]["runId"] / "envelope.json")
                envelope = json.loads(envelope_path.read_text())
                if any(command["commandId"] == "mirrors.remote-model-check"
                       for command in envelope["commands"]):
                    node["evidenceUse"] = "retained-attempt"
                    return
            raise AssertionError("fixture remote model-check run is absent")

        bundle, verification = self.bundle(mutate_scope=retain_remote_probe)
        catalog_path, _ = self.catalog(bundle, verification)
        with self.assertRaisesRegex(
                ValueError, "required command is absent: mirrors.remote-model-check"):
            self.evaluate(catalog_path, bundle, verification)

    def test_source_evidence_cannot_be_promoted_to_later_dimensions(self):
        bundle, verification = self.bundle(full_profile=False)
        catalog_path, _ = self.catalog(bundle, verification)
        with self.assertRaisesRegex(ValueError, "cannot promote evidence into observation dimension"):
            self.evaluate_profile("source-validation", catalog_path, bundle, verification)

        self.tearDown(); self.setUp()
        bundle, verification = self.bundle()
        catalog_path, catalog = self.catalog(bundle, verification)
        catalog["capabilities"][0]["observations"]["hostedCiAccepted"] = {
            "state": "accepted", "evidenceId": "run-fixture"
        }
        catalog_path.write_text(json.dumps(catalog))
        with self.assertRaisesRegex(ValueError, "cannot promote evidence into observation dimension: hostedCiAccepted"):
            self.evaluate(catalog_path, bundle, verification)

    def test_linked_scope_rejects_missing_tampered_and_malformed_distribution_inputs(self):
        bundle, verification = self.bundle()
        catalog_path, _ = self.catalog(bundle, verification)
        scope = self.scope_from_bundle(bundle)
        input_run = next(node["privateRunRef"]["runId"] for node in scope["nodes"]
                         if node["phase"] == "source-gate")
        shutil.rmtree(self.store / "runs" / input_run)
        with self.assertRaisesRegex(ValueError, "qualification bundle is missing"):
            self.evaluate(catalog_path, bundle, verification)

        self.tearDown(); self.setUp()
        bundle, verification = self.bundle()
        catalog_path, _ = self.catalog(bundle, verification)
        scope = self.scope_from_bundle(bundle)
        input_run = next(node["privateRunRef"]["runId"] for node in scope["nodes"]
                         if node["phase"] == "source-gate")
        path = self.store / "runs" / input_run / "envelope.json"
        path.write_bytes(path.read_bytes() + b" ")
        with self.assertRaisesRegex(ValueError, "bundle record identity mismatch"):
            self.evaluate(catalog_path, bundle, verification)

        self.tearDown(); self.setUp()
        bundle, verification = self.bundle(
            mutate_distribution=lambda manifest: manifest.__setitem__("componentRefs", [{}]))
        catalog_path, _ = self.catalog(bundle, verification)
        with self.assertRaisesRegex(ValueError, "invalid qualification distribution"):
            self.evaluate(catalog_path, bundle, verification)

        self.tearDown(); self.setUp()
        bundle, verification = self.bundle(mismatch_reduction_input=True)
        catalog_path, _ = self.catalog(bundle, verification)
        with self.assertRaisesRegex(ValueError, "reduction input differs"):
            self.evaluate(catalog_path, bundle, verification)

    def test_linked_scope_rejects_cycle_duplicate_credit_self_and_wrong_origin(self):
        def cycle(scope):
            origin = next(node for node in scope["nodes"]
                          if node["phase"] == "origin" and node["evidenceUse"] == "qualification-credit")
            reproduction = next(node for node in scope["nodes"] if node["phase"] == "reproduction")
            origin["dependsOnRunIds"].append(reproduction["privateRunRef"]["runId"])
        bundle, verification = self.bundle(mutate_scope=cycle)
        catalog_path, _ = self.catalog(bundle, verification)
        with self.assertRaisesRegex(ValueError, "dependency cycle"):
            self.evaluate(catalog_path, bundle, verification)

        self.tearDown(); self.setUp()
        def duplicate_credit(scope):
            node = next(node for node in scope["nodes"]
                        if node["evidenceUse"] == "retained-attempt"
                        and node["phase"] == "source-gate")
            node["evidenceUse"] = "qualification-credit"
        bundle, verification = self.bundle(mutate_scope=duplicate_credit)
        catalog_path, _ = self.catalog(bundle, verification)
        with self.assertRaisesRegex(ValueError, "duplicate qualification command credit"):
            self.evaluate(catalog_path, bundle, verification)

        self.tearDown(); self.setUp()
        def mixed_distribution(scope):
            other = next(node for node in scope["nodes"]
                         if node["phase"] == "distribution"
                         and node["evidenceUse"] == "supporting-diagnostic")
            replay = next(node for node in scope["nodes"] if node["phase"] == "replay")
            replay["distributionRunId"] = other["privateRunRef"]["runId"]
            replay["dependsOnRunIds"].append(other["privateRunRef"]["runId"])
        bundle, verification = self.bundle(mutate_scope=mixed_distribution)
        catalog_path, _ = self.catalog(bundle, verification)
        with self.assertRaisesRegex(ValueError, "different D binding"):
            self.evaluate(catalog_path, bundle, verification)

        self.tearDown(); self.setUp()
        def self_include(scope):
            run_id = f"fixture-run-{self.run_count + 1}"
            scope["nodes"].append({"phase":"installed-diagnostic",
                "evidenceUse":"supporting-diagnostic",
                "privateRunRef":{"schemaVersion":"mirrors.evidence-envelope/v1.0",
                    "runId":run_id,"envelopeSha256":"8"*64,"projectionKind":"private"},
                "publicRunRef":{"schemaVersion":"mirrors.evidence-public-summary/v1.0",
                    "runId":run_id,"envelopeSha256":"9"*64,"projectionKind":"public"},
                "distributionRunId":scope["distributionBindingRunId"],
                "dependsOnRunIds":[scope["distributionBindingRunId"]]})
        bundle, verification = self.bundle(mutate_scope=self_include)
        catalog_path, _ = self.catalog(bundle, verification)
        with self.assertRaisesRegex(ValueError, "cannot include its enclosing run"):
            self.evaluate(catalog_path, bundle, verification)

        self.tearDown(); self.setUp()
        def wrong_origin(scope):
            reproduction = next(node for node in scope["nodes"] if node["phase"] == "reproduction")
            credited = next(node for node in scope["nodes"]
                            if node["phase"] == "origin" and node["evidenceUse"] == "qualification-credit")
            retry = next(node for node in scope["nodes"]
                         if node["phase"] == "origin" and node["evidenceUse"] == "retained-attempt")
            reproduction["dependsOnRunIds"].remove(credited["privateRunRef"]["runId"])
            reproduction["dependsOnRunIds"].append(retry["privateRunRef"]["runId"])
        bundle, verification = self.bundle(mutate_scope=wrong_origin)
        catalog_path, _ = self.catalog(bundle, verification)
        with self.assertRaisesRegex(ValueError, "origin does not match"):
            self.evaluate(catalog_path, bundle, verification)

        self.tearDown(); self.setUp()
        def wrong_recovery_origin(scope):
            recovery = next(node for node in scope["nodes"] if node["phase"] == "recovery")
            credited = next(node for node in scope["nodes"]
                            if node["phase"] == "origin"
                            and node["evidenceUse"] == "qualification-credit")
            retry = next(node for node in scope["nodes"]
                         if node["phase"] == "origin"
                         and node["evidenceUse"] == "retained-attempt")
            recovery["dependsOnRunIds"].remove(credited["privateRunRef"]["runId"])
            recovery["dependsOnRunIds"].append(retry["privateRunRef"]["runId"])
        bundle, verification = self.bundle(mutate_scope=wrong_recovery_origin)
        catalog_path, _ = self.catalog(bundle, verification)
        with self.assertRaisesRegex(ValueError, "recovery receipt origin does not match"):
            self.evaluate(catalog_path, bundle, verification)

        self.tearDown(); self.setUp()
        def second_distribution_credit(scope):
            other = next(node for node in scope["nodes"]
                         if node["phase"] == "distribution"
                         and node["evidenceUse"] == "supporting-diagnostic")
            other["evidenceUse"] = "qualification-credit"
        bundle, verification = self.bundle(mutate_scope=second_distribution_credit)
        catalog_path, _ = self.catalog(bundle, verification)
        with self.assertRaisesRegex(ValueError, "only the selected D run"):
            self.evaluate(catalog_path, bundle, verification)

        self.tearDown(); self.setUp()
        def source_r0_as_installed_mutation(scope):
            origin = next(node for node in scope["nodes"] if node["phase"] == "origin"
                          and node["evidenceUse"] == "qualification-credit")
            origin["phase"] = "mutation"
        bundle, verification = self.bundle(mutate_scope=source_r0_as_installed_mutation)
        catalog_path, _ = self.catalog(bundle, verification)
        with self.assertRaisesRegex(ValueError, "wrong phase"):
            self.evaluate(catalog_path, bundle, verification)

    def test_q_public_projection_omits_private_scope_graph_and_bounds_are_closed(self):
        bundle, _verification = self.bundle()
        scope = self.scope_from_bundle(bundle)
        public = (bundle / "public-summary.json").read_text()
        self.assertNotIn(scope["scopeId"], public)
        for node in scope["nodes"]:
            self.assertNotIn(json.dumps(node["privateRunRef"]["runId"]), public)
            self.assertNotIn(node["privateRunRef"]["envelopeSha256"], public)
        oversized = copy.deepcopy(scope)
        template = oversized["nodes"][0]
        while len(oversized["nodes"]) <= 64:
            node = copy.deepcopy(template)
            run_id = f"oversized-{len(oversized['nodes'])}"
            node["privateRunRef"]["runId"] = run_id
            node["publicRunRef"]["runId"] = run_id
            oversized["nodes"].append(node)
        with self.assertRaisesRegex(ValueError, "too long"):
            qualification_scope._scope_document(finalize.canonical_json(oversized))
        too_many_edges = copy.deepcopy(scope)
        run_ids = [node["privateRunRef"]["runId"] for node in too_many_edges["nodes"]]
        for node in too_many_edges["nodes"]:
            own = node["privateRunRef"]["runId"]
            node["dependsOnRunIds"] = [run_id for run_id in run_ids if run_id != own]
        self.assertGreater(sum(len(node["dependsOnRunIds"])
                               for node in too_many_edges["nodes"]), 256)
        with self.assertRaisesRegex(ValueError, "exceeds 256 edges"):
            qualification_scope.verify_scope(too_many_edges, self.store)

    def test_command_context_binds_raw_registry_owner_environment_and_executable(self):
        bundle, _verification = self._finalized(
            [("mirrors.local-no-model", "mirrors.required")], self.components)
        envelope = json.loads((bundle / "envelope.json").read_text())
        context_artifact = next(item for item in envelope["artifacts"]
                                if item["artifactId"] == "command-context")
        original = json.loads(
            (bundle / context_artifact["location"]["path"]).read_text())
        case_number = 0

        def rejected(mutator, message):
            nonlocal case_number
            case_number += 1
            context = copy.deepcopy(original)
            mutator(context)
            raw = finalize.canonical_json(context)
            context_bundle = self.root / f"context-negative-{case_number}"
            context_bundle.mkdir()
            (context_bundle / "context.json").write_bytes(raw)
            candidate = copy.deepcopy(envelope)
            artifact = next(item for item in candidate["artifacts"]
                            if item["artifactId"] == "command-context")
            artifact["bytes"] = len(raw)
            artifact["sha256"] = hashlib.sha256(raw).hexdigest()
            artifact["location"] = {"kind":"bundle", "path":"context.json"}
            with self.assertRaisesRegex(ValueError, message):
                qualification_scope.validate_command_context(context_bundle, candidate)

        rejected(
            lambda context: context["registry"].__setitem__("sha256", "0" * 64),
            "raw registry differs from its digest",
        )
        rejected(
            lambda context: context["registry"]["selectedEntry"].__setitem__(
                "defaultTimeoutSeconds", 11),
            "selected entry differs from raw registry",
        )

        def unknown_registry_field(context):
            registry = json.loads(context["registry"]["rawUtf8"])
            registry["commands"][0]["unknown"] = True
            rendered = json.dumps(registry, sort_keys=True, separators=(",", ":"))
            context["registry"]["rawUtf8"] = rendered
            context["registry"]["sha256"] = hashlib.sha256(rendered.encode()).hexdigest()
            context["registry"]["selectedEntry"] = registry["commands"][0]
        rejected(unknown_registry_field, "unknown field")

        rejected(
            lambda context: context["command"].__setitem__("cwd", "/other"),
            "differs from E1 command record",
        )

        def absent_cwd_owner(context):
            registry = json.loads(context["registry"]["rawUtf8"])
            entry = registry["commands"][0]
            entry.pop("requiredCwd")
            entry["requiredCwdComponentId"] = "absent-component"
            rendered = json.dumps(registry, sort_keys=True, separators=(",", ":"))
            context["registry"]["rawUtf8"] = rendered
            context["registry"]["sha256"] = hashlib.sha256(rendered.encode()).hexdigest()
            context["registry"]["selectedEntry"] = entry
        rejected(absent_cwd_owner, "cwd component is absent")

        rejected(
            lambda context: context["command"]["effectiveEnvironment"].append(
                {"name":"UNREGISTERED", "value":"private"}),
            "non-allowlisted environment value",
        )
        rejected(
            lambda context: context["executable"].__setitem__("requested", "other"),
            "executable differs from argv",
        )

    def test_malformed_profile_and_unbounded_validator_output_refuse_deterministically(self):
        bundle, verification = self.bundle()
        catalog_path, _ = self.catalog(bundle, verification)
        malformed = self.root / "malformed-profiles.json"
        malformed.write_text(json.dumps({
            "schemaVersion": "mirrors.evidence-qualification-profiles/v1", "profiles": [7]
        }))
        with self.assertRaisesRegex(ValueError, "entries must be objects"):
            self.evaluate(catalog_path, bundle, verification, malformed)

        noisy = self.root / "noisy-validator"
        noisy.write_text("#!/usr/bin/env python3\nimport sys\nsys.stdout.write('x' * 70000)\n")
        noisy.chmod(0o755)
        with self.assertRaisesRegex(ValueError, "output exceeded 65536 bytes"):
            catalog_links.evaluate_catalog_link(
                catalog_path, bundle, verification, "release-candidate",
                catalog_links.DEFAULT_PROFILES, noisy,
            )


if __name__ == "__main__":
    unittest.main()
