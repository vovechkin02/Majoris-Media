#!/usr/bin/env python3
"""Check Valadoc declaration summaries in project-owned Vala source."""

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
ACCESS = re.compile(r"^\s*(?:public|protected|private|internal)\s+")
SPECIAL = re.compile(r"^\s*(?:static\s+)?construct\s*\{|^\s*int\s+main\s*\(")


def is_declaration(line: str) -> bool:
    """Select declarations rather than assignments and control flow."""
    if SPECIAL.match(line):
        return True
    if not ACCESS.match(line):
        return False
    text = line.strip()
    return any(token in text for token in (" class ", " interface ", " enum ", " errordomain ", " signal ", "(", "{", ";"))


def summary_before(lines: list[str], index: int) -> bool:
    """Allow annotations between a declaration and its adjacent Valadoc block."""
    pos = index - 1
    while pos >= 0 and lines[pos].lstrip().startswith("["):
        pos -= 1
    if pos < 0 or not lines[pos].strip().endswith("*/"):
        return False
    end = pos
    while pos >= 0 and "/**" not in lines[pos]:
        pos -= 1
    if pos < 0:
        return False
    text = " ".join(lines[pos : end + 1]).replace("/**", "").replace("*/", "").replace("*", "").strip()
    return len(text) >= 12


def main() -> int:
    """Report source documentation coverage and return a failing status for gaps."""
    failures = []
    count = 0
    for base in ("src", "examples", "tests"):
        for file in sorted((ROOT / base).rglob("*.vala")):
            lines = file.read_text(encoding="utf-8").splitlines()
            for index, line in enumerate(lines):
                if not is_declaration(line):
                    continue
                count += 1
                if not summary_before(lines, index):
                    failures.append(f"{file.relative_to(ROOT)}:{index + 1}: {line.strip()}")
    c_count = 0
    for path in sorted((ROOT / "native").rglob("*")):
        if path.suffix not in {".c", ".h"}:
            continue
        lines = path.read_text(encoding="utf-8").splitlines()
        for index, line in enumerate(lines):
            if not re.search(r"\bmediakit_engine_(?:is_available|unavailable_reason)\s*\(", line):
                continue
            c_count += 1
            pos = index - 1
            if line.lstrip().startswith("mediakit_engine_"):
                pos -= 1  # C return type on the preceding line.
            if pos < 0 or not lines[pos].strip().endswith("*/"):
                failures.append(f"{path.relative_to(ROOT)}:{index + 1}: undocumented C function")
    for failure in failures:
        print("UNDOCUMENTED:", failure)
    print(f"Vala and C declaration summaries: {count + c_count - len(failures)}/{count + c_count}")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
