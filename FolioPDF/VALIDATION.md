# Validation status

Created 21 October 2026. This delivery contains source code. It contains no compiled `.app`, device archive, signed/unsigned `.ipa`, certificate, or provisioning profile.

## Completed in the authoring environment

- Swift source syntax parsed using the Swift grammar for tree-sitter; no syntax errors detected.
- Xcode OpenStep project parsed; source/resource paths and object-reference graph checked.
- Both build targets and the shared FolioPDF scheme verified structurally.
- Info.plist and the privacy manifest parsed with Python plistlib.
- Asset catalog JSON and app icon file verified structurally.
- Scheme XML parsed.
- Build/test shell scripts checked with `bash -n`.
- Project regeneration checked for deterministic output.
- Source archive integrity and file inventory checked.

These checks are not Swift type-checking, iOS compilation, XCTest execution, visual QA, or a substitute for running the app.

## Not executed here

- Xcode compile, linker, and asset catalog compiler
- All 12 XCTest methods in `FolioPDFTests/PDFOperationsTests.swift`
- Simulator UI, accessibility, keyboard, navigation, and sheet behavior
- Device scanning, permission-denial handling, photo import, OCR, memory, and performance
- Device archive, code signing, IPA export, installation, or launch
- The GitHub Actions workflow

## Required Mac checks

1. Open the Xcode project and resolve any compiler/SDK warnings or errors.
2. Run `bash scripts/test_ios.sh` and inspect the `.xcresult` report. Fix failures before continuing.
3. In Simulator, create a sample PDF; annotate, save, close, reopen, share to Files, then reopen the exported copy.
4. Verify both landscape and portrait PDFs, rotated pages, text placement near page edges, multiline notes, highlights across lines/pages, ink and signature placement, erasing, and undo.
5. Confirm page order, extraction, merge order, and the block on deleting every page.
6. Open encrypted PDFs, test incorrect/correct passwords, and confirm read-only widgets and protection-preserving sharing.
7. Export a password-protected copy, check that another PDF viewer asks for its password, and confirm the working copy stays unencrypted.
8. Test failing/cancelled imports, unreadable PDFs, duplicate filenames, read/write failure, protected PDFs, and low-storage errors.
9. Test iPhone and iPad layouts, largest accessibility text, VoiceOver focus, and dark appearance.

## Required physical-device checks

1. Test camera permission approval/denial, scanning cancellation, multipage capture, and unsupported-device behavior.
2. Test Files/iCloud providers and Open In, photos from the ordered picker, and OCR on real scanned pages.
3. Test drawing with a finger and Apple Pencil where available.
4. Background/resume the app with edits open and verify persistence.
5. Profile representative large documents and repeated imports/exports for memory pressure and temporary-file growth.
6. Archive and export using your own signing configuration; verify installation, Developer Mode where required, launch, and round-trip PDF export on the intended phone.

Only after these checks pass should a compiled build be described as tested or ready for use. Store distribution would require additional privacy, accessibility, security, compatibility, and release review.
