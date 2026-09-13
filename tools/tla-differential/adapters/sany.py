"""Pinned standalone-SANY adapter; it receives no Mirrors expectations."""
from __future__ import annotations
import hashlib, json
from pathlib import Path
from typing import Mapping, Any
from capture import AdapterFixture, MaterializedFixture, verify_materialized
from process import ProcessLimits, ProcessRequest, run_process

def observe(*, fixture: AdapterFixture, materialized: MaterializedFixture, config: Mapping[str, object], limits: ProcessLimits, artifact_dir: Path) -> dict[str, object]:
    jar = Path(str(config["sany_jar"])).resolve(); classes = Path(str(config["bridge_classes"])).resolve(); java = str(config.get("java", "java"))
    scratch = materialized.input_dir / ".sany-artifacts"
    scratch.mkdir(exist_ok=False)
    argv = [java, "-XX:-UsePerfData", "-Xmx1g", "-Djava.io.tmpdir=" + str(scratch), "-cp", f"{classes}:{jar}", "SanyBridge", materialized.root_path.name]
    result = run_process(ProcessRequest(argv, materialized.input_dir, artifact_dir=scratch), limits)
    raw = []
    artifact_dir.mkdir(parents=True, exist_ok=True)
    for label, content in (("stdout", result.stdout), ("stderr", result.stderr)):
        path = artifact_dir / f"sany-{label}.txt"
        path.write_bytes(content)
        raw.append({"path": f"fixtures/{fixture.id}/sany/raw/{path.name}", "sha256": hashlib.sha256(content).hexdigest()})
    try: payload = json.loads(result.stdout.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError): payload = None
    execution = result.status.value if result.status.value != "completed" else ("completed" if payload is not None else "invalid_output")
    required = {"schema","exitCode","ok","parseOk","semanticOk","errorLevel","root","modules"}
    if execution == "completed" and (not isinstance(payload, dict) or set(payload) != required or payload.get("schema") != "mirrors.sany-bridge/v1"):
        execution, payload = "invalid_output", None
    valid_ok = execution == "completed" and result.returncode == 0 and payload["exitCode"] == 0 and payload["ok"] is True and payload["parseOk"] is True and payload["semanticOk"] is True
    valid_reject = execution == "completed" and result.returncode == 0 and payload["ok"] is False and payload["errorLevel"] > 0
    outcome = "accepted" if valid_ok else ("rejected" if valid_reject else "unknown")
    if execution == "completed" and outcome == "unknown": execution = "invalid_output"
    verify_materialized(materialized)
    modules = payload.get("modules", []) if payload else []
    staged = {Path(name).stem: (name, digest) for name, digest in materialized.source_digests.items()}
    root = payload.get("root") if payload else None
    root_module = next((module for module in modules if module.get("name") == root), {})
    declarations = [row for row in root_module.get("declarations", []) if row.get("declaredIn") in staged]
    variables = [{"name": row["name"], "declaredIn": row["declaredIn"], "declaredName": row["name"]} for row in declarations if row["kind"] == "variable"]
    operators = [{key: row[key] for key in ("name", "declaredIn", "arity", "local")} for row in declarations if row["kind"] == "operator"]
    level_names = {0:"constant",1:"state",2:"action",3:"temporal"}
    levels = [{"name":row["name"],"declaredIn":row["declaredIn"],"level":level_names.get(row["level"],"unknown")} for row in declarations if row["kind"] == "operator"]
    sources = [{"module": name, "path": staged[name][0], "sha256": staged[name][1]} for name in {m.get("name") for m in modules if m.get("name") in staged}]
    deps = [edge for module in modules for edge in module.get("dependencies", []) if edge.get("owner") in staged and edge.get("dependency") in staged]
    facts = {key:{"capability":"unqualified"} for key in ("outcome","stage","source_closure","variables","resolution","levels","substitution")}
    if outcome != "unknown":
        facts["outcome"] = {"capability":"supported","value":outcome}
    if outcome == "accepted":
        facts.update({"outcome":{"capability":"supported","value":outcome}, "source_closure":{"capability":"supported","value":sources}, "variables":{"capability":"supported","value":variables}, "resolution":{"capability":"supported","value":{"dependencies":deps,"operators":operators}}, "levels":{"capability":"supported","value":levels}, "substitution":{"capability":"supported","value":[instance for module in modules if module.get("name") in staged for instance in module.get("instances", [])]}})
    if outcome == "accepted" and any(sub["actual"] is None for inst in facts["substitution"]["value"] for sub in inst["substitutions"]):
        facts["substitution"] = {"capability": "unqualified"}
    fingerprint = hashlib.sha256(jar.read_bytes()).hexdigest() if jar.is_file() else "unavailable"
    return {"schema":"mirrors.tla-differential-observation/v1", "fixture":fixture.id, "engine":"sany", "provider":fixture.provider, "inputDigest":materialized.input_digest, "adapter":{"id":"sany","version":"v1"}, "tool":{"id":"tla2tools","version":str(config.get("version","pending")),"fingerprint":fingerprint}, "invocation":{"argv":argv,"exitCode":result.returncode}, "execution":execution, "outcome":outcome, "nativePhase":"semantic", "stage":None, "diagnostics":[], "facts":facts, "rawArtifacts":raw}
