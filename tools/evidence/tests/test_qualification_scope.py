from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

EVIDENCE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(EVIDENCE))

import qualification_scope as scope_module  # noqa: E402

SELECTION_A = "a" * 64
SELECTION_B = "b" * 64
LOCAL_COMPONENTS = [
    {"componentId": "mirrorecma", "revision": "1" * 40, "dirty": False},
    {"componentId": "mirrors", "revision": "2" * 40, "dirty": False},
]
GATE_COMPONENTS = LOCAL_COMPONENTS + [
    {"componentId": "mirrorgate", "revision": "3" * 40, "dirty": False},
]


def run_ref(run_id: str, projection: str) -> dict:
    if projection == "private":
        schema = "mirrors.evidence-envelope/v1.0"
    else:
        schema = "mirrors.evidence-public-summary/v1.0"
    return {"schemaVersion": schema, "runId": run_id, "envelopeSha256": "c" * 64,
            "projectionKind": projection}


def envelope(run_id: str, command_id: str, components: list[dict], selection: str,
             status: str = "qualified") -> dict:
    return {
        "runId": run_id,
        "catalogSelectionRef": {"schemaVersion": "mirrors.framework-catalog/v1",
                                "selectionKind": "sha256", "selectionValue": selection},
        "qualification": {"status": status},
        "commands": [{"commandId": command_id, "tierId": "tier", "requirement": "required",
                      "argv": ["x"], "cwd": "/tmp", "exit": {"code": 0, "kind": "code"}}],
        "components": components,
        "artifacts": [],
        "outcomes": {"cleanup": []},
        "tiers": [],
    }


class ScopeMultiBindingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.store = Path(self.temporary.name)
        (self.store / "runs").mkdir(mode=0o700)
        self.envelopes: dict[str, dict] = {}
        self.bindings: dict[str, dict] = {}

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def add_run(self, run_id: str, command_id: str, components: list[dict], selection: str,
                binding: bool = False, status: str = "qualified") -> None:
        (self.store / "runs" / run_id).mkdir(mode=0o700)
        self.envelopes[run_id] = envelope(run_id, command_id, components, selection, status)
        if binding:
            self.bindings[run_id] = {"profileId": "profile", "componentRefs": components,
                                     "distributionManifestSha256": "d" * 64,
                                     "cacheIndexSha256": "e" * 64}

    def node(self, run_id: str, phase: str, distribution: str | None = None,
             depends: tuple[str, ...] = (), evidence: str = "qualification-credit") -> dict:
        return {"phase": phase, "evidenceUse": evidence,
                "privateRunRef": run_ref(run_id, "private"),
                "publicRunRef": run_ref(run_id, "public"),
                "distributionRunId": distribution, "dependsOnRunIds": list(depends)}

    def verify(self, scope: dict) -> dict:
        def fake_envelope(bundle, expected, public):
            return self.envelopes[bundle.name], {}

        with patch.object(scope_module, "_verified_envelope", fake_envelope), \
                patch.object(scope_module, "validate_command_context",
                             lambda bundle, envelope: {}), \
                patch.object(scope_module, "_distribution_binding",
                             lambda bundle, envelope, selected: self.bindings[bundle.name]):
            return scope_module.verify_scope(scope, self.store)

    def scope(self, bindings: list[str], nodes: list[dict], selection: str = SELECTION_A) -> dict:
        return {"schemaVersion": "mirrors.qualification-scope/v2",
                "scopeId": "multi-binding-test", "qualificationClass": "local-candidate",
                "selectedCatalogRef": {"schemaVersion": "mirrors.framework-catalog/v1",
                                       "selectionKind": "sha256", "selectionValue": selection},
                "distributionBindingRunIds": bindings, "nodes": nodes}

    def test_two_bindings_credit_their_own_nodes(self) -> None:
        self.add_run("run-local-d", "framework.install-diagnostics", LOCAL_COMPONENTS,
                     SELECTION_A, binding=True)
        self.add_run("run-gate-d", "framework.install-diagnostics-gate", GATE_COMPONENTS,
                     SELECTION_A, binding=True)
        self.add_run("run-replay", "framework.replay-correct", LOCAL_COMPONENTS, SELECTION_A)
        self.add_run("run-gate-mutation", "framework.mutation-gate", GATE_COMPONENTS, SELECTION_A)
        scope = self.scope(["run-local-d", "run-gate-d"], [
            self.node("run-local-d", "distribution"),
            self.node("run-gate-d", "distribution"),
            self.node("run-replay", "replay", "run-local-d", ("run-local-d",)),
            self.node("run-gate-mutation", "mutation", "run-gate-d", ("run-gate-d",)),
        ])
        result = self.verify(scope)
        self.assertEqual(result["status"], "verified")
        self.assertEqual([binding["runId"] for binding in result["bindings"]],
                         ["run-local-d", "run-gate-d"])
        self.assertEqual(result["bindings"][1]["componentIds"],
                         ["mirrorecma", "mirrors", "mirrorgate"])
        self.assertEqual(sorted(command["commandId"] for command in result["commands"]),
                         ["framework.install-diagnostics", "framework.install-diagnostics-gate",
                          "framework.mutation-gate", "framework.replay-correct"])
        self.assertNotIn("distributionManifestSha256", result)

    def test_single_binding_still_reports_singular_digests(self) -> None:
        self.add_run("run-local-d", "framework.install-diagnostics", LOCAL_COMPONENTS,
                     SELECTION_A, binding=True)
        self.add_run("run-replay", "framework.replay-correct", LOCAL_COMPONENTS, SELECTION_A)
        scope = self.scope(["run-local-d"], [
            self.node("run-local-d", "distribution"),
            self.node("run-replay", "replay", "run-local-d", ("run-local-d",)),
        ])
        result = self.verify(scope)
        self.assertEqual(result["distributionManifestSha256"], "d" * 64)
        self.assertEqual(result["cacheIndexSha256"], "e" * 64)
        self.assertEqual(result["distributionBindingRunId"], "run-local-d")

    def test_node_matching_no_binding_is_rejected(self) -> None:
        self.add_run("run-local-d", "framework.install-diagnostics", LOCAL_COMPONENTS,
                     SELECTION_A, binding=True)
        self.add_run("run-orphan", "framework.replay-correct", LOCAL_COMPONENTS, SELECTION_A)
        scope = self.scope(["run-local-d"], [
            self.node("run-local-d", "distribution"),
            self.node("run-orphan", "replay", "run-absent"),
        ])
        with self.assertRaisesRegex(ValueError, "lacks an exact D binding"):
            self.verify(scope)

    def test_node_matching_wrong_binding_is_rejected(self) -> None:
        self.add_run("run-local-d", "framework.install-diagnostics", LOCAL_COMPONENTS,
                     SELECTION_A, binding=True)
        self.add_run("run-gate-mutation", "framework.mutation-gate", GATE_COMPONENTS, SELECTION_A)
        scope = self.scope(["run-local-d"], [
            self.node("run-local-d", "distribution"),
            self.node("run-gate-mutation", "mutation", "run-local-d", ("run-local-d",)),
        ])
        with self.assertRaisesRegex(ValueError, "components differ from bound distribution"):
            self.verify(scope)

    def test_credited_node_using_non_credit_binding_is_rejected(self) -> None:
        self.add_run("run-local-d", "framework.install-diagnostics", LOCAL_COMPONENTS,
                     SELECTION_A, binding=True)
        self.add_run("run-gate-d", "framework.install-diagnostics-gate", GATE_COMPONENTS,
                     SELECTION_A, binding=True)
        self.add_run("run-gate-mutation", "framework.mutation-gate", GATE_COMPONENTS, SELECTION_A)
        scope = self.scope(["run-local-d"], [
            self.node("run-local-d", "distribution"),
            self.node("run-gate-d", "distribution", evidence="supporting-diagnostic"),
            self.node("run-gate-mutation", "mutation", "run-gate-d", ("run-gate-d",)),
        ])
        with self.assertRaisesRegex(ValueError, "non-credited D binding"):
            self.verify(scope)

    def test_undeclared_credited_distribution_is_rejected(self) -> None:
        self.add_run("run-local-d", "framework.install-diagnostics", LOCAL_COMPONENTS,
                     SELECTION_A, binding=True)
        self.add_run("run-gate-d", "framework.install-diagnostics-gate", GATE_COMPONENTS,
                     SELECTION_A, binding=True)
        scope = self.scope(["run-local-d"], [
            self.node("run-local-d", "distribution"),
            self.node("run-gate-d", "distribution"),
        ])
        with self.assertRaisesRegex(ValueError, "only declared distribution bindings"):
            self.verify(scope)

    def test_duplicate_command_credit_is_rejected(self) -> None:
        self.add_run("run-local-d", "framework.install-diagnostics", LOCAL_COMPONENTS,
                     SELECTION_A, binding=True)
        self.add_run("run-replay-one", "framework.replay-correct", LOCAL_COMPONENTS, SELECTION_A)
        self.add_run("run-replay-two", "framework.replay-correct", LOCAL_COMPONENTS, SELECTION_A)
        scope = self.scope(["run-local-d"], [
            self.node("run-local-d", "distribution"),
            self.node("run-replay-one", "replay", "run-local-d", ("run-local-d",)),
            self.node("run-replay-two", "replay", "run-local-d", ("run-local-d",)),
        ])
        with self.assertRaisesRegex(ValueError, "duplicate qualification command credit"):
            self.verify(scope)

    def test_mixed_selection_is_rejected(self) -> None:
        self.add_run("run-local-d", "framework.install-diagnostics", LOCAL_COMPONENTS,
                     SELECTION_A, binding=True)
        self.add_run("run-replay", "framework.replay-correct", LOCAL_COMPONENTS, SELECTION_B)
        scope = self.scope(["run-local-d"], [
            self.node("run-local-d", "distribution"),
            self.node("run-replay", "replay", "run-local-d", ("run-local-d",)),
        ])
        with self.assertRaisesRegex(ValueError, "different C0 catalog"):
            self.verify(scope)

    def reproduction_bundle(self, run_id: str, reference: dict, relative: str) -> bytes:
        payload = json.dumps({"schema": "mirrorecma.reproduction-bundle/v1",
                              "evidenceLinks": {"runRef": reference}}).encode()
        path = self.store / "runs" / run_id / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(payload)
        return payload

    def test_reproduction_may_bind_a_credited_replay_r0(self) -> None:
        import hashlib
        self.add_run("run-local-d", "framework.install-diagnostics", LOCAL_COMPONENTS,
                     SELECTION_A, binding=True)
        self.add_run("run-replay", "framework.replay-faulty", LOCAL_COMPONENTS, SELECTION_A)
        self.add_run("run-reproduction", "framework.reproduction", LOCAL_COMPONENTS, SELECTION_A)
        relative = "artifacts/private/attachment-000.bin"
        payload = self.reproduction_bundle("run-reproduction", run_ref("run-replay", "private"), relative)
        self.envelopes["run-reproduction"]["artifacts"] = [{
            "artifactId": "reproduction-bundle", "role": "reproduction-input",
            "requirement": "required", "location": {"kind": "bundle", "path": relative},
            "bytes": len(payload), "sha256": hashlib.sha256(payload).hexdigest()}]
        scope = self.scope(["run-local-d"], [
            self.node("run-local-d", "distribution"),
            self.node("run-replay", "replay", "run-local-d", ("run-local-d",)),
            self.node("run-reproduction", "reproduction", "run-local-d",
                      ("run-local-d", "run-replay")),
        ])
        result = self.verify(scope)
        self.assertEqual(result["status"], "verified")
        self.assertEqual(sorted(command["commandId"] for command in result["commands"]),
                         ["framework.install-diagnostics", "framework.replay-faulty",
                          "framework.reproduction"])

    def test_lease_reproduction_uses_its_own_installed_origin_phase(self) -> None:
        import hashlib
        self.add_run("run-d", "framework.install-diagnostics", LOCAL_COMPONENTS,
                     SELECTION_A, binding=True)
        self.add_run("run-lease-r0", "framework.lease-origin-installed", LOCAL_COMPONENTS, SELECTION_A)
        self.add_run("run-lease-r1", "framework.reproduction-lease", LOCAL_COMPONENTS, SELECTION_A)
        relative = "artifacts/private/bundle.json"
        payload = self.reproduction_bundle("run-lease-r1", run_ref("run-lease-r0", "private"), relative)
        self.envelopes["run-lease-r1"]["artifacts"] = [{
            "artifactId": "bundle", "role": "reproduction-input", "requirement": "required",
            "location": {"kind": "bundle", "path": relative}, "bytes": len(payload),
            "sha256": hashlib.sha256(payload).hexdigest()}]
        document = self.scope(["run-d"], [
            self.node("run-d", "distribution"),
            self.node("run-lease-r0", "origin", "run-d", ("run-d",)),
            self.node("run-lease-r1", "reproduction", "run-d", ("run-d", "run-lease-r0")),
        ])
        self.assertEqual(self.verify(document)["status"], "verified")
        document["nodes"][1]["phase"] = "replay"
        with self.assertRaisesRegex(ValueError, "wrong phase"):
            self.verify(document)

    def test_reproduction_rejects_a_mismatched_r0_reference(self) -> None:
        self.add_run("run-local-d", "framework.install-diagnostics", LOCAL_COMPONENTS,
                     SELECTION_A, binding=True)
        self.add_run("run-replay", "framework.replay-faulty", LOCAL_COMPONENTS, SELECTION_A)
        self.add_run("run-reproduction", "framework.reproduction", LOCAL_COMPONENTS, SELECTION_A)
        other = run_ref("run-other", "private")
        relative = "artifacts/private/attachment-000.bin"
        payload = self.reproduction_bundle("run-reproduction", other, relative)
        self.envelopes["run-reproduction"]["artifacts"] = [{
            "artifactId": "reproduction-bundle", "role": "reproduction-input",
            "requirement": "required", "location": {"kind": "bundle", "path": relative},
            "bytes": len(payload), "sha256": __import__("hashlib").sha256(payload).hexdigest()}]
        scope = self.scope(["run-local-d"], [
            self.node("run-local-d", "distribution"),
            self.node("run-replay", "replay", "run-local-d", ("run-local-d",)),
            self.node("run-reproduction", "reproduction", "run-local-d",
                      ("run-local-d", "run-replay")),
        ])
        with self.assertRaisesRegex(ValueError, "origin does not match"):
            self.verify(scope)

    def test_reproduction_without_an_r0_dependency_is_rejected(self) -> None:
        self.add_run("run-local-d", "framework.install-diagnostics", LOCAL_COMPONENTS,
                     SELECTION_A, binding=True)
        self.add_run("run-reproduction", "framework.reproduction", LOCAL_COMPONENTS, SELECTION_A)
        scope = self.scope(["run-local-d"], [
            self.node("run-local-d", "distribution"),
            self.node("run-reproduction", "reproduction", "run-local-d", ("run-local-d",)),
        ])
        with self.assertRaisesRegex(ValueError, "credited R0 run"):
            self.verify(scope)

    def test_registered_cwd_matches_environment_owner_with_subdirectory(self) -> None:
        flat = {"requiredCwdEnvironmentName": "MIRRORS_INSTALLED_RUNTIME"}
        nested = {"requiredCwdEnvironmentName": "MIRRORS_INSTALLED_GATE_RUNTIME",
                  "requiredCwdSubdirectory": "gate/mirrorgate-supervisor"}
        self.assertTrue(scope_module.command_cwd_matches({}, {}, "/tmp/anywhere"))
        self.assertTrue(scope_module.command_cwd_matches(
            flat, {"MIRRORS_INSTALLED_RUNTIME": "/tmp/runtime"}, "/tmp/runtime"))
        self.assertFalse(scope_module.command_cwd_matches(
            flat, {"MIRRORS_INSTALLED_RUNTIME": "/tmp/runtime"}, "/tmp/runtime/sub"))
        self.assertTrue(scope_module.command_cwd_matches(
            nested, {"MIRRORS_INSTALLED_GATE_RUNTIME": "/tmp/gate"},
            "/tmp/gate/gate/mirrorgate-supervisor"))
        self.assertFalse(scope_module.command_cwd_matches(
            nested, {"MIRRORS_INSTALLED_GATE_RUNTIME": "/tmp/gate"}, "/tmp/gate"))
        self.assertFalse(scope_module.command_cwd_matches(
            nested, {}, "/tmp/gate/gate/mirrorgate-supervisor"))

    def test_v1_scope_is_still_readable(self) -> None:
        document = json.dumps({
            "schemaVersion": "mirrors.qualification-scope/v1",
            "scopeId": "legacy", "qualificationClass": "local-candidate",
            "selectedCatalogRef": {"schemaVersion": "mirrors.framework-catalog/v1",
                                   "selectionKind": "sha256", "selectionValue": SELECTION_A},
            "distributionBindingRunId": "run-local-d",
            "nodes": [self.node("run-local-d", "distribution")],
        }).encode()
        parsed = scope_module._scope_document(document)
        self.assertEqual(parsed["scopeId"], "legacy")
        self.assertEqual(scope_module.scope_binding_ids(parsed), ["run-local-d"])

    def test_unknown_scope_version_is_rejected(self) -> None:
        document = json.dumps({"schemaVersion": "mirrors.qualification-scope/v9"}).encode()
        with self.assertRaisesRegex(ValueError, "unsupported qualification scope version"):
            scope_module._scope_document(document)


if __name__ == "__main__":
    unittest.main()
