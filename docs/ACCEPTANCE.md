# Acceptance status

Part 4 of the spec says v1 is complete only when every criterion passes on every matrix configuration, using the
build that ships. **v1 is not complete.** This page says, criterion by criterion, what was verified, what is built but
can only be verified on a Mac, and what needs people or Apple.

Everything here was done in a Linux container (x86_64, Swift 6.4.3). There was no Mac, no Xcode and no macOS SDK, so:

- The platform-independent modules (Core, FS, Store, Model, Extract, Engine, and the UI module's presentation logic and
  app models) were built with zero warnings and tested, 224 tests in 7 suites, all passing in debug (with coverage) and in release.
- The macOS-only code (SwiftUI views, the AppKit shell, the Foundation Models adapter, the Vision/PDFKit/Quick Look
  readers, FSEvents, security-scoped bookmarks, coordinated moves, App Intents, the Finder extension) was written and
  reviewed but **never compiled**. The first build on a Mac will probably surface compile errors to fix.

Legend:

- **Pass (here)**: an automated check passes in this environment. On a Mac the same check still has to pass, with the
  real Apple frameworks where the criterion involves them.
- **Built, verify on Mac**: implemented; the check needs macOS, real hardware or the full app running.
- **Needs people or Apple**: App Review, testers, raters, designers, trademark search.
- **Not met**: a known gap.

Tests are in `UntitledKit/Tests`; gates are in `scripts/`; CI runs both (`.github/workflows`).

## A. Build and platform

| | Status | Evidence |
|---|---|---|
| A1 | Built, verify on Mac | The package builds with zero warnings on Linux (`swift build --build-tests`). The app and extension have never been compiled. CI runs one `xcodebuild` command and fails on any warning. |
| A2 | Built, verify on Mac | `scripts/check_xcodeproj.py` checks deployment target 27.0 and `ARCHS = arm64`; CI checks the binary with `lipo`. |
| A3 | Pass (here) | `scripts/check_entitlements.py` diffs both entitlement files against the list it reads from spec 3.2. CI repeats it on the signed app. |
| A4 | Needs people or Apple | No network entitlement; privacy manifest declares no collected data. App Review not attempted. |
| A5 | Pass (here) for the code; About panel on Mac | GRDB 7.9.0 is the only dependency (`Package.resolved`). Its license is in `Licenses.aboutCredits` (tested) and the About panel. |
| A6 | Pass (here) for coverage; the 100 runs need a Mac | `scripts/coverage.py`: UntitledCore 95.3%, UntitledFS 93.4% (Linux; Darwin-only branches are compiled out here). Here the non-Core suites ran 5 times and the Core suite twice, all without a failure; `stability.yml` runs it 100 times in a row on macOS. |
| A7 | Built, verify on Mac | `SystemServices.handOffToRunningCopy()`: a second copy signals the first and quits. |
| A8 | Pass (here) | `scripts/check_release_hygiene.sh`: no markers, debug menus or environment-driven test hooks in shipping code; the engine's test helper lives in the test target. |

## B. Onboarding

| | Status | Evidence |
|---|---|---|
| B1 | Built, verify on Mac | Return continues, ⌘[ goes back, every control is a standard control with a label. VoiceOver run needed. |
| B2 | Pass (here) for states; settings pane on Mac | `AppleIntelligencePaneTests`. The System Settings URL must be confirmed on macOS 27. |
| B3 | Pass (here) for the logic | `OnboardingModelTests.folders`: picker opens on Desktop; another pick is added and the UI says so. |
| B4 | Pass (here) for the logic | Downloads is added without a picker. Entitlement access verified only on Mac. |
| B5 | Pass (here) | `StyleInference` fixtures (H10) and the 10-file minimum with its reason (`AppModelTests.learnFromFolder`). |
| B6 | Pass (here) for the tip; latency on Mac | The tip appears at 10 s (`OnboardingModelTests.demo`). The 3.19 latency needs the reference Mac. |
| B7 | Pass (here) | `AppModelTests.onboardingGatesWatching`: nothing watched before finishing, resume at the same step (Part 5, #49). |
| B8 | Built, verify on Mac | Polls `FIFinderSyncController.isExtensionEnabled` every second while step 6 is open. |

## C. Access and watching

| | Status | Evidence |
|---|---|---|
| C1 | Built, verify on Mac | Bookmarks are resolved and opened at launch (`EngineTests.bookmarksAndReconnect` with path bookmarks). Restart and OS-restart counts need a Mac. |
| C2 | Pass (here) | Missing folder within 5 s; moved folder at launch; Reconnect resumes watching. |
| C3 | Pass (here) | 100 nested fixtures, 0 processed. |
| C4 | Pass (here) | Files added while quit, filtered by date added; also on a folder's first scan. |
| C5 | Pass (here) for the logic; real volumes on Mac | `EngineTests.disconnectedVolumeResumes`: Disconnected within 5 s, no event loop, watching resumes within 10 s. |
| C6 | Pass (here) for the policy; real volumes on Mac | Volume types are refused with an explanation (`WatchingTests`). |
| C7 | Pass (here) | Project-like folders need confirmation. |

## D. Intake and eligibility

| | Status | Evidence |
|---|---|---|
| D1 | Pass (here) with the polling watcher | `LargeFileTests` (2 GB over 60 s, `UNTITLED_SLOW_TESTS=1`). Repeat with FSEvents on a Mac. |
| D2 | Built, verify on Mac | Temporary-name downloads and renames from in-progress names are covered (Part 5, #47); real Safari, Chrome and Firefox runs needed. |
| D3 | Built, verify on Mac | Screenshot detection by metadata and name is tested; every shortcut needs a real Mac. |
| D4 | Pass (here) | Every 3.6 exclusion has a fixture. Dataless iCloud files are metadata-only by logic; real iCloud on a Mac. |
| D5 | Pass (here) | ≥ 400 names including every macOS language's screenshot name. |
| D6 | Pass (here) | 11 files at once: 0 renames, one group, one notification. |
| D7 | Pass (here) | 1,000 scripted races, 0 renames. |
| D8 | Pass (here) | |
| D9 | Pass (here) | |

## E. Extraction

| | Status | Evidence |
|---|---|---|
| E1 | Not met | Fixtures for every type that can be generated are in `Fixtures/` (`make_fixtures.py`). Text, Markdown and HTML pass here; the other types have macOS tests (`AppleFixtureTests`, HEIC made with ImageIO) that have not run. Pages, Numbers and Keynote fixtures must be saved from the apps; their test fails until they exist. |
| E2 | Built, verify on Mac | `AppleFixtureTests.pdfPageLimit` and `protectedPDF`. |
| E3 | Built, verify on Mac | Images are downscaled through ImageIO thumbnails; memory needs measuring with a 100-megapixel image. |
| E4 | Pass (here) for stored data | Extracted text never reaches the databases or temporary files; stored fields are capped at 200 characters. File-activity tracing (fs_usage) over 100 runs on a Mac is still needed. |
| E5 | Pass (here) for the timeline | 50 scripted captures while switching apps. Real screenshots on a Mac. |
| E6 | Pass (here) | |

## F. Model

| | Status | Evidence |
|---|---|---|
| F1 | Pass (here) by construction; runtime on Mac | No network entitlement (A3 gate). A network monitor during the full test run on a Mac is still needed. |
| F2 | Pass (here) with a fake model | Greedy sampling, 50 identical runs. Repeat with the on-device model. |
| F3 | Pass (here) | Every availability state uses Basic naming and shows the status. |
| F4 | Pass (here) | Every error-table row injected through a fake generator. |
| F5 | Pass (here) | 1,000 fixtures within the budget. |
| F6 | Pass (here) | 50 arrivals in order. |
| F7 | Pass (here) | |
| F8 | Needs people or Apple | Needs the section Q corpus. |

## G. Guards

G1–G7: **Pass (here)**. Date and source tracing, 1,000 PII fixtures, never-include words, 200 injection fixtures,
100,000 random sanitizer inputs, Windows-safe names.

## H. Styles and formatter

H1–H10: **Pass (here)**, including 1,000,000 random style/field combinations (passes in debug and in release). H7's on-screen explanations
(Styles shows each `StyleIssue`) are built and need a Mac to see.

## I. Learning

I1–I5: **Pass (here)**.

## J. File safety

| | Status | Evidence |
|---|---|---|
| J1 | Pass (here) | 10,000-operation chaos test across two folders. |
| J2 | Pass (here) | |
| J3 | Pass (here) | kill -9 at random points across 1,000 operations (`untitled-journal-harness`). |
| J4 | Pass (here) | |
| J5 | Built, verify on Mac | Moves go through `NSFileCoordinator` (`CoordinatedMove`). Preview, TextEdit and Pages need checking. |
| J6 | Pass (here) for extended attributes; Finder tags and comments on Mac | Attributes, including quarantine, are byte-identical after rename, move and undo. |
| J7–J9 | Pass (here) | |

## K. Organizing

K1–K4: **Pass (here)**.

## L. Undo and history

L1 is **built, verify on Mac** for on-screen timing (the engine emits the change immediately). L2–L7: **Pass (here)**.

## M. Review and Quick Rename

| | Status | Evidence |
|---|---|---|
| M1 | Built, verify on Mac | Shortcuts are wired in `ReviewView`; VoiceOver run needed. |
| M2 | Pass (here) | Field edits re-format without the model; `WhyThisNameTests` covers every part of 500 random names. |
| M3 | Pass (here) | |
| M4 | Pass (here) for accept and cancel; U2 on Mac | 500 items with progress; cancel leaves the rest untouched. |
| M5 | Pass (here) for Return, Esc and ⌘R; latency on Mac | `QuickRenameTests`. |
| M6 | Pass (here) for the logic | Picker opens on the file's folder; declining leaves the file untouched and offers Copy name. |

## N. Menu bar

| | Status | Evidence |
|---|---|---|
| N1 | Pass (here) for shapes; real menu bars on Mac | Five vector glyphs, distinct in grayscale at 1x and 2x (`docs/design/menu-bar-glyphs.png`). |
| N2 | Pass (here) for placement; dismissal on Mac | 5,000 random screen layouts, never off-screen. Click outside, Esc and second click are wired. |
| N3 | Built, verify on Mac | Undo, Show in Finder, and drag-out as the file. |
| N4 | Pass (here) | |

## O. Windows and settings

| | Status | Evidence |
|---|---|---|
| O1 | Pass (here) for the policy; Dock on Mac | `DockPolicyTests`; leaves the Dock 0.5 s after the last window closes. |
| O2 | Built, verify on Mac | Window frames autosave by name; the sidebar selection is saved. Split-view column widths rely on the system and are unverified. |
| O3 | Built, verify on Mac | Activity search over 100,000 entries is ≤ 200 ms here; scrolling hitches need ProMotion hardware. |
| O4 | Pass (here) | Every setting has a one-line explanation (`SettingsCatalogTests`), shown under each control. |
| O5 | Pass (here) | Verified in the databases; Reset also restarts onboarding. |
| O6 | Pass (here) | |

## P. Notifications and integrations

| | Status | Evidence |
|---|---|---|
| P1 | Pass (here) by inspection | Permission is requested only from onboarding step 6 (`OnboardingModel.requestNotifications`). |
| P2 | Built, verify on Mac | Actions run in the background through the notification delegate, registered before launch finishes. |
| P3 | Pass (here) | |
| P4 | Pass (here) for the handoff; Finder on Mac | Granted folders and renamed paths are shared through the app group (Part 5, #51). |
| P5 | Pass (here) | Forged, unknown, malformed and stale IDs do nothing. |
| P6 | Pass (here) for the engine; Shortcuts and Siri on Mac | Clear errors for files outside granted folders. |

## Q. Naming quality benchmark

Q1–Q4: **Needs people or Apple** (a 400-file corpus, two blind raters and a tie-breaker, on both OS versions).
Q5–Q6: **Pass (here)** for the formatter and determinism with a fake model; the corpus runs need a Mac.

## R. Visual design and glass

| | Status | Evidence |
|---|---|---|
| R1 | Pass (here) as a code audit | `scripts/check_glass_usage.sh`: glass only in the two panels and the Review action bar. Visual audit on a Mac. |
| R2, R3 | Built, verify on Mac | |
| R4 | Not met | The icon exists as an asset catalog (`docs/design/app-icon.svg`); the Icon Composer file with Default, Dark, Clear and Tinted variants has not been made. |
| R5 | Pass (here) | The glyphs are vector paths drawn into template images; everything else is SF Symbols. |
| R6 | Needs people or Apple | |

## S. Motion

S1 and S2: **Pass (here)** for the timing table and the Reduce Motion rules (`MotionTests`); curves, haptics and the
static glyph need checking on a Mac. S3: **Built, verify on Mac**.

## T. Accessibility

T1–T4: **Built, verify on Mac**. Rows read naturally (`RowTextTests`), controls are labeled, color is never the only
signal (the Low badge has an icon and text).

## U. Performance

U1–U4: **Built, verify on Mac** on the reference MacBook Air. Activity search (100,000 entries) and the style
preview meet their targets here.

## V. Energy

V1: **Built, verify on Mac**. V2–V4: **Pass (here)** for the logic (pauses, resume within 10 s, backoff schedule).

## W. Privacy and security

W1–W4: **Pass (here)**.

## X. Reliability

| | Status | Evidence |
|---|---|---|
| X1 | Needs people or Apple | 72-hour soak on a Mac. |
| X2 | Needs people or Apple | Two-week beta with ≥ 50 testers. |
| X3 | Built, verify on Mac | |
| X4 | Pass (here) | |
| X5 | Pass (here) | A bookmark that doesn't resolve needs Reconnect once, with no retry loop. |

## Y. Release gates

| | Status | Evidence |
|---|---|---|
| Y1 | Not met | Needs a release-candidate binary. |
| Y2 | Needs people or Apple | “Untitled” is a common word, which can make a trademark and an App Store listing hard to clear. |
| Y3 | Not met | The week-1 spikes (3.21) need a Mac and have not been run. |
