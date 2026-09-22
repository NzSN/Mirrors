from __future__ import annotations

import json
import hashlib
import os
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path


EVIDENCE = Path(__file__).resolve().parents[1]
COLLECTOR = EVIDENCE / "collect.py"


class CollectorTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.repository = self.root / "repository"
        self.repository.mkdir()
        subprocess.run(["git", "init", "-q", str(self.repository)], check=True)
        subprocess.run(["git", "-C", str(self.repository), "config", "user.email", "fixture@example.invalid"], check=True)
        subprocess.run(["git", "-C", str(self.repository), "config", "user.name", "Fixture"], check=True)
        subprocess.run(["git", "-C", str(self.repository), "remote", "add", "origin",
                        "https://example.invalid/fixture.git"], check=True)
        (self.repository / "source.txt").write_text("source\n", encoding="utf-8")
        catalog = self.repository / "catalog"
        catalog.mkdir()
        (catalog / "framework-catalog.json").write_text("{}\n", encoding="utf-8")
        subprocess.run(["git", "-C", str(self.repository), "add", "."], check=True)
        subprocess.run(["git", "-C", str(self.repository), "commit", "-qm", "fixture"], check=True)
        self.store = self.root / "store"
        self.registry = self.root / "commands.json"

    def tearDown(self):
        self.temporary.cleanup()

    def registry_for(self, command_id: str, prefix: list[str], requirement: str = "required"):
        self.registry.write_text(json.dumps({
            "schemaVersion": "mirrors.evidence-command-registry/v1",
            "commands": [{
                "commandId": command_id,
                "tierId": "fixture.tier",
                "requirement": requirement,
                "argvPrefix": prefix,
                "defaultTimeoutSeconds": 10,
                "catalogComponentId": "fixture",
                "catalogPath": "catalog/framework-catalog.json",
            }],
        }), encoding="utf-8")

    def attachment_plan(self, root: Path, attachments: list[dict], *,
                        adapter="none", adapter_artifact=None,
                        application=None) -> Path:
        path = self.root / f"attachment-plan-{len(list(self.root.glob('attachment-plan-*')))}.json"
        path.write_text(json.dumps({
            "schemaVersion": "mirrors.evidence-attachment-plan/v1",
            "sourceRoot": str(root),
            "application": application,
            "adapter": {"kind": adapter, "artifactId": adapter_artifact},
            "attachments": attachments,
        }), encoding="utf-8")
        return path

    def enable_attachments(self, root_arg_index: int):
        document = json.loads(self.registry.read_text())
        document["commands"][0]["attachmentsAllowed"] = True
        document["commands"][0]["attachmentRootArgIndex"] = root_arg_index
        self.registry.write_text(json.dumps(document))

    def valid_gate_receipt(self, application="lease-service"):
        denominator = {"work-queue":9,"persistent-transfer":4,"lease-service":4}[application]
        identity = lambda name, digit: {"id":name,"sha256":digit * 64}
        expected = lambda index: {"kind":"behavioral_mismatch","code":"replay_mismatch",
            "traceIndex":0,"stateIndex":index + 1,"action":"step"}
        cleanup = [{"scope":"local-cooperative","requirement":"required","status":"confirmed"},
                   {"scope":"gate-physical","requirement":"required","status":"confirmed"}]
        physical = {"status":"confirmed","remainingResources":[],"failures":[]}
        cases = [{"id":f"mutant-{index}","implementation":identity(f"impl-{index}","a"),
                  "expected":expected(index),"probeIds":["probe"]}
                 for index in range(denominator)]
        protected = {"suite":identity("suite","1"),"model":identity("model","2"),
            "generatedInterface":identity("interface","3"),"corpus":identity("corpus","4"),
            "acceptance":identity("acceptance","5"),"observer":identity("observer","6"),
            "correctImplementation":identity("correct","7"),
            "probes":[identity("probe","8")],"executionProfiles":[identity("gate-profile","9")]}
        mutants = [{"id":case["id"],"testedPath":"gate","disposition":"attempted",
            "classification":"killed_by_behavioral_mismatch","expected":case["expected"],
            "observed":case["expected"],"cleanup":cleanup,"probe":{"status":"passed"},
            "durationMs":1} for case in cases]
        controls = [{"id":"crash","outcome":"failed","cleanup":physical},
                    {"id":"hang","outcome":"timedOut","cleanup":physical},
                    {"id":"cancel","outcome":"cancelled","cleanup":physical}]
        extras = (["observer-shadow-unchecked","observer-shadow-enforced",
                   "observer-throws","observer-invalid"] if application == "lease-service" else [])
        variants = ["correct", *[case["id"] for case in cases],
                    "crash", "hang", "cancel", *extras]
        fidelity = {"schema":"mirrorgate.observer-fidelity/v1",
            "method":"actual-facts-vs-observation","probeIdentity":protected["probes"][0],
            "normalCases":"passed"}
        if application == "lease-service":
            fidelity.update({"shadowControl":{"reportedReplay":"passed",
                "actualFactsComparison":{"status":"failed","code":"probe_observer_divergence",
                                         "enforcedOutcome":"failed"}},
                "observerError":"implementation_failure","invalidObservation":"codec_failure"})
        else:
            fidelity["shadowControl"] = {"status":"not_applicable",
                "reason":"real Gate shadow negative is retained by lease-service"}
        revision = subprocess.check_output(
            ["git","-C",str(self.repository),"rev-parse","HEAD"], text=True).strip()
        component = {"componentId":"fixture","repository":"https://example.invalid/fixture.git",
                     "revision":revision,"dirty":False}
        return {"schema":"mirrorgate.application-validation/v2","application":application,
            "authoring":"not exercised; source submissions","node":"v24.15.0",
            "runnerSha256":"a"*64,"publicContractSha256":"b"*64,"model":"c"*64,
            "referenceImplementation":"d"*64,"trace":"e"*64,"interface":"fixture-interface",
            "catalog":{"selectionRef":{"schemaVersion":"mirrors.framework-catalog/v1",
                "selectionKind":"git-revision","selectionValue":revision},
                "combinationId":"fixture-combination","componentRefs":[component]},
            "protected":protected,
            "campaignDefinition":{"id":f"{application}.campaign/v1","revision":1,
                "denominator":denominator,"orderedCaseIds":[case["id"] for case in cases],
                "cases":cases},
            "mutationCampaign":{"schema":"mirrorecma.mutation-campaign-result/v1",
                "campaignId":f"{application}.campaign/v1","revision":1,"testedPath":"gate",
                "denominator":denominator,"requiredOnPath":denominator,"status":"complete",
                "acceptance":{"status":"met","reasonCodes":[]},
                "baseline":{"id":"correct","testedPath":"gate","disposition":"attempted",
                    "classification":"survived","cleanup":cleanup,"probe":{"status":"passed"},
                    "durationMs":1},"mutants":mutants},
            "fidelity":fidelity,"controls":controls,
            "outcomes":[{"variant":variant,"fixedFixtureProbe":"enforced",
                         "outcome":"passed","receipt":{"cleanup":physical}}
                        for variant in variants]}

    def valid_local_aggregate_receipt(self):
        sys.path.insert(0, str(EVIDENCE))
        import collect
        revision = subprocess.check_output(
            ["git","-C",str(self.repository),"rev-parse","HEAD"], text=True).strip()
        component = {"componentId":"fixture","repository":"https://example.invalid/fixture.git",
                     "revision":revision,"dirty":False}
        selection = {"schemaVersion":"mirrors.framework-catalog/v1",
                     "selectionKind":"git-revision","selectionValue":revision}
        cleanup = [{"scope":"local-cooperative","requirement":"required",
                    "status":"confirmed"}]
        campaigns = []
        for application, expected in collect.LOCAL_CAMPAIGNS.items():
            mutation_results = [{"id":case_id,
                "classification":"killed_by_behavioral_mismatch",
                "disposition":"attempted","cleanup":cleanup,
                "probe":{"status":"passed","facts":{}}}
                for case_id, _trace, _state, _action in expected]
            variants = [("correct","passed",None)] + [
                (case_id,"mismatch",{"code":"replay_mismatch","traceIndex":trace,
                                      "stateIndex":state,"action":action})
                for case_id, trace, state, action in expected] + [
                ("crash","failed",None),("hang","timedOut",None),
                ("cancel","cancelled",None)]
            detailed = []
            for variant, classification, mismatch in variants:
                result = {"variant":variant,"classification":classification,
                    "cleanup":{"status":"confirmed","remainingEntries":[]},
                    "probe":{"status":"passed","facts":{}},
                    "suiteResult":{"outcome":classification,"cleanup":{
                        "status":"succeeded","quiescence":"confirmed"}}}
                if mismatch is not None:
                    result["expectedFirstMismatch"] = mismatch
                detailed.append(result)
            campaigns.append({"schema":"mirrorecma.application-validation/v2",
                "application":application,"suiteId":f"{application}/v1",
                "tier":"checked-deterministic-witness",
                "generatedAt":"2026-09-22T00:00:00.000Z","node":"v24.15.0",
                "identities":{key:str(index) * 64 for index, key in enumerate((
                    "model","implementation","harness","interface","applicationConfig",
                    "mirror","trace"), start=1)},
                "mutationCampaign":{"id":f"{application}.campaign/v1","revision":1,
                    "status":"complete","acceptance":{"status":"met","reasonCodes":[]},
                    "denominator":len(expected),"requiredOnPath":len(expected),
                    "results":mutation_results},
                "measurements":{"setupTime":"not measured"},"results":detailed})
        return ({"schema":"mirrorecma.application-campaign-aggregate/v1",
                 "tier":"installed-prevalidated","applications":list(collect.LOCAL_CAMPAIGNS),
                 "denominator":17,"acceptance":{"status":"met"},
                 "cleanup":{"scope":"local-cooperative","status":"confirmed","cases":29},
                 "framework":{"catalogSelectionRef":selection,"componentRefs":[component],
                    "installedRegistrySha256":"a"*64,"frameworkInputSha256":"b"*64,
                    "installationSchema":"mirrorecma.installed-framework-binding/v1"},
                 "campaigns":campaigns}, selection, [component])

    def invoke(self, command_id: str, command: list[str], *options: str, timeout: float = 10):
        return subprocess.run(
            [
                sys.executable,
                str(COLLECTOR),
                "--store", str(self.store),
                "--registry", str(self.registry),
                "--command-id", command_id,
                "--cwd", str(self.repository),
                "--component", f"fixture={self.repository}",
                *options,
                "--",
                *command,
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
        )

    def envelope(self):
        envelopes = list((self.store / "staging").glob("*/envelope.staging.json"))
        self.assertEqual(len(envelopes), 1)
        return json.loads(envelopes[0].read_text(encoding="utf-8")), envelopes[0].parent

    def test_exit_zero_streams_and_stages(self):
        self.registry_for("fixture.zero", [sys.executable])
        result = self.invoke(
            "fixture.zero",
            [sys.executable, "-c", "import sys; print('out'); print('err', file=sys.stderr)"],
        )
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertEqual(result.stdout, b"out\n")
        self.assertIn(b"err\n", result.stderr)
        envelope, root = self.envelope()
        self.assertEqual(envelope["commands"][0]["exit"], {"kind": "code", "code": 0})
        self.assertEqual(envelope["outcomes"]["behavior"]["status"], "passed")
        self.assertEqual(envelope["outcomes"]["persistence"]["status"], "incomplete")
        self.assertEqual((root / "artifacts/private/stdout.log").read_bytes(), b"out\n")
        self.assertEqual((root / "artifacts/private/stderr.log").read_bytes(), b"err\n")

    def test_nonzero_exit_is_preserved(self):
        self.registry_for("fixture.seven", [sys.executable])
        result = self.invoke("fixture.seven", [sys.executable, "-c", "raise SystemExit(7)"])
        self.assertEqual(result.returncode, 7)
        envelope, _ = self.envelope()
        self.assertEqual(envelope["commands"][0]["exit"], {"kind": "code", "code": 7})
        self.assertEqual(envelope["outcomes"]["behavior"]["status"], "failed")

    def test_child_signal_is_recorded_and_propagated(self):
        self.registry_for("fixture.signal", [sys.executable])
        result = self.invoke(
            "fixture.signal",
            [sys.executable, "-c", "import os,signal; os.kill(os.getpid(), signal.SIGTERM)"],
        )
        self.assertEqual(result.returncode, -signal.SIGTERM)
        envelope, _ = self.envelope()
        self.assertEqual(envelope["commands"][0]["exit"], {"kind": "signal", "signal": "SIGTERM"})

    def test_timeout_is_bounded_and_preserves_child_signal(self):
        self.registry_for("fixture.timeout", [sys.executable])
        result = self.invoke(
            "fixture.timeout",
            [sys.executable, "-c", "import time; time.sleep(30)"],
            "--timeout-seconds", "0.1",
        )
        self.assertEqual(result.returncode, -signal.SIGTERM)
        envelope, _ = self.envelope()
        self.assertEqual(envelope["outcomes"]["behavior"]["classification"]["code"], "timeout")

    def test_timeout_kills_descendant_that_retains_output_pipes(self):
        self.registry_for("fixture.pipe-descendant", [sys.executable])
        program = (
            "import subprocess,sys; "
            "subprocess.Popen([sys.executable,'-c','import time; time.sleep(30)']); "
            "raise SystemExit(0)"
        )
        started = time.monotonic()
        result = self.invoke(
            "fixture.pipe-descendant",
            [sys.executable, "-c", program],
            "--timeout-seconds", "0.5",
        )
        self.assertLess(time.monotonic() - started, 3)
        self.assertEqual(result.returncode, 0)
        envelope, _ = self.envelope()
        self.assertEqual(envelope["outcomes"]["behavior"]["classification"]["code"], "timeout")

    def test_timeout_bounds_leader_that_closes_both_pipes(self):
        self.registry_for("fixture.closed-pipes", [sys.executable])
        program = "import os,time; os.close(1); os.close(2); time.sleep(30)"
        started = time.monotonic()
        result = self.invoke(
            "fixture.closed-pipes",
            [sys.executable, "-c", program],
            "--timeout-seconds", "0.1",
        )
        self.assertLess(time.monotonic() - started, 3)
        self.assertEqual(result.returncode, -signal.SIGTERM)
        envelope, _ = self.envelope()
        self.assertEqual(envelope["outcomes"]["behavior"]["classification"]["code"], "timeout")

    def test_unavailable_executable_is_not_run(self):
        missing = str(self.root / "not-an-executable")
        self.registry_for("fixture.unavailable", [missing])
        result = self.invoke("fixture.unavailable", [missing])
        self.assertEqual(result.returncode, 127)
        envelope, _ = self.envelope()
        self.assertEqual(envelope["commands"][0]["exit"], {"kind": "not-started"})
        self.assertEqual(envelope["tiers"][0]["status"], "unavailable")

    def test_oversized_output_is_not_truncated_and_called_complete(self):
        self.registry_for("fixture.large", [sys.executable])
        result = self.invoke(
            "fixture.large",
            [sys.executable, "-c", "print('abcdefghij', end='')"],
            "--max-output-bytes", "4",
        )
        self.assertEqual(result.returncode, 0)
        envelope, root = self.envelope()
        self.assertEqual(envelope["outcomes"]["persistence"]["status"], "failed")
        self.assertIn("command-stdout", envelope["outcomes"]["persistence"]["missingArtifactIds"])
        self.assertFalse((root / "artifacts/private/stdout.log").exists())

    def test_component_change_during_collection_is_incomplete(self):
        self.registry_for("fixture.change", [sys.executable])
        result = self.invoke(
            "fixture.change",
            [sys.executable, "-c", "from pathlib import Path; Path('source.txt').write_text('changed\\n')"],
        )
        self.assertEqual(result.returncode, 0)
        envelope, root = self.envelope()
        self.assertEqual(envelope["outcomes"]["persistence"]["reasonCode"], "component-changed-during-collection")
        snapshots = json.loads((root / "artifacts/private/component-snapshots.json").read_text())
        self.assertTrue(snapshots["changed"])
        self.assertFalse(snapshots["before"][0]["dirty"])
        self.assertTrue(snapshots["after"][0]["dirty"])

    def test_collector_interrupt_is_forwarded_and_staged(self):
        self.registry_for("fixture.interrupt", [sys.executable])
        started_marker = self.root / "child-started"
        process = subprocess.Popen(
            [
                sys.executable, str(COLLECTOR),
                "--store", str(self.store), "--registry", str(self.registry),
                "--command-id", "fixture.interrupt", "--cwd", str(self.repository),
                "--component", f"fixture={self.repository}", "--",
                sys.executable, "-c", f"from pathlib import Path; import time; Path({str(started_marker)!r}).write_text('yes'); time.sleep(30)",
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        deadline = time.monotonic() + 5
        while not started_marker.exists() and time.monotonic() < deadline:
            time.sleep(0.02)
        self.assertTrue(started_marker.exists())
        process.send_signal(signal.SIGINT)
        process.communicate(timeout=5)
        self.assertEqual(process.returncode, -signal.SIGINT)
        envelope, _ = self.envelope()
        self.assertEqual(envelope["commands"][0]["exit"], {"kind": "signal", "signal": "SIGINT"})

    def test_write_failure_does_not_replace_child_exit(self):
        self.registry_for("fixture.write-failure", [sys.executable])
        self.store.write_text("not a directory", encoding="utf-8")
        result = self.invoke("fixture.write-failure", [sys.executable, "-c", "raise SystemExit(7)"])
        self.assertEqual(result.returncode, 7)
        self.assertIn(b"evidence collection persistence failed", result.stderr)

    def test_registry_prefix_is_enforced_before_execution(self):
        marker = self.root / "must-not-exist"
        self.registry_for("fixture.bound", ["expected-program"])
        result = self.invoke(
            "fixture.bound",
            [sys.executable, "-c", f"from pathlib import Path; Path({str(marker)!r}).write_text('bad')"],
        )
        self.assertEqual(result.returncode, 2)
        self.assertFalse(marker.exists())

    def test_registered_working_directory_is_enforced_before_execution(self):
        marker = self.root / "must-not-exist"
        self.registry_for("fixture.cwd", [sys.executable])
        document = json.loads(self.registry.read_text())
        document["commands"][0]["requiredCwd"] = str(self.root / "different")
        self.registry.write_text(json.dumps(document))
        result = self.invoke(
            "fixture.cwd",
            [sys.executable, "-c", f"from pathlib import Path; Path({str(marker)!r}).write_text('bad')"],
        )
        self.assertEqual(result.returncode, 2)
        self.assertFalse(marker.exists())

    def test_registered_working_directory_environment_is_exact_and_private(self):
        self.registry_for("fixture.cwd-environment", [sys.executable])
        document = json.loads(self.registry.read_text())
        document["commands"][0]["requiredEnvironmentNames"] = ["FIXTURE_ACTIVE_ROOT"]
        document["commands"][0]["requiredCwdEnvironmentName"] = "FIXTURE_ACTIVE_ROOT"
        self.registry.write_text(json.dumps(document))
        environment = os.environ.copy(); environment["FIXTURE_ACTIVE_ROOT"] = str(self.repository)
        result = subprocess.run([
            sys.executable,str(COLLECTOR),"--store",str(self.store),
            "--registry",str(self.registry),"--command-id","fixture.cwd-environment",
            "--cwd",str(self.repository),"--component",f"fixture={self.repository}",
            "--",sys.executable,"-c","print('yes')"],env=environment,
            stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        self.assertEqual(result.returncode,0,result.stderr.decode())
        _envelope, staging = self.envelope()
        context = json.loads((staging / "artifacts/private/command-context.json").read_text())
        self.assertEqual(context["command"]["effectiveEnvironment"], [{
            "name":"FIXTURE_ACTIVE_ROOT","value":str(self.repository)}])
        self.tearDown(); self.setUp()
        marker = self.root / "must-not-exist"
        self.registry_for("fixture.cwd-environment", [sys.executable])
        document = json.loads(self.registry.read_text())
        document["commands"][0]["requiredEnvironmentNames"] = ["FIXTURE_ACTIVE_ROOT"]
        document["commands"][0]["requiredCwdEnvironmentName"] = "FIXTURE_ACTIVE_ROOT"
        self.registry.write_text(json.dumps(document))
        environment = os.environ.copy(); environment["FIXTURE_ACTIVE_ROOT"] = str(self.root)
        rejected = subprocess.run([
            sys.executable,str(COLLECTOR),"--store",str(self.store),
            "--registry",str(self.registry),"--command-id","fixture.cwd-environment",
            "--cwd",str(self.repository),"--component",f"fixture={self.repository}",
            "--",sys.executable,"-c",f"from pathlib import Path; Path({str(marker)!r}).write_text('bad')"],
            env=environment,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        self.assertEqual(rejected.returncode,2)
        self.assertFalse(marker.exists())

    def test_registered_environment_is_exact_and_retained_privately(self):
        self.registry_for("fixture.environment", [sys.executable])
        document = json.loads(self.registry.read_text())
        document["commands"][0]["requiredEnvironment"] = {
            "FIXTURE_CONTEXT": "PRIVATE_CANARY_MARKER"
        }
        self.registry.write_text(json.dumps(document))
        missing = self.invoke("fixture.environment", [sys.executable,"-c","print('no')"])
        self.assertEqual(missing.returncode, 2)
        environment = os.environ.copy(); environment["FIXTURE_CONTEXT"] = "wrong"
        mismatch = subprocess.run([
            sys.executable, str(COLLECTOR), "--store", str(self.store),
            "--registry", str(self.registry), "--command-id", "fixture.environment",
            "--cwd", str(self.repository), "--component", f"fixture={self.repository}",
            "--", sys.executable, "-c", "print('no')"], env=environment,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertEqual(mismatch.returncode, 2)
        environment["FIXTURE_CONTEXT"] = "PRIVATE_CANARY_MARKER"
        result = subprocess.run([
            sys.executable, str(COLLECTOR), "--store", str(self.store),
            "--registry", str(self.registry), "--command-id", "fixture.environment",
            "--cwd", str(self.repository), "--component", f"fixture={self.repository}",
            "--", sys.executable, "-c", "print('yes')"], env=environment,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        envelope, staging = self.envelope()
        context = json.loads((staging / "artifacts/private/command-context.json").read_text())
        self.assertEqual(context["command"]["effectiveEnvironment"], [
            {"name":"FIXTURE_CONTEXT","value":"PRIVATE_CANARY_MARKER"}])
        self.assertRegex(context["registry"]["sha256"], r"^[0-9a-f]{64}$")
        self.assertEqual(context["command"]["environmentFiles"], [])
        sys.path.insert(0, str(EVIDENCE))
        import finalize
        bundle, _ = finalize.finalize(staging, self.store)
        public = (bundle / "public-summary.json").read_text()
        self.assertNotIn("PRIVATE_CANARY_MARKER", public)
        self.assertNotIn("FIXTURE_CONTEXT", public)

    def test_registry_change_during_child_blocks_persistence_but_preserves_exit(self):
        self.registry_for("fixture.registry-change", [sys.executable])
        program = (
            "import json,sys; p=sys.argv[1]; d=json.load(open(p)); "
            "d['commands'][0]['defaultTimeoutSeconds']=11; open(p,'w').write(json.dumps(d))"
        )
        result = self.invoke("fixture.registry-change",
            [sys.executable,"-c",program,str(self.registry)])
        self.assertEqual(result.returncode, 0)
        self.assertIn(b"command registry changed during collection", result.stderr)
        self.assertFalse((self.store / "staging").exists())

    def test_registered_environment_file_hash_is_enforced_and_retained(self):
        executable = self.root / "pinned-tool"
        executable.write_bytes(b"#!/bin/sh\nexit 0\n"); executable.chmod(0o700)
        digest = hashlib.sha256(executable.read_bytes()).hexdigest()
        self.registry_for("fixture.environment-file", [sys.executable])
        document = json.loads(self.registry.read_text())
        document["commands"][0]["requiredEnvironmentNames"] = ["PINNED_TOOL"]
        document["commands"][0]["requiredEnvironmentFileSha256"] = {"PINNED_TOOL":digest}
        self.registry.write_text(json.dumps(document))
        environment = os.environ.copy(); environment["PINNED_TOOL"] = str(executable)
        result = subprocess.run([
            sys.executable,str(COLLECTOR),"--store",str(self.store),
            "--registry",str(self.registry),"--command-id","fixture.environment-file",
            "--cwd",str(self.repository),"--component",f"fixture={self.repository}",
            "--",sys.executable,"-c","print('yes')"],env=environment,
            stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        self.assertEqual(result.returncode,0,result.stderr.decode())
        _envelope, staging = self.envelope()
        context = json.loads((staging / "artifacts/private/command-context.json").read_text())
        self.assertEqual(context["command"]["environmentFiles"], [{
            "name":"PINNED_TOOL","requested":str(executable),"resolution":"available",
            "resolvedPath":str(executable.resolve()),"bytes":executable.stat().st_size,
            "sha256":digest}])
        self.tearDown(); self.setUp()
        bad = self.root / "wrong-tool"; bad.write_bytes(b"wrong"); bad.chmod(0o700)
        self.registry_for("fixture.environment-file", [sys.executable])
        document = json.loads(self.registry.read_text())
        document["commands"][0]["requiredEnvironmentNames"] = ["PINNED_TOOL"]
        document["commands"][0]["requiredEnvironmentFileSha256"] = {"PINNED_TOOL":"0"*64}
        self.registry.write_text(json.dumps(document))
        environment = os.environ.copy(); environment["PINNED_TOOL"] = str(bad)
        rejected = subprocess.run([
            sys.executable,str(COLLECTOR),"--store",str(self.store),
            "--registry",str(self.registry),"--command-id","fixture.environment-file",
            "--cwd",str(self.repository),"--component",f"fixture={self.repository}",
            "--",sys.executable,"-c","print('must not run')"],env=environment,
            stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        self.assertEqual(rejected.returncode,2)
        self.assertIn(b"environment file identity differs",rejected.stderr)

    def test_attachment_file_argv_and_registered_output_contract_are_exact(self):
        output = self.root / "outputs"; output.mkdir(mode=0o700)
        target = output / "result.json"
        self.registry_for("fixture.output-path", [sys.executable])
        document = json.loads(self.registry.read_text())
        entry = document["commands"][0]
        entry.update({"attachmentsAllowed":True,"attachmentPathArgIndex":3,
            "attachmentAdapter":{"kind":"none","application":None,"artifactId":None},
            "attachmentOutputs":[{"artifactId":"result","relativePath":"result.json",
                "role":"diagnostic","mediaType":"application/json","requirement":"required",
                "captureMode":"new-output","maxBytes":1024,"expectedSha256":None,
                "producerResult":None}]})
        self.registry.write_text(json.dumps(document))
        plan = self.attachment_plan(output, entry["attachmentOutputs"])
        program = "import os,sys; fd=os.open(sys.argv[1],os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600); os.write(fd,b'{}'); os.close(fd)"
        result = self.invoke("fixture.output-path",
            [sys.executable,"-c",program,str(target)],"--attachment-plan",str(plan))
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        envelope, _ = self.envelope()
        self.assertIn("result", {artifact["artifactId"] for artifact in envelope["artifacts"]})

    def test_production_registry_uses_component_roots_not_developer_paths(self):
        registry = json.loads((EVIDENCE / "commands.json").read_text())
        rendered = json.dumps(registry, sort_keys=True)
        self.assertNotIn("/home/", rendered)
        commands = {entry["commandId"]: entry for entry in registry["commands"]}
        source_commands = {
            "mirrors.local-no-model":"mirrors", "mirrors.interop":"mirrors",
            "mirrors.remote-model-check":"mirrors",
            "mirrorecma.project-check":"mirrorecma", "mirrorecma.test":"mirrorecma",
            "mirrorgate.required":"mirrorgate",
            "mirrorgate.application-campaign.work-queue":"mirrorgate",
            "mirrorgate.application-campaign.persistent-transfer":"mirrorgate",
            "mirrorgate.application-campaign.lease-service":"mirrorgate",
        }
        self.assertLessEqual(set(source_commands), set(commands))
        for command_id, component_id in source_commands.items():
            self.assertEqual(commands[command_id]["requiredCwdComponentId"], component_id)
        self.assertEqual(commands["mirrors.local-no-model"]["argvPrefix"],
                         ["bash", "tools/run-local-no-model-check.sh"])
        local_runner = (EVIDENCE.parents[1] / "tools/run-local-no-model-check.sh").read_text()
        executable_lines = [line.strip() for line in local_runner.splitlines()
                            if line.strip() and not line.lstrip().startswith("#")]
        self.assertNotIn("lake test", "\n".join(executable_lines))
        self.assertFalse(any("check-async-protocol.py" in line
                             for line in executable_lines))
        self.assertIn(
            "unset APALACHE_MC APALACHE_JAR TLA2TOOLS_JAR MIRRORS_ASYNC_RESOURCE_E2E",
            executable_lines)
        self.assertNotIn("APALACHE_MC",
                         commands["mirrors.remote-model-check"]["requiredEnvironmentNames"])
        self.assertNotIn("MIRRORS_REMOTE_JAVA_ARCHIVE_SHA256",
                         commands["mirrors.remote-model-check"]["requiredEnvironmentNames"])
        self.assertEqual(
            commands["mirrors.remote-model-check"]["requiredEnvironment"], {
                "MIRRORS_REMOTE_APALACHE_ARCHIVE_SHA256":
                    "68fb56dd9d053cf21d692fd7ec3fbaaeba1395661ec7434fa2b4c47e6fc432b8",
                "MIRRORS_REMOTE_APALACHE_JAR_SHA256":
                    "33611081942d392646af60993c599907f1f41752fce4a62304dbf9e2cdad4346",
                "MIRRORS_REMOTE_APALACHE_VERSION":"0.61.0",
                "MIRRORS_REMOTE_JAVA_ARCHIVE_SHA256":
                    "54ba13f3ef80887fa74708b2a32daaae6262517ba68433d850bb4b426343172b",
                "MIRRORS_REMOTE_JAVA_EXECUTABLE_SHA256":
                    "58df5c13e5d6e68f242ad9b724479122828523008ef0907d3f2a02f54afaff23",
                "MIRRORS_REMOTE_JAVA_OBSERVED_VERSION":"25.0.4+7-LTS",
                "MIRRORS_REMOTE_JAVA_SELECTED_VERSION":"25.0.4+7",
            })
        self.assertEqual(commands["mirrors.remote-model-check"]["argvPrefix"],
                         ["python3", "tools/evidence/run_remote_model_check.py"])
        self.assertEqual(commands["mirrors.interop"]["requiredEnvironment"]["HS_REF"],
                         "5ee414ee16b8aba50ceb480ac8013a56165272bb")
        self.assertEqual(commands["mirrors.interop"]["requiredEnvironmentFileSha256"],
                         {"HS_BIN":"6b8b46ce98b59c4bbb6a922ead08b1d576a77b8889454d106c10d1227584a087"})
        for application in ("work-queue", "persistent-transfer", "lease-service"):
            command = commands[f"mirrorgate.application-campaign.{application}"]
            self.assertEqual(command["argvLength"], 5)
            self.assertEqual(command["argvPrefix"][2:4], [application, "--receipt"])
            self.assertEqual(command["attachmentPathArgIndex"], 4)
            self.assertEqual(command["attachmentAdapter"], {
                "kind":"mirrorgate.application-validation/v2",
                "application":application,
                "artifactId":f"{application}-gate-receipt",
            })
            self.assertEqual(command["attachmentOutputs"][0]["relativePath"],
                             f"{application}-gate-receipt.json")

    def test_remote_model_check_rejects_java_archive_mismatch_before_execution(self):
        registry = json.loads((EVIDENCE / "commands.json").read_text())
        command = next(entry for entry in registry["commands"]
                       if entry["commandId"] == "mirrors.remote-model-check")
        credential = self.root / "credential.pem"
        credential.write_text("fixture; the wrapper must not read these bytes")
        environment = dict(os.environ)
        environment.update(command["requiredEnvironment"])
        environment.update({
            "MIRRORS_REMOTE_CA": str(credential),
            "MIRRORS_REMOTE_CLIENT_CERT": str(credential),
            "MIRRORS_REMOTE_CLIENT_KEY": str(credential),
            "MIRRORS_REMOTE_SERVER_PIN": "1" * 64,
            "MIRRORS_REMOTE_SERVICE_BINARY_SHA256": "2" * 64,
            "MIRRORS_REMOTE_SERVICE_SOURCE_REF": "3" * 40,
            "MIRRORS_REMOTE_JAVA_ARCHIVE_SHA256": "0" * 64,
        })
        result = subprocess.run(
            [sys.executable, str(EVIDENCE / "run_remote_model_check.py")],
            cwd=EVIDENCE.parents[1], env=environment,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, b"")
        self.assertIn(b"tool identity differs from the selected pins", result.stderr)

    def test_predeclared_gate_receipt_sets_behavior_and_cleanup_from_native_fields(self):
        output = self.root / "outputs"; output.mkdir(mode=0o700)
        receipt = self.valid_gate_receipt()
        receipt_source = self.root / "gate-receipt-source.json"
        receipt_source.write_text(json.dumps(receipt)); receipt_source.chmod(0o600)
        program = (
            "import os,sys; p=os.path.join(sys.argv[1],'lease-receipt.json'); "
            "fd=os.open(p,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600); os.write(fd,open(sys.argv[2],'rb').read()); os.close(fd); "
            "p=os.path.join(sys.argv[1],'lease-observation.json'); fd=os.open(p,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600); os.write(fd,b'{}'); os.close(fd)"
        )
        self.registry_for("fixture.gate", [sys.executable])
        self.enable_attachments(3)
        plan = self.attachment_plan(output, [
            {"artifactId":"gate-receipt","relativePath":"lease-receipt.json","role":"producer-result","mediaType":"application/json","requirement":"required","captureMode":"new-output","maxBytes":1048576,"expectedSha256":None,"producerResult":{"producer":"mirrorgate","schemaVersion":"mirrorgate.application-validation/v2"}},
            {"artifactId":"gate-observation","relativePath":"lease-observation.json","role":"diagnostic","mediaType":"application/json","requirement":"required","captureMode":"new-output","maxBytes":4096,"expectedSha256":None,"producerResult":None},
        ], adapter="mirrorgate.application-validation/v2",
           adapter_artifact="gate-receipt", application="lease-service")
        result = self.invoke("fixture.gate", [sys.executable,"-c",program,str(output),str(receipt_source)],
                             "--attachment-plan",str(plan))
        self.assertEqual(result.returncode,0,result.stderr.decode())
        envelope,_ = self.envelope()
        self.assertEqual(envelope["outcomes"]["behavior"]["status"],"passed")
        physical=next(item for item in envelope["outcomes"]["cleanup"] if item["scope"]=="gate-physical")
        self.assertEqual(physical["status"],"confirmed")
        self.assertEqual(envelope["releaseRequirements"]["requiredCleanupScopes"],["gate-physical"])
        self.assertEqual(envelope["outcomes"]["behavior"]["producerResult"]["artifactId"],"gate-receipt")

    def test_gate_cleanup_failure_cannot_be_downgraded_by_later_missing_cleanup(self):
        output = self.root / "outputs"; output.mkdir(mode=0o700)
        receipt = {
            "schema": "mirrorgate.application-validation/v2",
            "application": "lease-service",
            "outcomes": [
                {"outcome": "passed", "receipt": {"cleanup": {
                    "status": "failed", "remainingResources": ["worker"],
                    "failures": ["cleanup-failed"]}}},
                {"outcome": "passed", "receipt": {}},
            ],
        }
        program = (
            "import json,os,sys; p=os.path.join(sys.argv[1],'lease-receipt.json'); "
            f"fd=os.open(p,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600); os.write(fd,{json.dumps(json.dumps(receipt).encode().decode())}.encode()); os.close(fd)"
        )
        self.registry_for("fixture.gate", [sys.executable]); self.enable_attachments(3)
        plan = self.attachment_plan(output, [{
            "artifactId":"gate-receipt","relativePath":"lease-receipt.json",
            "role":"producer-result","mediaType":"application/json","requirement":"required",
            "captureMode":"new-output","maxBytes":4096,"expectedSha256":None,
            "producerResult":{"producer":"mirrorgate","schemaVersion":"mirrorgate.application-validation/v2"},
        }], adapter="mirrorgate.application-validation/v2",
           adapter_artifact="gate-receipt", application="lease-service")
        result = self.invoke("fixture.gate", [sys.executable,"-c",program,str(output)],
                             "--attachment-plan",str(plan))
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        envelope, _ = self.envelope()
        physical = next(item for item in envelope["outcomes"]["cleanup"]
                        if item["scope"] == "gate-physical")
        self.assertEqual(physical["status"], "failed")

    def test_gate_campaign_receipt_rejects_missing_duplicate_or_unbound_credit(self):
        sys.path.insert(0, str(EVIDENCE))
        import collect
        receipt = self.valid_gate_receipt()
        selection = receipt["catalog"]["selectionRef"]
        components = receipt["catalog"]["componentRefs"]
        collect._validate_gate_campaign_receipt(receipt, "lease-service", selection, components)
        missing = json.loads(json.dumps(receipt))
        missing["mutationCampaign"]["mutants"].pop()
        with self.assertRaisesRegex(ValueError, "denominator"):
            collect._validate_gate_campaign_receipt(missing, "lease-service", selection, components)
        duplicate = json.loads(json.dumps(receipt))
        duplicate["campaignDefinition"]["orderedCaseIds"][1] = \
            duplicate["campaignDefinition"]["orderedCaseIds"][0]
        with self.assertRaisesRegex(ValueError, "ordered case IDs"):
            collect._validate_gate_campaign_receipt(duplicate, "lease-service", selection, components)
        with self.assertRaisesRegex(ValueError, "catalog/component identity"):
            collect._validate_gate_campaign_receipt(
                receipt, "lease-service", {**selection, "selectionValue":"0" * 40}, components)

    def test_gate_aggregate_requires_all_three_exact_native_campaigns(self):
        sys.path.insert(0, str(EVIDENCE))
        import collect
        receipts = {application:self.valid_gate_receipt(application)
                    for application in ("work-queue","persistent-transfer","lease-service")}
        selection = receipts["lease-service"]["catalog"]["selectionRef"]
        components = receipts["lease-service"]["catalog"]["componentRefs"]
        captured = {f"{application}-gate-receipt":json.dumps(receipt).encode()
                    for application, receipt in receipts.items()}
        behavior, cleanup, tier = collect._gate_aggregate_outcomes(
            captured, selection, components)
        self.assertEqual((behavior["status"], tier), ("passed", "passed"))
        physical = next(item for item in cleanup if item["scope"] == "gate-physical")
        self.assertEqual(physical["status"], "confirmed")
        del captured["work-queue-gate-receipt"]
        behavior, cleanup, tier = collect._gate_aggregate_outcomes(
            captured, selection, components)
        self.assertEqual((behavior["status"], tier), ("inconclusive", "failed"))
        physical = next(item for item in cleanup if item["scope"] == "gate-physical")
        self.assertEqual(physical["status"], "unconfirmed")

    def test_gate_aggregate_preserves_observed_cleanup_failure(self):
        sys.path.insert(0, str(EVIDENCE))
        import collect
        receipts = {application:self.valid_gate_receipt(application)
                    for application in ("work-queue","persistent-transfer","lease-service")}
        failed = receipts["persistent-transfer"]["outcomes"][0]["receipt"]["cleanup"]
        failed.update({"status":"failed","remainingResources":["worker"],
                       "failures":["kill-failed"]})
        selection = receipts["lease-service"]["catalog"]["selectionRef"]
        components = receipts["lease-service"]["catalog"]["componentRefs"]
        captured = {f"{application}-gate-receipt":json.dumps(receipt).encode()
                    for application, receipt in receipts.items()}
        behavior, cleanup, tier = collect._gate_aggregate_outcomes(
            captured, selection, components)
        self.assertEqual((behavior["status"], tier), ("inconclusive", "failed"))
        physical = next(item for item in cleanup if item["scope"] == "gate-physical")
        self.assertEqual(physical["status"], "failed")

    def test_local_aggregate_requires_exact_mutants_probes_controls_and_framework(self):
        sys.path.insert(0, str(EVIDENCE))
        import collect
        receipt, selection, components = self.valid_local_aggregate_receipt()
        collect._validate_local_aggregate_receipt(receipt, selection, components)
        plan_stub = type("Plan", (), {"adapter_artifact_id":"local-campaigns"})()
        behavior, cleanup, tier = collect._local_aggregate_outcomes(
            plan_stub, {"local-campaigns":json.dumps(receipt).encode()},
            [{"artifactId":"local-campaigns","producer":"mirrorecma",
              "schemaVersion":"mirrorecma.application-campaign-aggregate/v1"}],
            selection, components)
        self.assertEqual((behavior["status"], tier), ("passed", "passed"))
        self.assertEqual(cleanup, [{"scope":"local-cooperative","requirement":"required",
                                   "status":"confirmed","artifactIds":["local-campaigns"]}])
        cases = [
            (lambda value: value["campaigns"][0]["mutationCampaign"]["results"].pop(),
             "mutation denominator"),
            (lambda value: value["campaigns"][1]["results"][1].__setitem__(
                "expectedFirstMismatch", {"code":"replay_mismatch","traceIndex":0,
                                          "stateIndex":999,"action":"chunk"}),
             "mismatch coordinates"),
            (lambda value: value["campaigns"][2]["results"][-2]["probe"].__setitem__(
                "status", "not_run"), "cleanup/probe"),
            (lambda value: value["framework"].__setitem__(
                "componentRefs", []), "catalog/component identity"),
        ]
        for index, (mutate, message) in enumerate(cases):
            with self.subTest(case=index):
                candidate = json.loads(json.dumps(receipt))
                mutate(candidate)
                with self.assertRaisesRegex(ValueError, message):
                    collect._validate_local_aggregate_receipt(candidate, selection, components)
        failed = json.loads(json.dumps(receipt))
        failed["campaigns"][0]["results"][0]["cleanup"]["status"] = "failed"
        behavior, cleanup, tier = collect._local_aggregate_outcomes(
            plan_stub, {"local-campaigns":json.dumps(failed).encode()}, [],
            selection, components)
        self.assertEqual((behavior["status"], tier), ("inconclusive", "failed"))
        self.assertEqual(cleanup[0]["status"], "failed")

    def test_local_aggregate_attachment_sets_required_cleanup_and_behavior(self):
        receipt, _selection, _components = self.valid_local_aggregate_receipt()
        output = self.root / "outputs"; output.mkdir(mode=0o700)
        source = self.root / "local-receipt-source.json"
        source.write_text(json.dumps(receipt)); source.chmod(0o600)
        program = (
            "import os,sys; p=os.path.join(sys.argv[1],'local-application-campaigns.json'); "
            "fd=os.open(p,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600); "
            "os.write(fd,open(sys.argv[2],'rb').read()); os.close(fd)"
        )
        attachment = {"artifactId":"local-application-campaigns",
            "relativePath":"local-application-campaigns.json","role":"producer-result",
            "mediaType":"application/json","requirement":"required",
            "captureMode":"new-output","maxBytes":16 * 1024 * 1024,
            "expectedSha256":None,"producerResult":{"producer":"mirrorecma",
                "schemaVersion":"mirrorecma.application-campaign-aggregate/v1"}}
        self.registry_for("fixture.local", [sys.executable]); self.enable_attachments(3)
        registry = json.loads(self.registry.read_text())
        registry["commands"][0]["attachmentAdapter"] = {
            "kind":"mirrorecma.application-campaign-aggregate/v1",
            "application":None,"artifactId":"local-application-campaigns"}
        registry["commands"][0]["attachmentOutputs"] = [attachment]
        self.registry.write_text(json.dumps(registry))
        plan = self.attachment_plan(output, [attachment],
            adapter="mirrorecma.application-campaign-aggregate/v1",
            adapter_artifact="local-application-campaigns")
        result = self.invoke("fixture.local",
            [sys.executable,"-c",program,str(output),str(source)],
            "--attachment-plan",str(plan))
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        envelope, _ = self.envelope()
        self.assertEqual(envelope["outcomes"]["behavior"]["status"], "passed")
        self.assertEqual(envelope["outcomes"]["cleanup"], [{
            "scope":"local-cooperative","requirement":"required","status":"confirmed",
            "artifactIds":["local-application-campaigns"]}])
        self.assertEqual(envelope["releaseRequirements"]["requiredCleanupScopes"],
                         ["local-cooperative"])

    def test_reduction_adapter_binds_model_valid_result_and_all_materialized_inputs(self):
        sys.path.insert(0, str(EVIDENCE))
        import collect
        validator_sha, apalache_sha, java_sha, archive_sha = (
            "a"*64, "b"*64, "c"*64, "d"*64)
        qualification_ref = (
            "microsoft-jdk-25.0.4+7-linux-x64/sha256:" + archive_sha)
        captured = {
            "lease-reduction-candidate-trace":b"candidate-trace",
            "lease-reduction-original-bundle":b"original-bundle",
            "lease-reduction-model":b"model",
            "lease-reduction-lock":b"lock",
            "lease-reduction-original-trace":b"original-trace",
            "lease-reduction-candidate":b"candidate-request",
        }
        tool_manifest = {"schema":"mirrorecma.lease-reduction-tools/v1",
            "validator":{"sha256":validator_sha},
            "apalache":{"jarSha256":apalache_sha},
            "java":{"executableSha256":java_sha,"archiveSha256":archive_sha,
                    "qualificationRef":qualification_ref}}
        captured["lease-reduction-tool-manifest"] = json.dumps(tool_manifest).encode()
        sha = lambda artifact_id: hashlib.sha256(captured[artifact_id]).hexdigest()
        receipt = {"schema":"mirrorecma.lease-reduction-oracle/v1",
            "status":"model_valid","profile":"lease-service-input-shrink/v1",
            "domainVersion":"LeaseService.Next/v1","modelSha256":sha("lease-reduction-model"),
            "interfaceDigest":"e"*64,"originalCorpusSha256":"f"*64,
            "candidateCorpusSha256":"1"*64,
            "selectedTraceSha256":sha("lease-reduction-original-trace"),
            "traceOccurrences":[0,1],
            "validator":{"id":"mirrors.model-interface-reduction/v1","sha256":validator_sha},
            "apalache":{"version":"0.61.0","sha256":apalache_sha},
            "java":{"observedVersion":"25.0.4+7-LTS","selectedVersion":"25.0.4+7",
                "executableSha256":java_sha,"archiveSha256":archive_sha,
                "distributionQualified":True,"qualificationRef":qualification_ref},
            "cleanup":{"status":"confirmed","method":"explore_done"},
            "materialization":{"originalTraceSha256":sha("lease-reduction-original-trace"),
                "candidateTraceSha256":sha("lease-reduction-candidate-trace"),
                "originalBundleSha256":sha("lease-reduction-original-bundle"),
                "actionSequence":["init","acquire","acquire","renew","advance","write",
                                  "acquire","release","renew","write","release"],
                "inputMeasure":{"before":2,"after":1},
                "changes":["/states/2/parameters/client/#bigint"],
                "toolManifestSha256":sha("lease-reduction-tool-manifest"),
                "sources":{"model":{"path":"model","sha256":sha("lease-reduction-model")},
                    "lock":{"path":"lock","sha256":sha("lease-reduction-lock")},
                    "originalTrace":{"path":"trace","sha256":sha("lease-reduction-original-trace")},
                    "candidateRequest":{"path":"candidate","sha256":sha("lease-reduction-candidate")}}}}
        captured["lease-reduction-receipt"] = json.dumps(receipt).encode()
        collect._validate_reduction_receipt(receipt, captured)
        plan_stub = type("Plan", (), {"adapter_artifact_id":"lease-reduction-receipt"})()
        behavior, cleanup, tier = collect._reduction_outcomes(
            plan_stub, captured, [{"artifactId":"lease-reduction-receipt",
                "producer":"mirrorecma","schemaVersion":"mirrorecma.lease-reduction-oracle/v1"}])
        self.assertEqual((behavior["status"], tier), ("passed", "passed"))
        self.assertEqual(cleanup[0]["status"], "confirmed")
        changed = dict(captured); changed["lease-reduction-candidate-trace"] = b"other"
        with self.assertRaisesRegex(ValueError, "artifact identity differs"):
            collect._validate_reduction_receipt(receipt, changed)
        invalid = json.loads(json.dumps(receipt))
        invalid["materialization"]["changes"] = ["/states/3/parameters/client/#bigint"]
        with self.assertRaisesRegex(ValueError, "unsupported coordinates"):
            collect._validate_reduction_receipt(invalid, captured)

    def test_native_recovery_receipt_sets_gate_recovery_cleanup_without_exit_inference(self):
        output = self.root / "outputs"; output.mkdir(mode=0o700)
        payload = {
            "schema": "mirrorgate.recovery-receipt/v1", "attemptId": "attempt-1",
            "trigger": "offline_reclaim", "original": None,
            "journalSchema": "mirrorgate.recovery-journal/v1",
            "controllerInstance": "controller-1", "bootId": "boot-1", "principalUid": os.geteuid(),
            "ownershipObservations": ["reclaimed"], "cgroupObservations": [{
                "resourceId":"resource-1",
                "settings":{"pids.max":"32","memory.max":"1048576",
                            "memory.swap.max":"0","cpu.max":"10000 100000"},
                "counters":{"pids.current":"0","memory.current":"0",
                            "cgroup.events":"populated 0"}}],
            "remainingResources": [],
            "results": [{"resourceId":"resource-1","sessionId":"session-1","kind":"cgroup-v2",
                         "result":"reclaimed","reasonCode":None}],
            "cleanup": {"scope":"gate-recovery","requirement":"required",
                        "status":"confirmed","artifactIds":[]},
        }
        payload["sha256"] = hashlib.sha256(json.dumps(payload, sort_keys=True,
            separators=(",", ":"), ensure_ascii=True).encode()).hexdigest()
        sys.path.insert(0, str(EVIDENCE))
        import collect
        missing_observation = json.loads(json.dumps(payload))
        missing_observation["cgroupObservations"] = []
        unsigned = {key:value for key,value in missing_observation.items()
                    if key != "sha256"}
        missing_observation["sha256"] = hashlib.sha256(json.dumps(unsigned,
            sort_keys=True,separators=(",", ":"),ensure_ascii=True).encode()).hexdigest()
        plan_stub = type("Plan", (), {"adapter_artifact_id":"recovery-receipt"})()
        behavior, cleanup, tier = collect._gate_recovery_outcomes(
            plan_stub, {"recovery-receipt":json.dumps(missing_observation).encode()},
            [], "different-run")
        self.assertEqual((behavior["status"], tier), ("inconclusive", "failed"))
        self.assertEqual(next(item for item in cleanup
                              if item["scope"] == "gate-recovery")["status"],
                         "unconfirmed")
        program = (
            "import json,os,sys; p=os.path.join(sys.argv[1],'recovery.json'); "
            f"fd=os.open(p,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600); os.write(fd,{json.dumps(json.dumps(payload).encode().decode())}.encode()); os.close(fd)"
        )
        self.registry_for("fixture.recovery", [sys.executable]); self.enable_attachments(3)
        plan = self.attachment_plan(output, [{
            "artifactId":"recovery-receipt","relativePath":"recovery.json",
            "role":"recovery-receipt","mediaType":"application/json","requirement":"required",
            "captureMode":"new-output","maxBytes":65536,"expectedSha256":None,
            "producerResult":None,
        }], adapter="mirrorgate.recovery-receipt/v1", adapter_artifact="recovery-receipt")
        result = self.invoke("fixture.recovery", [sys.executable,"-c",program,str(output)],
                             "--attachment-plan",str(plan))
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        envelope, _ = self.envelope()
        recovery = next(item for item in envelope["outcomes"]["cleanup"]
                        if item["scope"] == "gate-recovery")
        self.assertEqual(recovery, {"scope":"gate-recovery","requirement":"required",
                                   "status":"confirmed","artifactIds":["recovery-receipt"]})
        self.assertEqual(envelope["releaseRequirements"]["requiredCleanupScopes"], ["gate-recovery"])
        self.assertNotIn("producerResult", envelope["outcomes"]["behavior"])

    def test_missing_symlink_oversized_and_changed_attachments_fail_persistence(self):
        cases = ["missing","symlink","oversized","changed"]
        for case in cases:
            with self.subTest(case=case):
                self.tearDown(); self.setUp()
                output=self.root/"outputs"; output.mkdir(mode=0o700)
                target=output/"result.json"
                capture_mode="new-output"; expected=None
                if case=="changed":
                    target.write_bytes(b"before"); target.chmod(0o600)
                    capture_mode="existing-input"; expected=hashlib.sha256(b"before").hexdigest()
                programs={
                    "missing":"pass",
                    "symlink":"import os,sys; os.symlink('/etc/passwd',os.path.join(sys.argv[1],'result.json'))",
                    "oversized":"import os,sys; fd=os.open(os.path.join(sys.argv[1],'result.json'),os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600); os.write(fd,b'12345'); os.close(fd)",
                    "changed":"import os,sys; open(os.path.join(sys.argv[1],'result.json'),'wb').write(b'after')",
                }
                self.registry_for("fixture.attach",[sys.executable]); self.enable_attachments(3)
                plan=self.attachment_plan(output,[{"artifactId":"attached","relativePath":"result.json","role":"diagnostic","mediaType":"application/json","requirement":"required","captureMode":capture_mode,"maxBytes":(16 if case=="changed" else 4),"expectedSha256":expected,"producerResult":None}])
                result=self.invoke("fixture.attach",[sys.executable,"-c",programs[case],str(output)],"--attachment-plan",str(plan))
                self.assertEqual(result.returncode,0)
                envelope,_=self.envelope()
                self.assertEqual(envelope["outcomes"]["persistence"]["status"],"failed")
                self.assertIn("attached",envelope["outcomes"]["persistence"]["missingArtifactIds"])

    def test_reproduction_attachment_cannot_self_reference_enclosing_run(self):
        output=self.root/"outputs"; output.mkdir(mode=0o700)
        run_id="run-self"
        data=json.dumps({"evidenceLinks":{"runRef":{"runId":run_id}}}).encode()
        path=output/"bundle.json"; path.write_bytes(data); path.chmod(0o600)
        plan_path=self.attachment_plan(output,[{"artifactId":"reproduction","relativePath":"bundle.json","role":"reproduction-input","mediaType":"application/json","requirement":"required","captureMode":"existing-input","maxBytes":4096,"expectedSha256":hashlib.sha256(data).hexdigest(),"producerResult":None}])
        sys.path.insert(0,str(EVIDENCE))
        import collect
        plan=collect.prepare_attachment_plan(plan_path)
        private=self.root/"private"; private.mkdir(mode=0o700)
        try:
            _artifacts,_producers,_captured,missing,failures=collect.capture_attachments(plan,private,run_id)
        finally:
            plan.close()
        self.assertEqual(missing,["reproduction"])
        self.assertTrue(failures)


if __name__ == "__main__":
    unittest.main()
