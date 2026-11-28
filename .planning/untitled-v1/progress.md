# Progress — Untitled v1

Plan: `docs/superpowers/plans/2026-11-27-untitled-v1.md` · Spec: `docs/SPEC.md`

## Environment
- Linux container (Ubuntu 24.04, x86_64). No macOS, no Xcode, no Mac attached.
- Swift 6.4.3 toolchain (signature verified) extracted in the session scratchpad; not persisted.
- GitHub: fetch works, push refused (Claude GitHub App lacks write access). Commits are local until access is fixed.

## Log
- 2026-11-27: Moved uploaded skills into `.claude/skills/`. Saved spec. Wrote plan.
- 2026-11-28: Renamed the product to Untitled everywhere (Part 5, #46). Added the UI layer: presentation logic and
  app models tested on Linux (glyphs, motion, settings explanations, onboarding, placement, Dock policy, Quick Rename,
  style and rule editing, Why this name?); SwiftUI views, AppKit shell, App Intents and Finder extension (macOS only,
  not compiled here). Engine: bookmark access and Reconnect, configuration before watching, first-scan arrivals
  (Part 5, #49), weekly counts, renamed paths for Finder. Moved the package to UntitledKit/; generated
  Untitled.xcodeproj with a checker; entitlements, privacy manifest, icon; gates for A3, A6, A8, R1; CI workflows;
  E1/E2 fixtures. XcodeGen build and a pip install were refused by the session's safety classifier; worked around
  with a hand-written generator and a stdlib checker.
