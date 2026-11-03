"""Regression probe: catalog refresh must use the selected Mirrors source."""

import json
import sys
import tempfile
from pathlib import Path
from unittest.mock import patch

repo = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(repo / "tools/distribution"))
import refresh_identity

with tempfile.TemporaryDirectory(prefix="mw12-selected-source-") as temporary:
    selected = Path(temporary)
    (selected / "Shell").mkdir()
    (selected / "Shell/Version.lean").write_text(
        'namespace Shell.Version\ndef version : String := "0.0.9"\nend Shell.Version\n'
    )
    catalog_path = selected / "catalog.json"
    catalog = json.loads((repo / "catalog/framework-catalog.json").read_text())
    catalog_path.write_text(json.dumps(catalog))
    refs = {entry["componentRef"]["componentId"]: entry["componentRef"]
            for entry in catalog["components"]}
    with patch.object(refresh_identity, "MIRRORS", selected):
        refreshed, _ = refresh_identity.update_catalogs(
            refs, selected, catalog_path=catalog_path,
            write_component_records=False)
    observed = next(entry["product"]["version"] for entry in refreshed["components"]
                    if entry["componentRef"]["componentId"] == "mirrors")
    print(json.dumps({"selectedSourceVersion": "0.0.9",
                      "observedCatalogVersion": observed}))
    assert observed == "0.0.9", "catalog used the running tool checkout instead of selected source"
