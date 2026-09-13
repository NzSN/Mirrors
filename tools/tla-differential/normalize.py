"""Semantic projections shared by observations and comparisons.

Ordering is ignored only for set-like facts. Import routes are retained in raw
inspection evidence but are not treated as oracle-independent identity.
"""
from __future__ import annotations

import json


def ordered(values):
    return sorted(values, key=lambda value: json.dumps(value, sort_keys=True))


def supported(value):
    return {"capability": "supported", "value": value}


def mirrors_facts(document):
    inspection = document["inspection"]
    modules = document["modules"]
    local = {module["name"] for module in modules}
    operators = [op for op in inspection["operators"] if op["declaredIn"] in local]
    facts = {
        "source_closure": supported(ordered([
            {key: source[key] for key in ("module", "path", "sha256")}
            for source in inspection["sources"]])),
        "variables": supported([
            {key: variable[key] for key in ("name", "declaredIn", "declaredName", "importPath")}
            for variable in inspection["variables"]]),
        "resolution": supported({
            "dependencies": ordered([{key: edge[key] for key in ("owner", "dependency", "kind", "local")}
                                     for edge in inspection["dependencies"] if edge["resolution"] == "local"]),
            "operators": ordered([{key: op[key] for key in ("name", "declaredIn", "arity", "local")}
                                  for op in operators])}),
        "levels": supported(ordered([{key: op[key] for key in ("name", "declaredIn", "level")}
                                     for op in operators])),
    }
    instances = []
    complete = True
    by_module = {module["name"]: module for module in modules}
    for module in modules:
        for instance in module["instances"]:
            value = {key: instance[key] for key in ("owner", "name", "module", "local")}
            # Site line disambiguates multiple unnamed instances in one owner.
            value["line"] = instance["line"]
            substitutions = list(instance["substitutions"])
            child = by_module.get(instance["module"])
            if child is None:
                complete = False
            else:
                formals = [name for decl in child["declarations"]
                           if decl["kind"] in ("constant", "variable") for name in decl["names"]]
                explicit = {sub["formal"] for sub in substitutions}
                # A successful frontend has already admitted same-name implicit
                # substitution. This records that language rule, without parsing.
                substitutions += [{"formal": name, "actual": {"kind": "name", "value": name}, "implicit": True}
                                  for name in formals if name not in explicit]
            if any(sub["actual"] is None for sub in substitutions):
                complete = False
            value["substitutions"] = ordered(substitutions)
            instances.append(value)
    facts["substitution"] = supported(ordered(instances)) if complete else {"capability": "unqualified"}
    return facts
