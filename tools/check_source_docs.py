#!/usr/bin/env python3
"""Validate adjacent declaration documentation for Vala and native C code."""

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
ACCESS = re.compile(r"^\s*(?:public|protected|private|internal)\s+")
SPECIAL = re.compile(r"^\s*(?:static\s+)?construct\s*\{|^\s*int\s+main\s*\(")
C_FUNCTION = re.compile(r"^\s*(?:static\s+)?(?:void|gboolean|const gchar\s*\*|gint|"
                        r"MediaKitEngine\s*\*|MediaKitRenderer\s*\*)\s*$")


def is_declaration(line: str) -> bool:
    """Recognize a Vala member declaration without mistaking normal statements."""
    if SPECIAL.match(line):
        return True
    if not ACCESS.match(line):
        return False
    text = line.strip()
    return any(token in text for token in
               (" class ", " interface ", " enum ", " errordomain ", " signal ", "(", "{", ";"))


def summary_before(lines: list[str], index: int) -> bool:
    """Require a meaningful documentation block immediately before declaration."""
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
    content = " ".join(lines[pos:end + 1]).replace("/**", "").replace("*/", "")
    return len(content.strip(" *\n")) >= 12


def check_vala() -> tuple[list[str], int]:
    """Inspect handwritten Vala source and example/test declarations."""
    failures = []
    count = 0
    for base in ("src", "examples", "tests"):
        for file in sorted((ROOT / base).rglob("*.vala")):
            lines = file.read_text(encoding="utf-8").splitlines()
            for index, line in enumerate(lines):
                if is_declaration(line):
                    count += 1
                    if not summary_before(lines, index):
                        failures.append(f"{file.relative_to(ROOT)}:{index + 1}: Vala")
    return failures, count


def check_c() -> tuple[list[str], int]:
    """Check native function comments at the definition, without counting prototypes."""
    failures = []
    count = 0
    for file in sorted((ROOT / "native").rglob("*.c")):
        lines = file.read_text(encoding="utf-8").splitlines()
        for index, line in enumerate(lines[:-1]):
            if not C_FUNCTION.match(line):
                continue
            if not re.match(r"^[A-Za-z_]\w*\(", lines[index + 1].strip()):
                continue
            count += 1
            if not summary_before(lines, index):
                failures.append(f"{file.relative_to(ROOT)}:{index + 1}: C")
    return failures, count


def main() -> int:
    """Report full documented declaration counts and fail on missing summaries."""
    vala_errors, vala_count = check_vala()
    c_errors, c_count = check_c()
    for failure in vala_errors + c_errors:
        print("UNDOCUMENTED:", failure)
    count = vala_count + c_count
    print(f"Documented Vala/C definitions: {count - len(vala_errors) - len(c_errors)}/{count}")
    return 1 if vala_errors or c_errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
