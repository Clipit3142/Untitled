# Nomen — Product Specification

This is the source of truth for Nomen v1. If a criterion in Part 4 is wrong, the spec is changed first and the change is logged in Part 5.

---

## Part 1 — Brainstorm

### Concept

Nomen is a menu bar app that watches folders like Desktop and Downloads. It reads each new file on the Mac itself (screenshots, PDFs, scans, photos, office files) and renames it in your naming style. It can also file things into folders.

### Feature ideas

**Core**

- Auto-rename new screenshots and downloads.
- A hands-off mode, and a "suggest first" mode.
- Undo for everything, plus a searchable history.
- Bulk-rename an existing messy folder, with a before/after preview.
- Move files into folders after renaming.

**Naming preferences**

- Templates built from tokens:
  - date, document type, company/source, subject, app, original name
  - fixed text, such as an "ACME_" prefix
- Case: Title Case, Sentence case, lowercase, UPPERCASE, camelCase, PascalCase.
- Spacing: separate settings for the gap between words and the gap between parts (space, hyphen, underscore, dot, en dash).
- Length: a maximum character count, a maximum number of subject words, and a rule for which parts get cut first.
- Dates:
  - format: 2026-11-27, 20261127, 27.11.2026, and others
  - which date: the one on the document, the capture date, or the date added
  - position in the name, and an optional time
- Characters: name language, accent removal, ASCII-only, emoji on/off, Windows-safe names.
- Vocabulary:
  - replacements like "Bill → Invoice"
  - fixed abbreviations and brand casing (iPhone, macOS)
  - banned words, and dropping filler words
- Different styles per folder and per file type (screenshots vs documents).
- Learning a style: from a folder you've already named well, from a few example names, or from your edits to suggestions.
- Plain-words style: describe your style in words, and the model turns it into settings.

**Smart extras**

- Leave files alone if they already have good names.
- "Why this name?" shows the evidence behind each part.
- Privacy guard: never put card numbers, IBANs or email addresses in names.
- Detect which app a screenshot came from.
- Keep the original name in the file's metadata.
- Finder tags, duplicate detection, naming voice memos from transcripts, and cleaning up old screenshots.

### UI ideas

- A menu bar panel with recent renames and one-click undo.
- A toast near the screenshot thumbnail.
- A Spotlight-style "Quick Rename" panel from Finder's right-click menu.
- A keyboard-driven review queue with Quick Look.
- A style editor with draggable token chips and a live preview.
- Liquid Glass everywhere, including glass cards for each file.
- The old name dissolving into the new one, and an animated menu bar icon while it works.
- Onboarding that asks for a screenshot and names it live.
- A haptic tick when chips snap into place.

### How it could work

- Watching: FSEvents, per-file dispatch sources, polling, or Spotlight queries.
- Reading files: Vision OCR, PDFKit, Quick Look thumbnails, and metadata (download URL, capture date).
- Model and API options:
  - Apple's on-device model via the Foundation Models framework.
  - Apple's larger server models on Private Cloud Compute, through the same session API. [dev](https://dev.to/hariharanjagan/whats-new-in-apples-foundation-models-framework-at-wwdc-2026-5227)
  - Cloud APIs with the user's key. The framework now works with cloud models like Claude and Gemini, or any provider that conforms to its language model protocol. [apple](https://developer.apple.com/wwdc26/guides/machine-learning/)
  - Local models via MLX or Ollama.
- Prompting: ask the model for the finished filename, with the style written into the prompt.
- Filing: the model picks a folder, or rules decide.
- Renaming: FileManager move.
- Integration: a Finder extension, the Services menu, Shortcuts/Siri, or a global hotkey that renames the current Finder selection.
- Distribution: the Mac App Store, or a direct download with Sparkle updates.

---

## Part 2 — What the brainstorm missed, and the decisions

### Gaps and errors

- LLMs don't reliably follow formatting rules like case, separators, length and date format.
  **Fix:** the model returns only fields (type, source, subject, which date), and deterministic code builds the name. Preferences become guarantees, but they still inform the model through the word budget, vocabulary, language and approved examples. This is the central design decision.
- Renaming well-named files would anger users. **Fix:** by default, only generic names (Screenshot…, IMG_1234, document (3), scan0001, UUIDs) are touched.
- Files still being written (downloads, large copies) could be renamed mid-write. **Fix:** a stability gate and a list of temp names to ignore.
- The sandbox blocks renaming without access to the file's folder, even for dragged-in files. **Fix:** every rename happens inside a folder the user granted. Dropping a file from anywhere else triggers a one-time folder grant.
- Nomen's own renames fire file events that could trigger it again. **Fix:** own-operation suppression plus a marker on each processed file.
- Races: another app can create the target name between the check and the rename. **Fix:** an exclusive rename that fails instead of overwriting.
- A crash mid-operation leaves the history wrong. **Fix:** a write-ahead journal.
- Hallucinated dates and companies. **Fix:**
  - dates are chosen only from dates actually found in the file
  - a source must appear in the file's text, its download domain, or the app name
- Sensitive data in names. Filenames leak into sync services, Recents and shared links. **Fix:** a PII guard.
- Prompt injection through file content. **Fix:** fields only, a strict sanitizer, and moves only through user rules.
- Apple Intelligence off or missing, refusals, context overflow. **Fix:** a deterministic Basic naming path and an explicit error policy.
- Rate limits. Rate limiting applies when the device is on battery and the process is running in the background. An app with UI running in the foreground reportedly has no rate limit. A menu bar app is mostly background. **Fix:**
  - a queue with backoff
  - non-streaming calls
  - a "wait until plugged in" option
  - a day-one spike to measure the real limits [apple](https://developer.apple.com/forums/thread/789788?answerId=845702022) [apple](https://developer.apple.com/forums/thread/787737)
- Huge extracted text. **Fix:** token-counted budgets.
- iCloud files that aren't downloaded would be pulled down just by reading them. **Fix:** skip them.
- Bundles, symlinks and code projects break when renamed. **Fix:** skip packages and links, and warn when a watched folder looks like a project.
- Filename rules:
  - a 255-byte limit
  - forbidden ":" and "/"
  - Unicode normalization
  - invisible direction-override characters, which can disguise ".exe" files

  **Fix:** a strict sanitizer.
- Extensions: .tar.gz, uppercase .JPG, files with no extension. **Fix:** explicit rules.
- Letting the model pick folders is unpredictable, and a wrong move loses the file. **Fix:** files move only via user rules, and only within the same volume.
- Silent learning makes names drift in ways users can't explain. **Fix:** learning only proposes changes, and the user approves each one.
- Notification spam when ten files land at once. **Fix:** batching plus a burst guard.
- Glass cards for content contradict Apple's guidance that Liquid Glass belongs to controls and navigation. **Fix:** glass only on floating panels and bars.
- Accessibility for glass and motion. **Fix:** explicit rules for Reduce Motion and Reduce Transparency.
- Testing an AI feature. The model is updated in sync with OS updates. **Fix:**
  - greedy (deterministic) decoding
  - a golden test corpus
  - Apple's Evaluations framework for quantifying accuracy as you iterate [apple](https://developer.apple.com/forums/thread/791086) [dev](https://dev.to/hariharanjagan/whats-new-in-apples-foundation-models-framework-at-wwdc-2026-5227)
- Screenshot app detection. With the floating thumbnail on, macOS writes the file seconds after capture, so the frontmost app at that moment can be wrong. **Fix:** look up the app at capture time from an in-memory app-switch timeline.
- Ambiguous dates like 03/04/2026. **Fix:** never guess; fall back to another date.
- A global hotkey for the Finder selection needs Apple Events permission and a sandbox exception. **Fix:** dropped, in favor of the Finder extension.
- The thumbnail toast duplicates notifications, can't reliably respect Focus, and covers content. **Fix:** dropped.
- Cloud APIs need a network entitlement, API keys and money, and they break the privacy promise. **Fix:** on-device only in v1.
- Menu bar apps don't appear in ⌘-Tab. **Fix:** switch the activation policy while a window is open.
- exFAT, FAT and network drives don't reliably support extended attributes or file events. **Fix:** APFS and Mac OS Extended only.

### Decisions

| Topic | Chosen | Rejected | Why |
|---|---|---|---|
| Minimum OS | macOS 27 | macOS 26 | Image input, token APIs, one OS version to test |
| Model | On-device Apple model | Private Cloud Compute, cloud APIs, local LLMs | Private, free, offline, no keys |
| Building names | Model → fields; code → name | Model writes the filename | Preferences become testable guarantees |
| Default scope | Generic names only | Every new file | Respects names people chose |
| Default mode | Review, with a later offer to go Automatic | Automatic on day one | Builds trust first |
| Filing | Rules over extracted fields | Model chooses the folder | Predictable and explainable |
| Distribution | Mac App Store, sandboxed | Direct download + Sparkle | No network entitlement at all, so the privacy claim is verifiable |
| Explicit renames | Finder extension, drag-and-drop, Shortcuts | Services menu, global hotkey | Work inside the sandbox |
| Feedback | System notifications | Custom toast | Focus, accessibility, consistency |
| Storage | SQLite via GRDB, two databases | SwiftData | Predictable transactions for the journal |

Cloud options are deferred, not dismissed. Apps in the App Store Small Business Program with fewer than 2 million first-time downloads can use Apple's next-generation models on Private Cloud Compute at no cloud API cost. That makes it a strong opt-in for v1.1. [apple](https://developer.apple.com/wwdc26/guides/macos/)

---

## Part 3 — Final specification

### 3.1 Product

One line: Nomen gives new screenshots and downloads clear names in your style, on-device, with undo for everything.

In v1:

- Folder watching, with Automatic and Review modes.
- On-device naming with a deterministic Basic fallback.
- The full style system.
- Learning from folders, examples and edits, always with approval.
- Rule-based filing.
- Quick Rename from Finder and from drag-and-drop.
- Bulk rename of existing files.
- Undo and history.
- Menu bar panel, main window, onboarding, notifications, and Shortcuts actions.

Not in v1:

- Cloud or Private Cloud Compute models.
- Finder tags.
- "Describe your style in words."
- A localized UI (the UI is English; names can be in any supported language).
- Audio/video naming and duplicate detection.
- Cross-volume moves, and network or exFAT volumes.
- Settings sync.
- Pricing and business model (not covered here).

### 3.2 Platform and distribution

- macOS 27.0 or later. macOS 27 is Apple-silicon only, having dropped Intel and Rosetta 2. [nyu](https://rits.shanghai.nyu.edu/ai/apple-foundation-models-macos-27/)
- Swift 6 language mode with complete concurrency checking.
- SwiftUI for views. AppKit for the status item, floating panels and activation policy.
- Mac App Store, App Sandbox, Hardened Runtime.
- Entitlements (exact list; all under `com.apple.security.`):
  - App: `app-sandbox`, `files.user-selected.read-write`, `files.downloads.read-write`, `files.bookmarks.app-scope`, `application-groups` (one group).
  - Finder extension: `app-sandbox`, `application-groups`.
- No network, no Apple Events, no temporary exceptions.
- No Accessibility, Screen Recording or Full Disk Access requests.
- Watched and destination folders must be on APFS or Mac OS Extended volumes. Any other volume is refused with an explanation.
- The only third-party dependency is GRDB (MIT).

### 3.3 Glossary

- **Granted folder:** a folder Nomen can write in. Its role is Watched, Destination or Access-only.
  - Downloads is granted by entitlement.
  - Others are granted through the system folder picker and saved as security-scoped bookmarks.
- **Watched folder:** a granted folder Nomen monitors, top level only.
- **Mode** (per watched folder): Automatic, Review or Off.
- **Fields:** kind, source, subject, date and app.
- **Style:** the preferences that turn fields into a name.
- **Proposal:** fields, plus the formatted name, destination, confidence and evidence.
- **Basic naming:** the deterministic path used when the model can't be.
- **Marker:** the extended attribute `com.yourcompany.Nomen.original`, set on every file Nomen has renamed.

### 3.4 Defaults and limits (single source of truth)

| Setting | Default | Range |
|---|---|---|
| Stability wait | 1.0 s; size and modification date equal on two checks ≥ 0.5 s apart | 0.5–10 s |
| PDF pages read | 2 | 1–5 |
| Content budget | ≤ 3,000 tokens | — |
| OCR image size | ≤ 4,096 px on the long side | — |
| Image sent to the model | ≤ 1,536 px on the long side | — |
| Max name length | 60 characters (base name, including any collision suffix) | 20–150 |
| Subject words | 5 | 1–12 |
| Examples stored / used | 20 / 5 per style | — |
| Learning threshold | same edit ≥ 2 times in 30 days | — |
| Finder edits count as feedback | within 7 days of Nomen's rename | — |
| Burst guard | > 10 eligible files in 30 s in one folder | — |
| Notification batching | ≥ 4 operations in 10 s | — |
| Generation timeout | 20 s | — |
| Rate-limit backoff | 5 s, 15 s, 60 s, then every 5 min | — |
| Content-reading size limit | 200 MB | — |
| Collision counter | 2–99 | — |
| PII digit run | ≥ 9 consecutive digits | — |
| History retention | 90 days | 30, 90, 365, forever |
| Thumbnail cache | 200 MB | — |
| "Pause until tomorrow" | resumes at 06:00 local time | — |
| Quick Rename selection | 1–50 files | — |
| Learn-from-folder minimum | 10 files | — |
| "Go Automatic?" offer | after 20 accepted proposals in a folder with ≤ 2 edits | — |

### 3.5 Pipeline

1. **Watch.** One FSEvents stream per watched folder (file-level events, 0.3 s latency).
   - An in-memory snapshot of each folder's top level (file identifier → name) sorts events into *arrived*, *renamed in place* and *removed*.
   - Only *arrived* starts processing.
   - The last event ID is saved. On launch, events replay from that ID, or a full scan runs if the ID is no longer valid. The scan only picks up files whose date added is on or after the folder's watch start.
2. **Stability gate.**
3. **Eligibility** (3.6). The first eligible arrival after a period of inactivity prewarms the model.
4. **Extract** content, metadata and evidence (3.7).
5. **Generate** fields with the model or Basic naming (3.8).
6. **Validate and guard** the fields (3.9).
7. **Format** with the style, check for collisions, and compute confidence.
8. **Decide.** Automatic mode with High confidence executes. Everything else goes to the Review queue.
9. **Execute** (3.13). Journal entry, then a coordinated exclusive rename/move, then the marker, then journal done, then a notification.
10. **Learn** from edits (3.11).

### 3.6 Eligibility (automatic processing)

All of these must hold:

- **Event:** an *arrived* event at the top level of a watched folder whose mode isn't Off, with nothing paused.
- **File kind:** a regular file.
  - Not a folder, package, symlink or Finder alias.
  - Not hidden, and not `.DS_Store`, `.localized` or `Icon\r`.
- **Not in progress:** not an in-progress download or temp file (`.download`, `.crdownload`, `.part`, `.partial`, `.opdownload`, `.tmp`, or a leading dot).
- **Type:** PNG, JPEG, HEIC, TIFF, GIF, WebP, PDF, TXT, Markdown, RTF, HTML, DOC, DOCX, XLSX, PPTX, Pages, Numbers or Keynote.
- **Timing:** date added is on or after the folder's watch start.
- **Not seen before:** no marker, no history entry for this file identifier plus date added, and not on the ignore list.
- **Writable and local:** not locked, folder writable, and not a dataless iCloud placeholder.
- **Generic name**, when "Only generic names" is on (the default).

**Generic name detector.** A name is generic if either is true:

- It matches a built-in pattern:
  - system screenshot and screen-recording names in every macOS language
  - camera names (IMG_1234, DSC_0001, PXL_…)
  - messaging exports ("WhatsApp Image …") and scanner names
  - "document", "file", "download", "untitled", "image", "unnamed", "attachment", "export"
  - browser duplicate suffixes like " (1)"
  - UUIDs, hex runs of 12+ characters, and names made only of digits, dates and separators
- Fewer than 3 letters remain after removing digits, dates and generic words. Han, kana and Hangul characters count as two letters each. *(Part 5, #38)*

A browser duplicate suffix makes a name generic only together with a generic word ("document (3)"); "Invoice (1)" keeps its name. *(Part 5, #45)*

Users can add patterns or turn the check off.

Explicit requests (Quick Rename, bulk rename, Shortcuts) skip the arrival, date-added, generic-name and pause conditions, but keep every safety condition.

Disallowed types get metadata-only proposals, always with Low confidence.
Dataless iCloud files also get metadata-only proposals and are never downloaded.

**Burst guard:** if more than 10 eligible files arrive in one folder within 30 s, a burst begins. None of the files still waiting at that moment, and none arriving until 30 s pass without an arrival, is renamed automatically. The burst goes to Review as one group, with one notification. Files already renamed before the burst began are not affected. *(Part 5, #37)*

### 3.7 Extraction

- **Images and screenshots:**
  - Vision text recognition (accurate, automatic language) at ≤ 4,096 px.
  - Image classification labels with confidences, and the capture date.
  - The image at ≤ 1,536 px goes to the model, if image input ships (3.21).
  - Screenshot detection, in order:
    1. Spotlight's screen-capture attribute, if indexed.
    2. The "Screenshot" comment macOS writes into the image metadata.
    3. Localized default-name patterns.

    Capture time comes from metadata or from the default name.
  - App at capture time: an in-memory timeline of app activations (last 10 minutes, never saved) gives the frontmost app at capture time.
- **PDF:** PDFKit text from the first N pages.
  - Pages with fewer than 30 characters are treated as scans: rendered at 200 dpi and OCR'd, and page 1's image goes to the model.
  - Password-protected PDFs get metadata only.
- **TXT, MD, RTF, HTML, DOC, DOCX:** read as attributed strings.
- **XLSX, PPTX, Pages, Numbers, Keynote:** a 1,024 px Quick Look thumbnail is OCR'd and also sent to the model as an image.
- **All files:** download domain, date added, creation date, size, page count, and the original name with generic parts stripped.
- **Language:** detected with the NaturalLanguage framework.
- **Date candidates:** found with data detectors plus numeric and month-name patterns.
  - Each candidate keeps its exact source snippet.
  - A numeric date where day and month are both ≤ 12 is dropped, unless the language or another date on the page settles the order.
- **Title line:** the tallest recognized text line, used by Basic naming.
- Extracted text stays in memory only and is discarded after the proposal is made.

### 3.8 Model layer

- **Model:** the system on-device model. macOS 27 lets apps pass images alongside text in prompts. Image input ships only if spike 2 confirms it on the reference Mac. The text-only path is always complete on its own. [apple](https://developer.apple.com/macos/whats-new/)
- **Availability:** checked at launch and on change. If the model is not eligible, not enabled, or not ready, Nomen uses Basic naming and shows the status in the panel and in Settings.
- **One request per file:**
  - A fresh session, greedy sampling, and a non-streaming respond. Apple advises against streaming in the background because it uses more power and hits the rate limit sooner. [apple](https://developer.apple.com/forums/thread/789788?answerId=845702022)
  - Requests run one at a time, in arrival order.
  - Automatic work uses background quality of service; Quick Rename uses user-initiated.
- **Output schema**, built at runtime with dynamic guided generation so answers must fit it:
  - `kind`: one of the built-in kinds, the user's custom kinds, or Other.
    - Built-in kinds: Invoice, Receipt, Bank Statement, Payslip, Tax Document, Contract, Letter, Form, Certificate, Ticket, Boarding Pass, Booking Confirmation, Order Confirmation, Shipping Label, Manual, Report, Article, Presentation, Spreadsheet, Résumé, Recipe, Map, Chat, Email, Social Post, Web Page, Error Message, Code, Diagram, Chart, Design, Photo, Scan.
  - `source`: optional, ≤ 4 words.
  - `subject`: ≤ N words.
  - `dateChoice`: the index of one date candidate, or none.
- **Instructions**, fixed per style version:

  > You name files. Fill the fields using only information in the provided content and metadata. Prefer concrete words (company, product, document type) over generic ones. Subject: at most {N} words, no dates, no numbers longer than 8 digits. Never include account numbers, card numbers, IBANs, phone numbers, email addresses, passwords or ID numbers. Write in {language}. Preferred words: {vocabulary}. Avoid: {never-include}. If the content is unreadable, use kind Other and a short visual description.

- **Prompt order:** metadata, then content, then the image if used, then up to 5 approved names.
- **Budget:** prompts are measured with Apple's context-size and token-counting APIs, first released in iOS 26.4 and part of the macOS 27 framework. [apple](https://developer.apple.com/videos/play/wwdc2026/241?time=166)
  Content is trimmed until the prompt fits in the context size minus 1,000 tokens:
  1. Lines after the first 40.
  2. Lines with neither date candidates nor title-sized text.
  3. A cut at a line boundary.

  Content never exceeds 3,000 tokens.
- **Error policy:**

  | Situation | Action |
  |---|---|
  | Guardrail or refusal | Basic naming, forced Low confidence, reason shown |
  | Context exceeded | Retry once with half the content, then Basic naming |
  | Rate limited or concurrent request | Keep pending; retry at 5 s, 15 s, 60 s, then every 5 min; status "Waiting for Apple Intelligence" |
  | Model unavailable, missing assets, unsupported language | Basic naming |
  | Decoding failure | Retry once, then Basic naming |
  | No answer in 20 s | Cancel, then Basic naming |

- **Regenerate** (⌘R in Quick Rename) uses random sampling. Only first proposals are deterministic.
- **Basic naming:**
  - kind from a keyword table (Invoice/Facture/Rechnung/Fattura/Factura/Fatura, Receipt/Quittung/Reçu, and so on), otherwise Other
  - source from the download domain, using a built-in alias list, or from the app name
  - subject from the title line
  - date from the style's date order

### 3.9 Validation, guards, confidence

- **Kind:** always valid, because of the schema.
- **Source:** kept only if it matches evidence, ignoring case and accents. The evidence can be the extracted text, the download domain, or the app name. Sources that only appear as a logo are dropped by design.
- **Date:** only the chosen candidate. Otherwise the style's fallback order: capture date, then date added, then creation date.
- **Subject:** the PII guard runs, then never-include words are removed, then words repeating the kind or source, then filler words if that option is on.
- **PII guard:** applies to all generated text, but not to names the user types. It removes:
  - card numbers (Luhn check, 13–19 digits, any spacing)
  - IBANs (checksum)
  - email addresses
  - phone numbers (international prefix, or 8+ digits with phone formatting)
  - any run of 9 or more digits
- **Confidence** High only if all of these hold. Otherwise Low.
  - Every required token in the style is non-empty after the guards (Other counts as empty).
  - The file yielded ≥ 20 characters of text, or its top image label has ≥ 0.7 confidence.
  - There was no guardrail or refusal.
  - The guards removed fewer than 50% of the subject words.
  - The new name differs from the current name.

### 3.10 Naming styles

| Setting | Options | Default |
|---|---|---|
| Template | Ordered tokens: Date, Kind, Source, Subject, App, Original, Text; each Required or Optional | Date (req) · Source · Kind · Subject (req) |
| Screenshot template | Same tokens | Date (req) · App · Subject (req) |
| Part separator | space, " - ", " – ", "_", "-", "." | space |
| Word separator | space, "-", "_", ".", none | space |
| Case | Title, Sentence, lowercase, UPPERCASE, camelCase, PascalCase, As generated | Title |
| Date format | 2026-11-27, 20261127, 2026-11, 27.11.2026, 27-11-2026, 11-27-2026, 27 Nov 2026 | 2026-11-27 |
| Date order | content, capture, added, created (reorderable) | that order |
| Time | off, HH.MM, HHMM | off |
| Max length | 20–150 characters | 60 |
| Subject words | 1–12 | 5 |
| Name language | Same as content, or a fixed supported language | Same as content |
| Characters | Remove accents, ASCII only, Windows-safe, Allow emoji | all off |
| Extension | Keep exactly, or Lowercase | Keep |
| Vocabulary | from → to (whole word, any case) | built-ins |
| Protected words | User list plus built-in brands (iPhone, macOS, iCloud, eBay, YouTube, GitHub, PayPal, LinkedIn…) | built-ins |
| Never include | Word list | empty |
| Remove filler words | Per-language lists | off |

**Rules that prevent conflicts**

- camelCase and PascalCase force the word separator to "none". "None" is only offered with those two cases.
- Protected words keep their casing in Title, Sentence and As generated. In lowercase, UPPERCASE, camelCase and PascalCase, the case setting wins.
- Title Case uses small-word lists for English, French, German, Italian, Spanish and Portuguese. Other languages capitalize every word. Scripts without case are left unchanged.
- Vocabulary loops (A→B plus B→A) can't be saved.
- Times use "." or no separator, because ":" isn't allowed. The time is joined to the date with the word separator, or "-" when there is none, so digits never run together. *(Part 5, #36)*
- ASCII only can't be combined with the " – " part separator. *(Part 5, #39)*
- Never include takes single words. A month name can't be listed while the date format uses month names. *(Part 5, #42)*
- Kind Other adds nothing to a name. *(Part 5, #43)*
- In "27 Nov 2026" the day has no leading zero. Japanese and Chinese render 2026年11月27日; Korean renders 2026년 11월 27일. *(Part 5, #44)*
- A date containing spaces (27 Nov 2026) is treated as words, so the separator and case settings apply to it.

**Presets.** Reference fields: 2026-11-27, Swisscom, Invoice, subject "mobile subscription November".

- Clean (default): `2026-11-27 Swisscom Invoice Mobile Subscription November.pdf`
- Compact: `20261127_swisscom_invoice_mobile_subscription_november.pdf`
- Descriptive (max length 80): `Invoice – Mobile Subscription November – Swisscom – 2026-11-27.pdf`
- Kebab: `2026-11-27-swisscom-invoice-mobile-subscription-november.pdf`

**Formatter.** A pure function: the same inputs always give the same output.

1. Apply vocabulary, never-include, the PII guard, de-duplication and filler removal to source and subject.
2. Get the kind label in the name language (app-provided translations) or the custom kind's label. Vocabulary applies to it.
3. Render the date and time.
4. Apply case, respecting protected words and the rules above.
5. Join words with the word separator and tokens with the part separator. Drop empty optional tokens together with their separator.
6. Apply the character options.
7. Sanitize:
   - remove "/", ":", NUL, control characters, and bidirectional and zero-width characters
   - normalize to NFC
   - collapse repeated separators
   - trim spaces, separators and dots at both ends, with no leading "."
8. Fit the length, counting user-perceived characters and including any collision suffix:
   1. Drop optional tokens in this order: Original, Text, App, Source, Kind, Date.
   2. Trim subject words from the end, keeping at least one.
   3. Trim words from the longest remaining non-date token.
   4. Cut at a character boundary if a single word is still too long.

   Dates are never cut; a time is dropped before the date would have to be cut. The same order then enforces ≤ 255 UTF-8 bytes for the whole filename. *(Part 5, #40)*
9. If the result is empty, use "File" in the name language, with the date in front if there is one.
10. Add the extension, byte-for-byte, or lowercased if that option is on.
    - .tar.gz, .tar.bz2, .tar.xz and .tar.zst count as a single extension.
    - An extension is 1–15 ASCII letters and digits with at least one letter, or exactly three digits (".001"). Anything else after the last dot ("Report v1.2") is part of the name. *(Part 5, #41)*
    - Files without an extension stay without one.

User-typed names are never restyled. Only step 7 and the 255-byte limit apply, and any change those make is shown before saving. Edit fields show only the base name. If a typed name ends with the file's own extension, that extension is stripped.

**Learning a style**

- From a folder (at least 10 files; read once, with no lasting access):
  - Detects date format, separators, case and token order by counting patterns.
  - Sets max length to the 90th-percentile name length rounded up to 10, clamped to 20–150.
  - Nothing changes until the user accepts the proposed style.
- From examples: 3–5 names the user types, analyzed the same way.

### 3.11 Learning from edits

- **Edit sources:**
  - edits in Review, Quick Rename and notification replies
  - Finder renames of a marked file within 7 days of Nomen renaming it
- **Patterns detected:** case change, separator change, date format or position change, token added or removed, word replaced, name shortened, filler removed.
- **Suggestions:** when a pattern occurs at least 2 times in 30 days for one style, a card appears, e.g. "You changed 'Bill' to 'Invoice' twice. Always do this?" It offers Always, Not now and Never ask. Only Always changes the style.
- **Examples:** accepted final names, 20 per style. The newest 5 go into prompts. They are visible and deletable, and only names are stored.

### 3.12 Organizing

- Destinations are granted folders with an optional subfolder pattern built from {year}, {month}, {source} and {kind}.
  - Subfolders are created as needed and sanitized like names.
  - They can never point outside the destination.
- Rules are ordered, and the first match wins.
  - Conditions (match All or Any): kind is, source contains, download domain is / ends with, is screenshot, app is, file type is, original name contains.
  - Action: move to a destination.
- Moves happen only when a rule matches.
  - In Automatic mode, the rename and move are one operation.
  - Review and Quick Rename show the destination with a "Move to …" checkbox, on by default.
- Same volume only. Rules with a destination on another volume can't be saved.
- Missing destination: the file is renamed in place, flagged, and the rule shows a warning.
- Rule tester: shows which of the last 50 processed files each rule would match.

### 3.13 File safety

- Every rename or move follows the same sequence:
  1. Journal entry *planned*.
  2. File coordination, so documents open in other apps follow the move.
  3. Identity re-check: same identifier, size, modification date, and an unchanged name.
  4. Exclusive rename (`renamex_np` with `RENAME_EXCL`, which fails instead of overwriting).
  5. Marker.
  6. Journal entry *done*.
- Name changed since detection: abort and record "named by someone else."
- **Collisions:**
  - The suffix is the word separator ("-" when there is none) plus n, where n runs from 2 to 99.
  - Comparisons are case-insensitive.
  - Past 99, the operation fails safely and the file is untouched.
- **Never:**
  - delete a file, or change its contents
  - change dates, tags, comments or other extended attributes (including quarantine)
  - follow symlinks, or move across volumes
- **Own-operation suppression:** events for files Nomen just moved are ignored for 5 s, keyed by file identifier.
- **Marker:** a binary plist holding the original name, the state (renamed or restored) and the first-renamed date. A file with a marker, in any state, is never processed automatically again.
- **Project folders:** adding a watched folder that contains `.git`, `package.json`, `*.xcodeproj`, `Cargo.toml`, `pyproject.toml` or `go.mod` needs explicit confirmation.

### 3.14 Undo, history, journal

- **Storage:** `history.sqlite` in WAL mode.
- **Entry states:** planned, done, failed, reverted.
- On launch, every *planned* entry is reconciled by locating its file identifier.
- Each entry records: time, identifier, bookmark, old and new path, method, style version, model or Basic path, and confidence.
- **Undo entry points:**
  - menu bar rows, Activity, and notifications
  - ⌘Z in the main window (undoes the last operation)
  - Finder's "Restore Original Name" (uses the marker, so it works even after history is purged)
  - batch undo for bulk runs and bursts
- **Undo rules:**
  - Restores the original name and folder, exclusively.
  - If the original name is taken, a collision suffix is added and the user is told.
  - If the original folder is missing, it is recreated only inside a granted folder; otherwise undo fails with an error.
  - If the file was deleted, undo is disabled and the reason is shown.
  - If the user moved the file, Nomen finds it via its bookmark, and asks for access if it's now outside granted folders.
  - After a restore, the marker state becomes *restored*.
- **Retention:** 90 days. Purges never touch planned entries or queued items.

### 3.15 Interface

**Menu bar item**

- An AppKit status item with a monochrome template glyph.
- States are told apart by shape: idle, working (animated), needs review (dot), paused (slash), problem (exclamation).
- It accepts file drops, which open Quick Rename.

**Menu bar panel** (360 pt, borderless panel with system glass via `NSGlassEffectView`)

- Header: a status pill (a plain capsule, not glass), e.g. "Watching Desktop and Downloads", "Paused until 06:00", "Waiting for Apple Intelligence" or "Basic naming". Next to it, a Pause menu: 1 hour, until tomorrow, indefinitely.
- Needs review (n): opens the queue.
- Recent: the last 5 operations.
  - Each row shows a thumbnail, the new name, "was …" and the time.
  - Hovering shows Undo and Show in Finder.
  - Rows can be dragged out as files, for example into a Mail message.
- Suggestion card: appears when a learning suggestion is pending.
- Footer: Open Nomen and Settings. A drop zone appears while files are dragged over the panel.

**Quick Rename panel** (opened from Finder's right-click menu or by dropping files)

- Layout:
  - A floating glass panel, 520 pt wide, in the upper third of the active screen.
  - Thumbnail and an editable name with the base name selected; the extension is shown separately.
  - A "Why this name?" disclosure, and a "Move to …" checkbox when a rule matches.
- Controls: Return renames, Esc cancels, ⌘R regenerates. With several files, each gets its own field.
- Loading: a shimmering placeholder while the proposal is generated.
- Folders without access: Nomen first opens the folder picker on the file's folder. If the user declines, it offers to copy the suggested name instead.

**Main window** (minimum 880 × 580, standard sidebar split view)

- **Review:**
  - Rows show a thumbnail, the proposed name, the original name, a destination chip, and a "Low" badge with icon and text when confidence is low.
  - The inspector shows a preview, editable fields (which re-format the name instantly), the final name, evidence per part, and the destination.
  - Selecting several items shows a floating glass action bar: Accept n, Skip, Change style.
  - Keys: ↑↓, Return accept, ⌘⌫ skip, E edit, Space Quick Look, ⌘A, ⌘Return accept selected.
- **Activity:**
  - History grouped by day, searchable by old or new name.
  - Per row: Undo, Show in Finder, Copy name, Never rename again.
- **Folders:**
  - Granted folders, grouped by role.
  - Per watched folder: mode, style, "only generic names", weekly count, and "Rename existing files…" (a bulk run whose results go to Review).
  - The one-time offer to switch a folder to Automatic appears here and in the panel.
- **Styles:**
  - A token bar with draggable chips, and the settings table.
  - A live preview of sample files. It uses stored fields, so editing never calls the model.
  - The examples list and pending learning suggestions.
- **Rules:** an ordered list, an editor, and the tester.
- **Dock and ⌘-Tab:** while any window is open, the app appears in both. It returns to menu-bar-only within 1 s after the last window closes, unless "Show in Dock" is on.

**Settings** (standard tabs)

- General: launch at login, show in Dock, pause in Low Power Mode (on), rename sound (off).
- Apple Intelligence: status, "Use Basic naming only", and on-battery behavior.
- Notifications.
- Privacy: the privacy statement, clear history, clear learned data, reset.
- Advanced: stability wait, PDF pages, retention, diagnostics export.

**Onboarding** (works fully from the keyboard, and resumes where you left off)

1. Welcome, with the privacy promise: "Everything stays on this Mac. Nomen has no internet access."
2. Apple Intelligence status, with a button to its settings. Continuing with Basic naming is allowed.
3. Folders: Desktop (the picker opens on Desktop), Downloads (no picker needed), and others.
4. Style: presets with live examples, learn from a folder, or type example names.
5. Mode: Review (default) or Automatic.
6. Notifications permission, launch at login, and enabling the Finder extension.
7. Live demo: "Take a screenshot." If none arrives within 10 s, Nomen explains that screenshots may be saved elsewhere and offers to add that folder.

**Notifications**

- Automatic renames: Undo and Show in Finder.
- Review items: Accept, Edit (type a name), Skip.
- Grouping: 4 or more operations in 10 s become one summary with Undo All. A burst gets one "n files waiting" notice.
- No echo: in-app actions never trigger a notification.
- Permission: asked only in onboarding step 6.

**Finder extension**

- Active in granted folders only.
- Menu items: "Rename with Nomen…" (1–50 items), and "Restore Original Name" (only when the marker says renamed).
- Requests go through the app-group container and a `nomen://` URL that carries only a request ID. Unknown IDs are ignored.

**Shortcuts actions**

- Suggest Name (returns text only), Rename File, Pause, Resume, and Rename Existing Files in Folder (results go to Review).
- Files outside granted folders return a clear error.

### 3.16 Liquid Glass and motion

- Custom glass appears on exactly three surfaces: the menu bar panel, the Quick Rename panel, and the Review action bar (grouped so it can morph). Standard controls, toolbars, sidebars, sheets and menus get glass from the system.
- Never glass on: rows, thumbnails, text, or inside another glass surface.
- Controls inside glass panels use standard button styles, with the prominent style for the primary action only.
- System settings respected: Reduce Transparency, Increase Contrast, and macOS 27's new slider for adjusting glass from ultra-clear to fully tinted. [apple](https://support.apple.com/en-ae/127257)
- App icon: made in Icon Composer, with Default, Dark, Clear and Tinted variants.
- **Motion:**
  - Timing: standard ~0.3 s smooth spring; small controls ~0.2 s snappy; panel open 0.35 s with a slight bounce. Nothing exceeds 0.5 s, and nothing blocks input.
  - The rename moment: the old name blurs and fades (0.2 s) while the new one rises into place (0.25 s), then the row glides into Recent/Activity.
  - Counts roll, and new rows slide in from the top with a fade.
  - The menu bar glyph animates only while working.
  - A haptic tick plays when chips snap or rules are reordered.
  - With Reduce Motion: crossfades of ≤ 0.2 s only, no shimmer, and a static glyph.
- **Text:**
  - system fonts, with monospaced digits in date columns
  - long filenames truncate in the middle so the extension stays visible
  - the full name is available as a tooltip and to VoiceOver

### 3.17 Accessibility

- VoiceOver: every control is labeled, and rows read naturally, e.g. "Renamed Screenshot… to Safari Flight Booking, 2 minutes ago".
- Keyboard and voice: Full Keyboard Access and Voice Control work everywhere.
- Contrast: ≥ 4.5:1, including on glass. Color is never the only signal.

### 3.18 Privacy and security

- No network: the app has no network entitlement. Its App Store privacy label is "Data Not Collected".
- Extracted text exists only in memory.
- What's stored on disk:
  - names, paths and bookmarks
  - fields of ≤ 200 characters each
  - settings and cached thumbnails
- Logs: names and paths are marked private, and the diagnostics export strips them.
- Quarantine attributes are never removed. Bidirectional and zero-width characters are stripped from names.

### 3.19 Performance and energy

Reference Mac: MacBook Air (M1, 8 GB). Unless stated, measurements are plugged in with the model warm.

- **Naming latency:**
  - Screenshot renamed (Automatic, from the moment the file is final): p50 ≤ 4 s, p95 ≤ 8 s. With a cold model: p95 ≤ 15 s.
  - Text PDF: p95 ≤ 10 s. Scanned PDF: p95 ≤ 15 s. Basic naming: p95 ≤ 2 s.
- **UI:**
  - Panel ≤ 150 ms. Main window ≤ 500 ms.
  - Quick Rename ≤ 300 ms with the app running, ≤ 1.5 s from a cold launch.
  - Style preview ≤ 50 ms. Activity search across 100,000 entries ≤ 200 ms.
- **Idle:**
  - ≤ 2 s of CPU per hour and ≤ 1 wakeup per second on average.
  - ≤ 80 MB of memory after 24 h.
- **Bulk:** a run of 1,000 files stays ≤ 400 MB.
- **On battery:** rate limits may delay work. The latency targets don't apply then, but every correctness rule does. A setting offers "Process normally" (default) or "Wait until plugged in".
- **Pauses:** Low Power Mode pauses processing by default. Serious or critical thermal state always pauses it. Queued work resumes within 10 s after the condition clears.

### 3.20 Architecture and storage

- **NomenCore** (pure, with no UI or file access): formatter, sanitizer, guards, date parsing, generic-name detector, eligibility rules, rule engine, edit diff, style inference.
- **NomenFS:** watcher, snapshots, stability gate, journal, executor, marker, bookmarks.
- **NomenExtract:** Vision, PDFKit, Quick Look, metadata, app timeline.
- **NomenModel:** schema builder, budgeter, error policy, Basic naming.
- **NomenStore** (GRDB):
  - `config.sqlite`: folders, styles, rules, kinds, examples, learning, ignore list, event IDs
  - `history.sqlite`: history, journal and queue

  They are kept separate, so a damaged history never loses configuration. Thumbnails live in Caches, capped at 200 MB, with least-recently-used eviction.
- **NomenEngine:** the pipeline that connects the modules above (queue, decide, execute, undo, learning, notification planning). It has no UI and runs in tests with fake extractors and a fake model. *(Added; see Part 5, #35.)*
- **NomenUI** (SwiftUI), the **App** target, and the **FinderExtension** target.

### 3.21 Testing and spikes

**Week-1 spikes** (must pass before feature work):

1. Foundation Models rate limits for a menu bar app, on battery and plugged in.
2. Image + text latency and quality on the reference Mac. This decides whether image input ships.
3. Sandbox behavior: Downloads renames, granted-folder renames, the drag-and-drop grant flow, the Finder extension handoff, and drops onto the status item.
4. Screenshot detection signals and timing across system languages.
5. Live glass backdrop in a borderless panel. A developer reported that `NSGlassEffectView` stopped updating its background in a borderless window on macOS 26.2. [apple](https://developer.apple.com/forums/thread/810314)

Spike results can change numbers in 3.4 and 3.19. Any change is written into this spec first.

**Ongoing testing:**

- Unit and property tests for NomenCore, integration tests on temp folders, a chaos harness, and UI tests.
- Instruments for hitches, leaks and energy.
- A golden corpus scored with the Evaluations framework.
- Prompt iteration with macOS 27's `fm` command-line tool, which accepts an image and a JSON schema. [apple](https://developer.apple.com/videos/play/wwdc2026/334)

### 3.22 Later versions

- **v1.1:** opt-in Private Cloud Compute for Low-confidence files, Finder tags, "describe your style", a localized UI, and import/export of styles.
- **v2:** bring-your-own-key cloud models, voice memo and video naming, duplicate detection, learned destination suggestions, and settings sync.

---

## Part 4 — Acceptance criteria

**Rules**

- Every criterion is pass/fail. v1 is complete only when every criterion passes on every matrix configuration, using the exact build that ships.
- No waivers and no "known issues." A flaky test counts as a failing test.
- If a criterion is wrong, change the spec first (logged in Part 5), then re-run everything it affects.
- AI judgment is measured against the benchmark in section Q. Everything the code controls has zero tolerance.

**Test matrix**

- Hardware:
  - MacBook Air (M1, 8 GB).
  - A MacBook Pro with ProMotion plus an external 1080p display.
  - A Mac mini with two external displays: one vertical, with the menu bar on the secondary display.
- OS: macOS 27.0 and the latest 27.x.
- Apple Intelligence: on (in English, French, German and Japanese) and off.
- System language: English, French, German, Japanese.
- Appearance: Light, Dark, Reduce Transparency, Increase Contrast, Reduce Motion, the glass slider at both ends, every accent color, notch and non-notch displays, and an auto-hiding menu bar.
- Power: plugged in, on battery, and Low Power Mode.
- Storage: internal APFS with iCloud Desktop & Documents on and off, plus an external APFS volume.

### A. Build and platform
- **A1.** A clean checkout builds with one xcodebuild command, with zero warnings under Swift 6 complete concurrency checking.
- **A2.** The deployment target is macOS 27.0, arm64 only.
- **A3.** Entitlements match 3.2 exactly, diffed in CI.
- **A4.** App Store review approves the app, and the privacy label reads "Data Not Collected".
- **A5.** GRDB is the only third-party code, and its license appears in About.
- **A6.** NomenCore and NomenFS have ≥ 90% line coverage, and every test passes 100 consecutive CI runs.
- **A7.** Launching a second copy brings the first copy forward and quits.
- **A8.** The release build has no debug menus, test hooks, or TODO/FIXME markers.

### B. Onboarding
- **B1.** Every step can be completed with the keyboard alone, and with VoiceOver.
- **B2.** The Apple Intelligence states (available, not enabled, not eligible, not ready) display correctly, and the settings button opens the right pane.
- **B3.** The Desktop picker opens on Desktop. If the user picks another folder, that folder is added and the UI says so.
- **B4.** Downloads is added without any picker.
- **B5.** Learn-from-folder is 100% correct on consistent-format fixtures. It is disabled, with the reason shown, for folders with fewer than 10 files.
- **B6.** The live demo meets the 3.19 targets, and the "saved elsewhere" tip appears after 10 s without a screenshot.
- **B7.** Quitting mid-onboarding resumes at the same step, and nothing is watched before onboarding finishes or is skipped.
- **B8.** The Finder extension status updates within 2 s after the user enables it.

### C. Access and watching
- **C1.** Folder access survives 20 app restarts, 5 OS restarts, and an app update.
- **C2.** A watched folder that is renamed, moved or deleted shows "Needs attention" with Reconnect within 5 s or at launch.
- **C3.** Files in subfolders are never processed automatically (100 nested fixtures, 0 processed).
- **C4.** Files added while Nomen was quit are handled at the next launch, but only if their date added is on or after the watch start.
- **C5.** Unmounting a watched external volume shows "Disconnected" with no error loop. On remount, watching resumes within 10 s.
- **C6.** Folders on exFAT, FAT, NTFS or network volumes are refused with an explanation.
- **C7.** Project-like folders require explicit confirmation.

### D. Intake and eligibility
- **D1.** A 2 GB file written over 60 s is processed exactly once, and only after the write finishes.
- **D2.** Downloads in Safari, Chrome and Firefox (including paused and resumed ones) produce exactly one proposal per finished file, and none for temp files.
- **D3.** Every screenshot shortcut (⌘⇧3, ⌘⇧4, ⌘⇧4 + Space, ⌘⇧5), with and without the floating thumbnail, produces exactly one proposal. Screen recordings produce none.
- **D4.** Every exclusion in 3.6 has a fixture, and 100% of them are skipped. Dataless iCloud files keep their download status unchanged.
- **D5.** The generic-name detector is 100% correct on ≥ 400 names, including every macOS language's screenshot name.
- **D6.** A burst of 11 or more files copied into one folder at once causes 0 automatic renames, one Review group, and one notification. *(Part 5, #37)*
- **D7.** In 1,000 scripted races where someone else renames the file mid-process, Nomen renames it 0 times.
- **D8.** Files with a marker in any state are never processed automatically.
- **D9.** Renaming an existing file in place never triggers processing.

### E. Extraction
- **E1.** Every allowed type yields text containing its fixture's key phrase.
- **E2.** Only the configured number of PDF pages is read. Password-protected PDFs never prompt, and get metadata-only proposals.
- **E3.** A 100-megapixel image peaks at ≤ 500 MB of memory.
- **E4.** File-activity tracing over 100 runs shows extracted text is never written to disk. No stored field other than names, paths and bookmarks exceeds 200 characters.
- **E5.** The app at capture time is correct for 50 scripted screenshots taken while switching apps, with the floating thumbnail on.
- **E6.** Ambiguous numeric dates are never used.

### F. Model
- **F1.** No Nomen process makes a single network connection during the whole test run.
- **F2.** The same file, style, learned state and OS build give an identical name in 50 runs.
- **F3.** For every availability state, Basic naming is used and the status shows within 5 s.
- **F4.** Every row of the error table, injected via test hooks, behaves exactly as specified.
- **F5.** 1,000 fixtures, including maximum-length content, cause 0 context-exceeded errors.
- **F6.** 50 simultaneous arrivals are processed in arrival order with 0 concurrency errors.
- **F7.** The schema matches the current kinds and date candidates. Custom-kind changes apply from the next file.
- **F8.** With image input disabled, the corpus still passes section Q.

### G. Guards
- **G1.** Every date in a name traces to a candidate snippet or a file date (0 exceptions).
- **G2.** Every source traces to evidence (0 exceptions).
- **G3.** Across 1,000 adversarial PII fixtures, 0 card numbers, IBANs, emails, phone numbers or 9+ digit runs end up in names.
- **G4.** Never-include words never appear.
- **G5.** Across 200 injection fixtures, every result is a single valid filename in an allowed folder, and 0 files move without a rule.
- **G6.** 100,000 random Unicode inputs to the sanitizer produce 100% valid output: NFC, ≤ 255 bytes, no forbidden or invisible control characters.
- **G7.** The Windows-safe option additionally guarantees no `\ * ? " < > |`, no trailing space or dot, and no reserved device names.

### H. Styles and formatter
- **H1.** 1,000,000 random combinations of style options and fields produce 100% valid names.
- **H2.** Each case mode matches ≥ 100 expected input/output pairs, covering protected words, acronyms, apostrophes, hyphens, numbers and caseless scripts.
- **H3.** No base name exceeds the max length (including any suffix), and none ends with a separator.
- **H4.** Truncation follows the 3.10 order exactly, and dates are never cut.
- **H5.** Every date format renders exactly, with correct month names in every name language.
- **H6.** The four presets produce exactly the reference outputs in 3.10.
- **H7.** Invalid combinations and vocabulary loops can't be saved, and the UI explains why.
- **H8.** A style change re-formats queued proposals within 50 ms, with 0 model calls. Files already renamed are untouched.
- **H9.** Typed names are never restyled, and any sanitizer change is shown before saving.
- **H10.** Example-name inference is 100% correct on 50 fixture sets.

### I. Learning
- **I1.** Suggestions appear only after ≥ 2 occurrences within 30 days.
- **I2.** After 500 random edits with every suggestion declined, the style state is byte-identical.
- **I3.** "Never ask" suppresses that suggestion until reset.
- **I4.** At most 20 examples are stored and the newest 5 are used. Deleting one takes effect from the next file.
- **I5.** Finder renames within 7 days count as edits. Nomen's own operations never do.

### J. File safety
- **J1.** A 10,000-operation chaos test runs concurrent creates, renames, moves, deletes, writes, rules and undo across two watched folders. Every file is accounted for, every SHA-256 is unchanged, and there are 0 overwrites.
- **J2.** 1,000 races to create the target name cause 0 overwrites.
- **J3.** kill -9 at random points during 1,000 operations leaves every planned entry reconciled correctly after relaunch.
- **J4.** Extensions are preserved exactly (or lowercased when that option is on), including multi-part and missing extensions.
- **J5.** Documents open in Preview, TextEdit and Pages follow the rename, and saving writes to the renamed file.
- **J6.** Dates, tags, comments, quarantine and other extended attributes are unchanged after rename, move and undo.
- **J7.** The marker always holds the first original name, and its state switches correctly.
- **J8.** Collision suffixes match 3.13, and the 100th collision fails safely.
- **J9.** No cross-volume move is ever attempted.

### K. Organizing
- **K1.** Rules are first-match-wins and deterministic. The tester matches real behavior on 100% of the last 50 files.
- **K2.** Files move only when a rule matches.
- **K3.** Subfolder patterns can't escape the destination, even with `..`, `/` or absolute paths in the fields.
- **K4.** A missing destination leads to a rename in place, a flag on the file, and a warning on the rule.

### L. Undo and history
- **L1.** Every operation appears in Activity within 1 s.
- **L2.** Every undo entry point in 3.14 restores the exact name and folder.
- **L3.** Undo finds files the user moved, and asks for access when they're outside granted folders.
- **L4.** Every undo conflict in 3.14 behaves as specified.
- **L5.** Batch undo restores every item, and lists any failures individually.
- **L6.** Purges run daily and never touch planned entries or queued items.
- **L7.** A corrupted history database is detected, set aside and recreated, with configuration intact and the user told.

### M. Review and Quick Rename
- **M1.** Every shortcut in 3.15 works, including with VoiceOver running.
- **M2.** Field edits re-format instantly, and "Why this name?" covers every part of the name.
- **M3.** The queue survives restarts, and items whose files vanished are removed with an Activity note.
- **M4.** Accepting 500 items shows progress, meets U2, and can be cancelled with the remaining files untouched.
- **M5.** Quick Rename meets its 3.19 targets with the base name selected. Return applies, Esc changes nothing, ⌘R regenerates.
- **M6.** A drop from a non-granted folder opens the picker on that folder. Declining leaves the file untouched and offers "Copy name".

### N. Menu bar
- **N1.** The glyph renders correctly on every matrix menu bar, and all five states are distinguishable in grayscale.
- **N2.** The panel never appears off-screen. A click outside, Esc, or a second click closes it.
- **N3.** Undo, Show in Finder and drag-out work from Recent rows (dragging into Mail attaches the file).
- **N4.** Pause settings persist across restarts, and "until tomorrow" resumes at 06:00.

### O. Windows and settings
- **O1.** Dock and ⌘-Tab behavior matches 3.15, including the "Show in Dock" setting.
- **O2.** Window size, position, sidebar selection and column widths are restored.
- **O3.** Activity with 100,000 entries scrolls with zero hitches on ProMotion.
- **O4.** Every setting has a one-line explanation.
- **O5.** Clear history, Clear learned data and Reset do exactly what they say, verified in the databases.
- **O6.** The Automatic offer appears exactly once per folder, after the 3.4 threshold.

### P. Notifications and integrations
- **P1.** Notification permission is requested only in onboarding step 6.
- **P2.** Every notification action works from banners and from Notification Center, with no Nomen window open.
- **P3.** Batching and burst notices follow 3.15, and in-app actions never echo as notifications.
- **P4.** Finder items appear only in granted folders, work for 1–50 items, and work when Nomen isn't running.
- **P5.** Forged or unknown `nomen://` IDs do nothing.
- **P6.** Every Shortcuts action works from Shortcuts and from Siri, with clear errors for files outside granted folders.

### Q. Naming quality benchmark
- **Q1.** The corpus has ≥ 400 files:
  - ≥ 150 screenshots from ≥ 30 apps and sites
  - ≥ 120 documents in ≥ 5 languages
  - ≥ 60 images and ≥ 40 scans
  - ≥ 30 adversarial files
- **Q2.** Model path, on both OS versions. Two blind raters mark each name Good, OK or Bad, and a third breaks ties. Passing requires:
  - Good ≥ 80% and Bad ≤ 3%
  - kind exactly right ≥ 90%
  - source correct ≥ 90% where a source exists
- **Q3.** Basic path: Bad ≤ 5%, Good ≥ 40%.
- **Q4.** Every Bad case is analyzed. Any caused by code is fixed, and the full benchmark is re-run.
- **Q5.** 100% of names comply with the four presets and with 10 random custom styles.
- **Q6.** Two full corpus runs produce 100% identical names.

### R. Visual design and glass
- **R1.** An audit confirms glass appears only where 3.16 allows.
- **R2.** No text is clipped, nothing overlaps, and no contrast check fails, in every matrix appearance on five reference wallpapers.
- **R3.** Glass backdrops update live while windows move beneath them.
- **R4.** All four icon variants are reviewed at every size from 16 to 1,024 px.
- **R5.** All glyphs are vector or SF Symbols, and look crisp on 1x and 2x displays.
- **R6.** Two designers sign off on side-by-side comparisons with Finder, System Settings and Control Center, and every flagged issue is fixed.

### S. Motion
- **S1.** Every animation in 3.16 uses the specified curves, including the haptic ticks. None exceeds 0.5 s or blocks input.
- **S2.** With Reduce Motion on, there are only crossfades of ≤ 0.2 s, no shimmer, and a static glyph.
- **S3.** Recorded scenarios show zero hitches at 60 Hz and at 120 Hz.

### T. Accessibility
- **T1.** Accessibility Inspector reports 0 issues on every screen.
- **T2.** Every action is reachable with Full Keyboard Access, with a visible focus ring.
- **T3.** Contrast is ≥ 4.5:1 everywhere, including on glass.
- **T4.** Voice Control can operate every control by its visible name.

### U. Performance
- **U1.** Every 3.19 target is met over 100 samples.
- **U2.** The main thread is never blocked for more than 50 ms in any scenario.
- **U3.** Nomen is ready to watch ≤ 2 s after login.
- **U4.** A 24-hour soak shows 0 leaks, with memory within 3.19 limits.

### V. Energy
- **V1.** An idle hour meets the 3.19 CPU and wakeup limits.
- **V2.** Low Power Mode and thermal pauses behave as in 3.19, and work resumes within 10 s.
- **V3.** With "Wait until plugged in," nothing is processed on battery, and processing starts within 10 s of plugging in.
- **V4.** Under forced rate limiting, retries follow the backoff schedule exactly, the status is shown, and no file is processed twice.

### W. Privacy and security
- **W1.** A database schema audit matches 3.18.
- **W2.** The diagnostics export contains none of 1,000 unique tokens planted in fixture names, paths and content.
- **W3.** The thumbnail cache stays ≤ 200 MB and is cleared by Clear history.
- **W4.** Quarantine attributes are never altered, on any fixture.

### X. Reliability
- **X1.** A 72-hour soak at 1 file per minute in three folders shows 0 crashes, 0 hangs, and memory growth ≤ 5% after the first hour.
- **X2.** The final two-week beta, with ≥ 50 testers, has 0 crashes.
- **X3.** Through sleep/wake, user switching, display changes, and time zone or clock changes, watching continues, with no duplicates and correct dates.
- **X4.** With the disk full, no operation happens without a journal entry, and the user is told.
- **X5.** A stale folder bookmark never causes repeated prompts or error loops.

### Y. Release gates
- **Y1.** Everything above passes on the release-candidate binary.
- **Y2.** The final name is cleared (trademark search and App Store availability).
- **Y3.** Spike results and the spec changes they caused are recorded in Part 5.

---

## Part 5 — Consistency review

These issues came from reading Parts 1–4 against each other. Every fix is applied above.

| # | Problem found | Fix |
|---|---|---|
| 1 | Drafts targeted macOS 26 but relied on token APIs and image input | Minimum macOS 27; matrix updated |
| 2 | "Rename every file" vs respecting good names | Generic names only, by default |
| 3 | Model picks folders vs predictable moves | Rules only (K2) |
| 4 | Cloud APIs vs no network access | On-device only in v1 |
| 5 | "Never change extensions" vs a lowercase option | Byte-for-byte unless Lowercase is chosen |
| 6 | Protected words vs lowercase styles | The case setting wins in lower, upper, camel and Pascal |
| 7 | camelCase with a word separator was allowed | Separator forced to none |
| 8 | The Descriptive preset produced 62 characters against a 60 limit | Preset max length set to 80 |
| 9 | Max length vs required tokens vs collision suffix | Suffix counted; fixed drop order; dates never cut; minimum 20 |
| 10 | "Deterministic" vs learning and OS model updates | Scoped to same file, style, learned state and OS build (F2) |
| 11 | Latency targets vs bursts and rate limits | Targets apply plugged in; correctness always applies |
| 12 | Undo removed the marker, so the restored generic name would be renamed again, in a loop | Marker stays, with state "restored" (D8) |
| 13 | Renaming an old file to a generic name triggered processing | Only *arrived* events trigger (D9) |
| 14 | Drag-and-drop renaming vs sandbox | One-time folder grant (M6) |
| 15 | Finder menu "everywhere" vs sandbox | Granted folders only |
| 16 | Drops went to Review in one place and Quick Rename in another | Always Quick Rename |
| 17 | "Suggest" and "Review" used for the same mode | "Review" everywhere |
| 18 | Glass cards on content | Glass on exactly three surfaces |
| 19 | The status pill was glass inside the glass panel | Plain capsule |
| 20 | Glass prominent buttons inside glass panels | Standard prominent style inside glass panels |
| 21 | Examples might store file content | Names only |
| 22 | Typed names were restyled | Sanitized only, with a visible notice |
| 23 | Confidence required "kind ≠ Other" even when kind wasn't in the template | Only required tokens count |
| 24 | Burst guard and notification batching looked like one mechanism with two thresholds | Separated and named |
| 25 | Image input vs the textual-evidence rule for sources | Rule kept; logo-only sources dropped |
| 26 | Restore after a history purge had no data | The marker carries the original name |
| 27 | Quick Rename ≤ 300 ms vs a cold launch | Separate 1.5 s target |
| 28 | Learn-from-folder implied lasting access | One-time read |
| 29 | exFAT and network volumes vs marker and event reliance | APFS and Mac OS Extended only |
| 30 | Screenshot app detection used the time the file appeared | Capture time plus app timeline |
| 31 | Quick Rename didn't say whether rules move the file | "Move to …" checkbox, on by default |
| 32 | Explicit requests on iCloud placeholders would download them | Metadata-only proposal, no download |
| 33 | M4 allowed 100 ms hangs while U2 says 50 ms | M4 now points to U2 |
| 34 | The "Go Automatic?" threshold had no UI or test | Added to Folders/panel and O6 |
| 35 | 3.20 had no home for the pipeline that connects the modules, so it could only be tested through the UI | NomenEngine module added to 3.20; it has no UI and runs in tests with fakes |
| 36 | With camelCase or PascalCase (no word separator), a compact date and time ran together into a 12-digit number, which the PII rule forbids | The time joins the date with the word separator, or "-" when there is none |
| 37 | "None of them is renamed automatically" could not hold for files renamed seconds before the 11th arrived without delaying every rename by 30 s, which breaks the 3.19 latency targets | The burst covers files still waiting when it begins and files arriving during it; D6 tests files copied in at once |
| 38 | The 3-letter rule made two-character Japanese and Chinese names ("東京") generic | Han, kana and Hangul characters count as two letters |
| 39 | ASCII only with the " – " part separator produced non-ASCII names | The combination can't be saved (H7) |
| 40 | Max length 20 with a long date format, a time and a collision suffix could not fit without cutting the date | The time is dropped before the date would be cut |
| 41 | "Explicit rules" for extensions did not say what counts as an extension, so "Report v1.2" would lose ".2" | An extension is 1–15 ASCII letters and digits with a letter, or three digits; multi-part tar extensions as listed |
| 42 | Never-include phrases could span two tokens, and month names could not be removed from dates without cutting them | Entries are single words; month names are refused with the month-name date format |
| 43 | Kind Other would have appeared as the word "Other" in names | Other adds nothing to a name; it still counts as empty for confidence |
| 44 | The month-name format was undefined for padding and for Japanese, Chinese and Korean | Unpadded day; CJK dates in their native order |
| 45 | "Browser duplicate suffixes" as a generic pattern would rename "Invoice (1)" and similar chosen names | The suffix counts only together with a generic word |
