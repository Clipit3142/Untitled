#!/usr/bin/env bash
# A8: no TODO/FIXME markers, debug menus or test hooks in shipping code.
set -euo pipefail
cd "$(dirname "$0")/.."
status=0
shipping=(App FinderExtension UntitledKit/Sources)
if grep -rnE '\b(TODO|FIXME|XXX|HACK)\b' "${shipping[@]}" --include='*.swift' --include='*.c' --include='*.h' --include='*.plist'; then
    echo "error: markers found in shipping code (A8)"; status=1
fi
# Debug menus and test-only switches must not exist in shipping code.
if grep -rnE '(Debug Menu|"Debug"|ProcessInfo\.processInfo\.environment\[)' "${shipping[@]}" --include='*.swift'; then
    echo "error: debug menus or environment-driven test hooks found in shipping code (A8)"; status=1
fi
# The journal harness is a test tool and must not be part of the app.
if grep -rn 'JournalHarness\|untitled-journal-harness' App FinderExtension Untitled.xcodeproj; then
    echo "error: the test harness is referenced by the app (A8)"; status=1
fi
[ "$status" -eq 0 ] && echo "Release hygiene OK: no markers, debug menus or test hooks in shipping code."
exit "$status"
