#!/usr/bin/env python3
"""Statically validate Meson source inventories, layering, XML and formatting."""

from pathlib import Path
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def verify_sources(folder: str) -> list[str]:
    """Compare each library's Vala source files with its Meson source list."""
    root = ROOT / folder
    sources = set(re.findall(r"'([^']+\.vala)'", (root / "meson.build").read_text()))
    expected = {str(file.relative_to(root)) for file in root.rglob("*.vala")}
    return [f"{folder}: Vala source list differs: missing={expected - sources}, extra={sources - expected}"] if sources != expected else []


def verify_xml() -> list[str]:
    """Require XML resources to reference correctly named GTK widget templates."""
    errors = []
    files = {node.text for node in ET.parse(ROOT / "data/media-kit-gtk.gresource.xml").findall(".//file")}
    expected = {
        "ui/media-view.ui": "MediaKitView",
        "ui/media-controls.ui": "MediaKitControls",
        "ui/gpu-next-controls.ui": "MediaKitGpuNextControls",
    }
    if files != set(expected):
        errors.append("XML resource file list differs from widget templates")
    for path, name in expected.items():
        template = ET.parse(ROOT / "data" / path).getroot().find("template")
        if template is None or template.attrib.get("class") != name:
            errors.append(f"Invalid GTK template: {path}")
    return errors


def verify_layering() -> list[str]:
    """Reject any direct reference to the GTK toolkit from headless core files."""
    errors = []
    for file in (ROOT / "src/core").rglob("*.vala"):
        if re.search(r"\b(?:Gtk|Gdk|Adw)\.", file.read_text()):
            errors.append(f"GTK symbol in Core: {file.relative_to(ROOT)}")
    meson = (ROOT / "meson.build").read_text()
    if "if get_option('gtk')" not in meson or "subdir('src/core')" not in meson:
        errors.append("Meson must build Core unconditionally, GTK conditionally")
    return errors


def verify_text() -> list[str]:
    """Check relevant handwritten files for line-ending and whitespace defects."""
    errors = []
    extensions = {".vala", ".c", ".h", ".md", ".py", ".xml", ".install", ".deps"}
    names = {"meson.build", "meson.options", ".editorconfig", "control", "rules", "changelog"}
    for file in ROOT.rglob("*"):
        if not file.is_file() or not (file.suffix in extensions or file.name in names):
            continue
        if file.name == "engineering-standards-v1.8.md":
            continue  # Preserve the user-supplied standard verbatim.
        try:
            source = file.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            errors.append(f"Non-UTF-8 file: {file.relative_to(ROOT)}")
            continue
        if not source.endswith("\n") or "\r" in source:
            errors.append(f"Invalid line endings: {file.relative_to(ROOT)}")
        if any(line.rstrip(" \t") != line for line in source.splitlines()):
            errors.append(f"Trailing whitespace: {file.relative_to(ROOT)}")
    return errors


def main() -> int:
    """Check source structure, explicitly without claiming that compilation ran."""
    errors = verify_sources("src/core") + verify_sources("src/gtk") + verify_xml()
    errors += verify_layering() + verify_text()
    for error in errors:
        print("FAIL:", error)
    if errors:
        return 1
    print("PASS: static source, XML, GTK/Core separation and text checks")
    print("NOT RUN: Vala/Meson native compilation or runtime checks")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
