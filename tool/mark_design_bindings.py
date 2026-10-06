"""Mark frozen page locations in packaged HTML without changing visible content.

The golden fixtures are internal baselines. This script deliberately reads their
paths but edits only app.html; code.html and screen.png remain references.
"""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT.parent / "energylens-common/docs/plans/support/golden_fixtures"
spec = importlib.util.spec_from_file_location("golden_extract", FIXTURES / "extract.py")
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PositionParser(module.PageParser):
    def __init__(self, raw: str):
        super().__init__()
        self.positions = {}
        self.line_starts = [0]
        for line in raw.splitlines(keepends=True):
            self.line_starts.append(self.line_starts[-1] + len(line))

    def _start(self, tag, pairs):
        parent = self.stack[-1] if self.stack else None
        base = parent["path"] if parent else ""
        path = f"{base}/{tag}[{self.counts.get((base, tag), 0) + 1}]"
        line, column = self.getpos()
        start = self.line_starts[line - 1] + column
        token = self.get_starttag_text()
        self.positions[path] = (start, token)
        super()._start(tag, pairs)


def main():
    manifest = {"revision": "mobile_design_2026_10_06_v1", "pages": {}}
    for fixture_path in sorted(FIXTURES.glob("*.json")):
        fixture = json.loads(fixture_path.read_text())
        page = fixture["page"]
        app_path = ROOT / "assets/design_pages" / page / "app.html"
        raw = app_path.read_text()
        parser = PositionParser(raw)
        parser.feed(raw)
        parser.close()
        text_paths = {}
        for segment in fixture["ordered_text_segments"]:
            if not segment["icon_glyph"]:
                text_paths.setdefault(segment["path"], []).append(segment["text"])
        controls = {
            control["path"]: control
            for control in fixture["controls"]
            if control["tag"] in {"a", "button", "input", "select", "textarea"}
        }
        replacements = []
        bindings = []
        actions = []
        fields = []
        for index, (path, texts) in enumerate(text_paths.items(), 1):
            marker = f"{page}_text_{index:03d}"
            bindings.append({"id": marker, "path": path, "text": texts})
            assert path in parser.positions, (page, path)
            replacements.append((path, f' data-el-bind="{marker}"'))
        action_number = field_number = 0
        for path, control in controls.items():
            assert path in parser.positions, (page, path)
            if control["tag"] in {"input", "select", "textarea"} and control["attributes"].get("type") not in {"button", "submit", "checkbox"}:
                field_number += 1
                marker = f"{page}_field_{field_number:03d}"
                fields.append({"id": marker, "path": path, "tag": control["tag"], "attributes": control["attributes"]})
                replacements.append((path, f' data-el-field="{marker}"'))
            else:
                action_number += 1
                marker = f"{page}_action_{action_number:03d}"
                actions.append({"id": marker, "path": path, "tag": control["tag"], "text": control.get("text", ""), "attributes": control["attributes"]})
                replacements.append((path, f' data-el-action="{marker}"'))
        edits = []
        for path, insertion in replacements:
            start, token = parser.positions[path]
            if insertion.strip() in token:
                continue
            offset = len(token) - (2 if token.endswith("/>") else 1)
            edits.append((start + offset, insertion))
        for offset, insertion in sorted(edits, reverse=True):
            raw = raw[:offset] + insertion + raw[offset:]
        app_path.write_text(raw)
        manifest["pages"][page] = {
            "bindings": bindings, "actions": actions, "fields": fields,
        }
    output = ROOT / "docs/design_page_binding_map.json"
    output.parent.mkdir(exist_ok=True)
    output.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()
