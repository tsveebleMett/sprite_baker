"""Run the real GDScript core tests with statement probes in disposable copies.

Usage: python tests/core_coverage.py --godot path/to/godot
Only .godot/core-coverage/ is generated. Production source files are never changed.
The denominator is executable logical statements inside functions; declarations,
comments, continuation lines, and else/elif labels are excluded. This measures
statement execution, not branch coverage.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
DESTINATION = ROOT / ".godot" / "core-coverage"


def bracket_delta(line: str) -> int:
    depth = 0
    quote = None
    escaped = False
    for character in line:
        if quote:
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == quote:
                quote = None
        elif character == "#":
            break
        elif character in "\"'":
            quote = character
        elif character in "([{":
            depth += 1
        elif character in ")]}":
            depth -= 1
    return depth


def instrument(path: Path) -> tuple[str, list[str]]:
    output = []
    probes = []
    in_function = False
    depth = 0
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        stripped = line.strip()
        if line.startswith(("func ", "static func ")):
            in_function = True
        elif line and not line[0].isspace() and not line.startswith("#"):
            in_function = False
        candidate = (
            in_function
            and line.startswith("\t")
            and depth == 0
            and stripped
            and not stripped.startswith(("#", "else:", "elif "))
        )
        if candidate:
            key = f"{path.name}:{number}"
            probes.append(key)
            indentation = line[: len(line) - len(line.lstrip())]
            output.append(f'{indentation}Coverage.hit("{key}")')
        output.append(line.replace("res://src/core/", "res://.godot/core-coverage/"))
        if line.startswith("extends "):
            output.append('const Coverage = preload("res://.godot/core-coverage/tracker.gd")')
        depth += bracket_delta(line)
    return "\n".join(output) + "\n", probes


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=str(ROOT / ".tools/godot/Godot_v4.6.1-stable_win64_console.exe"))
    parser.add_argument("--minimum", type=float, default=80.0)
    args = parser.parse_args()
    DESTINATION.mkdir(parents=True, exist_ok=True)
    targets = list(sorted((ROOT / "src/core").glob("*.gd")))
    probes = {}
    for path in targets:
        instrumented, identifiers = instrument(path)
        (DESTINATION / path.name).write_text(instrumented, encoding="utf-8")
        probes[path.name] = identifiers
    (DESTINATION / "tracker.gd").write_text(
        'extends RefCounted\nstatic var hits := {}\n'
        'static func hit(key: String) -> void:\n\thits[key] = true\n'
        'static func write_report() -> void:\n'
        '\tvar file := FileAccess.open("res://.godot/core-coverage/hits.json", FileAccess.WRITE)\n'
        '\tfile.store_string(JSON.stringify(hits))\n\tfile.close()\n',
        encoding="utf-8",
    )
    test = (ROOT / "tests/test_core.gd").read_text(encoding="utf-8-sig")
    test = test.replace("res://src/core/", "res://.godot/core-coverage/")
    test = test.replace("\tquit(1 if failures else 0)", '\tpreload("res://.godot/core-coverage/tracker.gd").write_report()\n\tquit(1 if failures else 0)')
    (DESTINATION / "test_core.gd").write_text(test, encoding="utf-8")
    process = subprocess.run([args.godot, "--headless", "--path", str(ROOT), "--script", "res://.godot/core-coverage/test_core.gd"], cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
    print(process.stdout, end="")
    print(process.stderr, end="", file=sys.stderr)
    if process.returncode:
        return process.returncode
    if "ERROR:" in process.stdout or "ERROR:" in process.stderr:
        return 1
    hits = json.loads((DESTINATION / "hits.json").read_text(encoding="utf-8"))
    total = sum(map(len, probes.values()))
    covered = sum(key in hits for identifiers in probes.values() for key in identifiers)
    summary = {}
    for name, identifiers in probes.items():
        missing = [int(key.rsplit(":", 1)[1]) for key in identifiers if key not in hits]
        percent = 100.0 * (len(identifiers) - len(missing)) / len(identifiers)
        summary[name] = {"statements": len(identifiers), "covered": len(identifiers) - len(missing), "percent": percent, "missing_lines": missing}
        print(f"{name}: {percent:.1f}% ({len(identifiers) - len(missing)}/{len(identifiers)}), missing lines: {missing}")
    percent = covered / total * 100.0
    summary["total"] = {"statements": total, "covered": covered, "percent": percent}
    (DESTINATION / "report.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(f"CORE STATEMENT COVERAGE: {percent:.1f}% ({covered}/{total}); required {args.minimum:.1f}%")
    return 0 if percent >= args.minimum else 1


if __name__ == "__main__":
    sys.exit(main())
