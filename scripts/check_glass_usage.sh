#!/usr/bin/env bash
# R1 (code audit): custom glass appears on exactly three surfaces (3.16): the menu bar panel and the
# Quick Rename panel (both hosted by GlassPanel), and the Review action bar.
set -euo pipefail
cd "$(dirname "$0")/.."
allowed='UntitledKit/Sources/UntitledUI/AppKit/GlassPanel.swift|UntitledKit/Sources/UntitledUI/Views/Main/Review/ReviewActionBar.swift'
found=$(grep -rlE 'NSGlassEffectView|glassEffect\(|GlassEffectContainer|\.buttonStyle\(\.glass' App FinderExtension UntitledKit/Sources --include='*.swift' || true)
unexpected=$(printf '%s\n' "$found" | grep -vE "^($allowed)$" | grep -v '^$' || true)
if [ -n "$unexpected" ]; then
    echo "error: custom glass outside the three allowed surfaces (3.16, R1):"; echo "$unexpected"; exit 1
fi
panels=$(grep -c 'GlassPanel(' UntitledKit/Sources/UntitledUI/AppKit/AppController.swift)
if [ "$panels" -ne 2 ]; then echo "error: expected 2 glass panels (menu bar, Quick Rename), found $panels"; exit 1; fi
echo "Glass audit OK: GlassPanel (menu bar panel, Quick Rename) and the Review action bar only."
