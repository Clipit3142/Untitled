#!/usr/bin/env python3
"""A6: UntitledCore and UntitledFS have at least 90% line coverage.

Runs `swift test --enable-code-coverage` in UntitledKit (skip with --no-run to reuse the last run),
then sums line coverage per module from the llvm-cov export SwiftPM writes."""
import glob
import json
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PACKAGE = os.path.join(ROOT, "UntitledKit")
MODULES = ("UntitledCore", "UntitledFS")
THRESHOLD = 90.0


def tool(name):
    """llvm tools from the toolchain on PATH, or through xcrun on macOS."""
    if shutil.which(name):
        return [name]
    return ["xcrun", name]


def merged_export(codecov):
    """On Linux every test target runs as its own bundle and SwiftPM exports only the last one,
    so merge every raw profile and export across all test binaries."""
    profdata = os.path.join(codecov, "merged.profdata")
    raws = glob.glob(os.path.join(codecov, "*.profraw"))
    subprocess.run(tool("llvm-profdata") + ["merge", "-sparse", "-o", profdata] + raws, check=True)
    products = os.path.dirname(codecov)
    binaries = sorted(glob.glob(os.path.join(products, "*Tests.so")) + glob.glob(os.path.join(products, "*.xctest")))
    arguments = [binaries[0]] + [item for binary in binaries[1:] for item in ("-object", binary)]
    output = subprocess.run(tool("llvm-cov") + ["export", "-summary-only", "-instr-profile", profdata] + arguments,
                            check=True, capture_output=True, text=True).stdout
    return json.loads(output)["data"][0]["files"]


def main():
    if "--no-run" not in sys.argv:
        subprocess.run(["swift", "test", "--enable-code-coverage"], cwd=PACKAGE, check=True)
    path = subprocess.run(["swift", "test", "--show-codecov-path"], cwd=PACKAGE, check=True,
                          capture_output=True, text=True).stdout.strip()
    data = json.load(open(path))["data"][0]["files"]
    if not all(any(f"/Sources/{module}/" in f["filename"] for f in data) for module in MODULES):
        data = merged_export(os.path.dirname(path))
    failed = False
    for module in MODULES:
        prefix = os.path.join(PACKAGE, "Sources", module) + os.sep
        files = [f for f in data if f["filename"].startswith(prefix)]
        count = sum(f["summary"]["lines"]["count"] for f in files)
        covered = sum(f["summary"]["lines"]["covered"] for f in files)
        percent = 100.0 * covered / count if count else 0.0
        print(f"{module}: {percent:.1f}% of {count} lines ({len(files)} files)")
        for f in sorted(files, key=lambda f: f["summary"]["lines"]["percent"])[:5]:
            print(f"    {f['summary']['lines']['percent']:5.1f}%  {os.path.relpath(f['filename'], PACKAGE)}")
        if percent < THRESHOLD:
            print(f"error: {module} is below {THRESHOLD}% (A6)")
            failed = True
    sys.exit(1 if failed else 0)


main()
