#!/usr/bin/env python3
"""A3: the entitlements match spec 3.2 exactly.

The expected lists are read from docs/SPEC.md section 3.2, so the spec stays the single source of
truth. Pass a built .app as the first argument to also check the signed entitlements of the app and
its Finder extension (needs codesign, macOS only)."""
import os
import plistlib
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PREFIX = "com.apple.security."


def expected():
    spec = open(os.path.join(ROOT, "docs", "SPEC.md")).read()
    section = spec[spec.index("### 3.2"):spec.index("### 3.3")]
    result = {}
    for label, key in (("App:", "app"), ("Finder extension:", "extension")):
        line = next(line for line in section.splitlines() if line.strip().startswith("- " + label))
        result[key] = {PREFIX + name for name in re.findall(r"`([a-z.\-]+)`", line)}
    return result


def keys(entitlements):
    return set(entitlements)


def check(name, entitlements, wanted, problems):
    got = keys(entitlements)
    for extra in sorted(got - wanted):
        problems.append(f"{name}: unexpected entitlement {extra}")
    for missing in sorted(wanted - got):
        problems.append(f"{name}: missing entitlement {missing}")
    groups = entitlements.get(PREFIX + "application-groups", [])
    if len(groups) != 1:
        problems.append(f"{name}: expected exactly one app group, found {len(groups)}")
    for key, value in entitlements.items():
        if key != PREFIX + "application-groups" and value is not True:
            problems.append(f"{name}: {key} should be true")


def main():
    wanted = expected()
    problems = []
    sources = {
        "app": os.path.join(ROOT, "App", "Untitled.entitlements"),
        "extension": os.path.join(ROOT, "FinderExtension", "FinderExtension.entitlements"),
    }
    for key, path in sources.items():
        with open(path, "rb") as handle:
            check(os.path.relpath(path, ROOT), plistlib.load(handle), wanted[key], problems)
    if len(sys.argv) > 1:
        app = sys.argv[1]
        for key, binary in (("app", app), ("extension", os.path.join(app, "Contents", "PlugIns", "UntitledFinderExtension.appex"))):
            output = subprocess.run(["codesign", "-d", "--entitlements", "-", "--xml", binary], capture_output=True, check=True).stdout
            check(os.path.basename(binary) + " (signed)", plistlib.loads(output) if output else {}, wanted[key], problems)
    if problems:
        print("\n".join(problems))
        sys.exit(1)
    print("Entitlements match spec 3.2:", {key: sorted(name[len(PREFIX):] for name in value) for key, value in wanted.items()})


main()
