#!/usr/bin/env python3
"""Checks Untitled.xcodeproj/project.pbxproj: it parses as an OpenStep plist, every object
reference resolves, and the targets carry the settings acceptance criteria A1–A3 depend on."""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class Parser:
    def __init__(self, text):
        self.text = text
        self.i = 0

    def skip(self):
        while self.i < len(self.text):
            if self.text.startswith("//", self.i):
                self.i = self.text.index("\n", self.i)
            elif self.text.startswith("/*", self.i):
                self.i = self.text.index("*/", self.i) + 2
            elif self.text[self.i].isspace():
                self.i += 1
            else:
                break

    def value(self):
        self.skip()
        c = self.text[self.i]
        if c == "{":
            self.i += 1
            result = {}
            while True:
                self.skip()
                if self.text[self.i] == "}":
                    self.i += 1
                    return result
                key = self.value()
                self.skip()
                assert self.text[self.i] == "=", f"expected = at {self.i}"
                self.i += 1
                result[key] = self.value()
                self.skip()
                assert self.text[self.i] == ";", f"expected ; at {self.i}"
                self.i += 1
        if c == "(":
            self.i += 1
            result = []
            while True:
                self.skip()
                if self.text[self.i] == ")":
                    self.i += 1
                    return result
                result.append(self.value())
                self.skip()
                if self.text[self.i] == ",":
                    self.i += 1
        if c == '"':
            self.i += 1
            out = []
            while self.text[self.i] != '"':
                if self.text[self.i] == "\\":
                    self.i += 1
                    out.append({"n": "\n", "t": "\t"}.get(self.text[self.i], self.text[self.i]))
                else:
                    out.append(self.text[self.i])
                self.i += 1
            self.i += 1
            return "".join(out)
        match = re.compile(r"[A-Za-z0-9_$/.:\-]+").match(self.text, self.i)
        assert match, f"unexpected {c!r} at {self.i}"
        self.i = match.end()
        return match.group(0)


def main():
    path = os.path.join(ROOT, "Untitled.xcodeproj", "project.pbxproj")
    document = Parser(open(path).read()).value()
    objects = document["objects"]
    problems = []

    def check_refs(value, owner):
        if isinstance(value, dict):
            for key, item in value.items():
                if key in ("isa", "remoteGlobalIDString"):
                    continue
                check_refs(item, owner)
        elif isinstance(value, list):
            for item in value:
                check_refs(item, owner)
        elif isinstance(value, str) and re.fullmatch(r"[0-9A-F]{24}", value) and value not in objects:
            problems.append(f"{owner} references missing object {value}")

    for identifier, obj in objects.items():
        check_refs(obj, identifier)
    if document["rootObject"] not in objects:
        problems.append("rootObject missing")

    targets = {o["name"]: o for o in objects.values() if o["isa"] == "PBXNativeTarget"}
    for name in ("Untitled", "UntitledFinderExtension"):
        if name not in targets:
            problems.append(f"target {name} missing")
    project = objects[document["rootObject"]]
    for config_id in objects[project["buildConfigurationList"]]["buildConfigurations"]:
        settings = objects[config_id]["buildSettings"]
        for key, expected in {"MACOSX_DEPLOYMENT_TARGET": "27.0", "ARCHS": "arm64", "SWIFT_VERSION": "6.0",
                              "SWIFT_STRICT_CONCURRENCY": "complete", "SWIFT_TREAT_WARNINGS_AS_ERRORS": "YES",
                              "ENABLE_HARDENED_RUNTIME": "YES", "ENABLE_APP_SANDBOX": "YES"}.items():
            if settings.get(key) != expected:
                problems.append(f"{objects[config_id]['name']}: {key} is {settings.get(key)!r}, expected {expected!r}")
    for target in targets.values():
        for config_id in objects[target["buildConfigurationList"]]["buildConfigurations"]:
            settings = objects[config_id]["buildSettings"]
            for key in ("INFOPLIST_FILE", "CODE_SIGN_ENTITLEMENTS"):
                if not os.path.exists(os.path.join(ROOT, settings.get(key, "?"))):
                    problems.append(f"{target['name']}: {key} points to a missing file")
    for obj in objects.values():
        if obj["isa"] == "XCLocalSwiftPackageReference" and not os.path.exists(os.path.join(ROOT, obj["relativePath"], "Package.swift")):
            problems.append("local package path has no Package.swift")
    # Every file in the navigator exists on disk, following each group's path.
    parents = {}
    for identifier, obj in objects.items():
        for child in obj.get("children", []) if obj["isa"] == "PBXGroup" else []:
            parents[child] = identifier

    def full_path(identifier):
        parts = []
        while identifier in objects:
            path = objects[identifier].get("path")
            if path:
                parts.insert(0, path)
            identifier = parents.get(identifier)
        return os.path.join(ROOT, *parts)

    for identifier, obj in objects.items():
        if obj["isa"] == "PBXFileReference" and obj.get("sourceTree") == "<group>" and not os.path.exists(full_path(identifier)):
            problems.append(f"file reference {obj['path']} does not exist at {full_path(identifier)}")
    sources = sum(len(objects[p]["files"]) for t in targets.values() for p in t["buildPhases"] if objects[p]["isa"] == "PBXSourcesBuildPhase")
    print(f"{sources} source files in build phases")
    print(f"{len(objects)} objects, {len(targets)} targets")
    if problems:
        print("\n".join(problems))
        sys.exit(1)
    print("project.pbxproj OK")


main()
