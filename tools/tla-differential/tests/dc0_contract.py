"""DC0 compatibility-contract inputs and preserved-checkpoint verification.

This module intentionally does not alter the corpus manifest or make a
reference result into an expectation.  A qualified host may use the small
sources below for a new, separately indexed reference run.  The assertions in
``test_dc0_contract.py`` instead verify the immutable J/K starting evidence.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path


REPO = Path(__file__).resolve().parents[3]
EVIDENCE = REPO / "test/fixtures/tla-frontend/differential/evidence"
CHECKPOINTS = ("checkpoint-j", "checkpoint-k")
CHECKPOINT_SEMANTIC_SHA256 = "5dd32f9003de7c09771dac69282be01a853fcf5dfd11c4302011b6bf3da3f354"

# The closed Unicode enumeration the DC0 live matrix covered. It is frozen with
# that evidence and never rewritten: DC3 removes admitted aliases from the
# profile, not from this record.
DC0_UNICODE_SPELLINGS = (
    "∧", "∨", "¬", "⇒", "⇔", "≡", "∈", "∉", "⊆", "⊂", "⊇", "⊃", "∪", "∩",
    "≠", "≤", "≥", "⟨", "⟩", "↦", "‥", "□", "◇", "≜", "→", "←", "∘", "×",
    "÷", "≺", "≻", "∼", "≈", "∙", "⋆", "○",
)

# The three aliases DC3 adopted as default-profile 3 spellings. Each keeps its
# canonical ASCII operator; every other DC0 glyph stays fail-closed.
ADMITTED_UNICODE_ALIASES = {"∧": "\\/\\", "∈": "\\in", "≤": "=<"}

# Must remain textually identical to Core.Tla.Lexer.stagedUnicodeOperatorSpellings.
STAGED_UNICODE_SPELLINGS = tuple(
    spelling for spelling in DC0_UNICODE_SPELLINGS
    if spelling not in ADMITTED_UNICODE_ALIASES
)

# The three aliases exercised in the unresolved outcome finding.  Each source
# is deliberately a one-definition module so native stdout/stderr can be tied
# to exactly one spelling and source digest.
EXERCISED_UNICODE_SOURCES = {
    "∧": "---- MODULE Dc0UnicodeAnd ----\nAnd == TRUE ∧ TRUE\n====\n",
    "∈": "---- MODULE Dc0UnicodeMember ----\nMember == 1 ∈ {1}\n====\n",
    "≤": "---- MODULE Dc0UnicodeLeq ----\nLeq == 1 ≤ 2\n====\n",
}

# These inputs delimit DC1's syntax-directed level rule.  Only the action
# result is preserved evidence; the other three are probes, not inferred facts.
# A qualified SANY run must record native observations before DC1 treats any of
# them as calibrated.
ENABLED_SOURCES = {
    "constant": "---- MODULE Dc0EnabledConstant ----\nC == TRUE\nE == ENABLED C\n====\n",
    "state": "---- MODULE Dc0EnabledState ----\nVARIABLE x\nS == x = x\nE == ENABLED S\n====\n",
    "action": "---- MODULE Dc0EnabledAction ----\nVARIABLE x\nA == x' = x\nE == ENABLED A\n====\n",
    "temporal": "---- MODULE Dc0EnabledTemporal ----\nT == []TRUE\nE == ENABLED T\n====\n",
}
ENABLED_ACTION_LEVEL = "state"

# Directly extracted from both preserved checkpoint reports.  The fixture IDs
# are historical and intentionally not renamed here.
NAMED_INSTANCE_EXPECTED = {
    "rej-instance-definition-only": ("InstanceDefsChild", "constant"),
    "rej-instance-variable-substituted": ("InstanceStateChild", "action"),
    "rej-instance-implicit-substitution": ("ImplicitChild", "action"),
    "rej-substitution-constant-by-state": ("LevelChild", "state"),
}


def source_sha256(source: str) -> str:
    return hashlib.sha256(source.encode("utf-8")).hexdigest()


def calibration_input_hashes() -> dict[str, str]:
    """Stable source fingerprints for a future, separately indexed rerun."""
    return {
        **{f"unicode/{spelling}": source_sha256(source)
           for spelling, source in EXERCISED_UNICODE_SOURCES.items()},
        **{f"enabled/{kind}": source_sha256(source)
           for kind, source in ENABLED_SOURCES.items()},
    }


def load_report(checkpoint: str) -> dict:
    return json.loads((EVIDENCE / checkpoint / "report.json").read_text(encoding="utf-8"))


def finding_keys(report: dict) -> set[tuple[str, str, str]]:
    return {
        (item["fixture"], item["engine"], item["fact"])
        for item in report["comparisons"] if item["status"] == "fail"
    }


def expected_findings() -> set[tuple[str, str, str]]:
    findings = {
        ("acc-actions", "sany", "levels"),
        ("rej-unicode-spelling", "sany", "outcome"),
        ("rej-unicode-spelling", "apalache", "outcome"),
    }
    for fixture in NAMED_INSTANCE_EXPECTED:
        findings |= {(fixture, "sany", "resolution"), (fixture, "sany", "levels")}
    return findings


def sany_observation(report: dict, fixture: str) -> dict:
    return next(row for row in report["observations"] if row["fixture"] == fixture and row["engine"] == "sany")
