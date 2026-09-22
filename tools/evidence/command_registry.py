"""Closed parsing shared by command collection and offline qualification."""

from __future__ import annotations

from typing import Any

from validate import loads_json_bytes


ENTRY_FIELDS = frozenset({
    "commandId", "tierId", "requirement", "argvPrefix", "argvLength",
    "requiredCwd", "requiredCwdComponentId", "requiredCwdEnvironmentName",
    "requiredCwdSubdirectory",
    "defaultTimeoutSeconds", "catalogComponentId", "catalogPath",
    "catalogSelectionRef", "requiredEnvironment", "requiredEnvironmentNames",
    "requiredEnvironmentFileSha256", "requiredPathPrefix", "attachmentsAllowed", "attachmentRootArgIndex",
    "attachmentPathArgIndex", "attachmentAdapter", "attachmentOutputs",
    "registryOwnerComponentId",
})


def parse_registry(raw: bytes) -> dict[str, Any]:
    registry = loads_json_bytes(raw)
    if type(registry) is not dict or set(registry) != {"schemaVersion", "commands"}:
        raise ValueError("evidence command registry root is not closed")
    if registry.get("schemaVersion") != "mirrors.evidence-command-registry/v1":
        raise ValueError("unsupported evidence command registry")
    commands = registry.get("commands")
    if (type(commands) is not list or not commands or len(commands) > 256
            or any(type(entry) is not dict for entry in commands)):
        raise ValueError("evidence command registry commands are malformed")
    if any(set(entry) - ENTRY_FIELDS for entry in commands):
        raise ValueError("evidence command registry entry has an unknown field")
    command_ids = [entry.get("commandId") for entry in commands]
    if (any(type(value) is not str or not value for value in command_ids)
            or len(command_ids) != len(set(command_ids))):
        raise ValueError("evidence command registry command IDs are malformed or duplicate")
    return registry


def select_command(registry: dict[str, Any], command_id: str) -> dict[str, Any]:
    matches = [entry for entry in registry["commands"]
               if entry.get("commandId") == command_id]
    if len(matches) != 1:
        raise ValueError(f"commandId must resolve exactly once: {command_id}")
    return matches[0]
