"""Verify Grok preparation artifacts and the reviewed task/document structure.

Does not run builds, installed qualification, remote commands or operations.
"""

import hashlib
import json
import re
import subprocess
from pathlib import Path

repo = Path(__file__).resolve().parents[3]
batch = repo / "Plans/mainwork-execution-20261103"


def read_json(path):
    return json.loads(path.read_text())


def check_bytes(path, size, digest):
    assert path.is_file() and not path.is_symlink(), str(path)
    raw = path.read_bytes()
    assert len(raw) == size, str(path)
    assert hashlib.sha256(raw).hexdigest() == digest, str(path)


counts = {}
for name in ("source", "admission", "handoff"):
    root = batch / name
    inventory = read_json(root / "inventory.json")
    expected = set()
    for item in inventory["files"]:
        path = (repo / item["path"] if item["path"].startswith("Plans/")
                else root / item["path"])
        assert path.resolve().is_relative_to(root)
        check_bytes(path, item["bytes"], item["sha256"])
        expected.add(path.relative_to(root).as_posix())
    actual = {p.relative_to(root).as_posix() for p in root.rglob("*")
              if p.is_file() and p != root / "inventory.json"}
    assert actual == expected, (name, actual ^ expected)
    counts[name] = len(expected)
    result = read_json(root / "result.json")
    for command in result.get("commands", []):
        for stream in ("stdout", "stderr"):
            if stream + "Path" in command:
                check_bytes(repo / command[stream + "Path"],
                            command[stream + "Bytes"], command[stream + "Sha256"])
        if "log" in command:
            check_bytes(root / command["log"], command["logBytes"],
                        command["logSha256"])

ledger = read_json(batch / "tasks.json")
tasks = {t["id"]: t for t in ledger["tasks"]}
assert len(tasks) == len(ledger["tasks"]) == 25
visited = set()


def visit(name, active):
    assert name in tasks and name not in active, name
    if name in visited:
        return
    task = tasks[name]
    dependencies = list(task["dependsOn"])
    for items in task.get("conditionalDependencies", {}).values():
        dependencies.extend(items)
    for dependency in dependencies:
        visit(dependency, active | {name})
    visited.add(name)


for task_id in tasks:
    visit(task_id, set())

baseline = read_json(batch / "review-baseline.json")
assert subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo,
                               text=True).strip() == baseline["head"]
assert subprocess.check_output(["git", "rev-parse", "HEAD^{tree}"], cwd=repo,
                               text=True).strip() == baseline["headTree"]
for path in baseline["preExistingUntrackedPaths"]:
    assert (repo / path).exists(), path

original = subprocess.check_output(["git", "show", "HEAD:CHECKPOINTS.md"], cwd=repo)
current = (repo / "CHECKPOINTS.md").read_bytes()
prefix = current[:current.index(b"## 2026-11-03")]
suffix = current[current.index(b"## 2026-10-31"):]
assert prefix + suffix == original
subprocess.run(["git", "diff", "--check"], cwd=repo, check=True,
               capture_output=True)
assert subprocess.check_output(["git", "diff", "--name-only"], cwd=repo,
                               text=True).splitlines() == ["CHECKPOINTS.md"]
assert not subprocess.check_output(["git", "diff", "--cached", "--name-only"],
                                   cwd=repo, text=True).strip()

registry = {entry["commandId"]: entry for entry in read_json(
    repo / "tools/evidence/commands.json")["commands"]}
profile = next(p for p in read_json(repo / "tools/evidence/qualification-profiles.json")["profiles"]
               if p["profileId"] == "m5-wsl-windows-remote")
vectors = []
for filename in ("tasks.md", "verification.md"):
    text = (batch / "handoff" / filename).read_text()
    for block in re.findall(r"```contract-argv\n(.*?)\n```", text, re.S):
        command_id, *argv = block.splitlines()
        entry = registry[command_id]
        assert len(argv) == entry["argvLength"], command_id
        assert argv[:len(entry["argvPrefix"])] == entry["argvPrefix"], command_id
        vectors.append(command_id)
assert set(profile["requiredCommandIds"]) <= set(vectors)
assert {registry[i]["tierId"] for i in profile["requiredCommandIds"]} == set(profile["requiredTierIds"])

blocks = re.findall(r"```bash\n(.*?)\n```",
                    (batch / "review/corrected-commands.md").read_text(), re.S)
for block in blocks:
    subprocess.run(["bash", "-n"], input=block, text=True, check=True,
                   capture_output=True)

documents = [repo / "Plans/mainwork-stages-2026-11-03.md", batch / "README.md",
             batch / "review.md", batch / "review/corrected-commands.md",
             *batch.glob("*-task.md")]
for document in documents:
    for target in re.findall(r"\]\(([^)#]+)(?:#[^)]*)?\)", document.read_text()):
        if "://" not in target:
            assert (document.parent / target).exists(), (document, target)

print(json.dumps({
    "schemaVersion": "mirrors.mainwork-batch-verification/v1",
    "status": "verified-preparation",
    "head": baseline["head"], "tree": baseline["headTree"],
    "inventoryCounts": counts, "inventoriedFilesVerified": sum(counts.values()),
    "taskCount": len(tasks), "dagAcyclic": True,
    "commandVectorsVerified": len(vectors),
    "requiredCommands": len(profile["requiredCommandIds"]),
    "requiredTiers": len(profile["requiredTierIds"]),
    "correctionBashSyntaxBlocks": len(blocks),
    "historicalCheckpointPreserved": True,
    "preExistingPathsPreserved": True,
    "newQualificationClaim": False,
}, indent=2))
