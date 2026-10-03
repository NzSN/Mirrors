"""Producer-side source selection policy; legacy identity records remain readable."""

def is_planning_documentation(component_id: str, path: str) -> bool:
    return (component_id == "mirrors"
            and path != "Plans/q3-readiness-2026-09-25.md"
            and (path.startswith(("Plans/", "tmp/")) or path == "CHECKPOINTS.md"))
