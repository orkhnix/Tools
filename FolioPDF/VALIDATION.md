# Validation status

Updated 21 October 2026. An unsigned iOS device IPA was compiled, packaged, downloaded, and verified. It still requires signing and a matching provisioning profile before installation.

## Build evidence

- Repository: https://github.com/orkhnix/Tools/tree/folio-pdf-build/FolioPDF
- Build: https://github.com/orkhnix/Tools/actions/runs/39646444971
- Tested source commit: `d11d5cb3290654ca5a84873dc2f0fdab2d90faf6`
- Xcode: 16.4 (16F6), GitHub macOS runner
- Simulator compilation: succeeded
- XCTest: 16 tests executed, zero failures
- Release iOS device archive: succeeded
- IPA packaging/upload: succeeded
- Artifact: `FolioPDF-unsigned.ipa`, 245930 bytes
- IPA SHA-256: `d488fffee34b58f05816995e30d48b89ccf682fa9681b6b1bfb54d7e771b1f6f`
- Bundle ID: `com.example.FolioPDF`, version 1.0.1 (build 2)
- Device architecture: arm64; Mach-O platform: iOS device
- Minimum iOS: 17.0
- No developer signature, embedded provisioning profile, or executable encryption
- ZIP integrity, compiled assets, privacy manifest, and exclusion of XCTest bundles from release package: verified

The preceding source-only delivery was checked for Swift syntax, project references, plist/JSON/XML/YAML validity, shell syntax, icon structure, deterministic project regeneration, and source archive integrity. The blank-filename test failure found in the first run was corrected before the successful build above.

## What the automated tests cover

Page extraction and deletion; rejection of invalid/all-page operations; annotation persistence; images to PDF; imported original-file preservation; filename sanitization; merge order; undo and save persistence; password-export isolation; protected-PDF read-only behavior and original-byte sharing; protection of invalid files from accidental overwrite.

## Remaining manual checks

1. Sign with an appropriate certificate and provisioning profile, install on the intended iPhone/iPad, and verify launch and PDF export/reopen.
2. Exercise annotations, multiline notes, pen and signature placement on rotated/landscape pages and near page edges.
3. Verify camera approval/denial, multipage scans, cancellation, and supported hardware.
4. Test Files/iCloud providers, Open In, ordered photo imports, and OCR on representative real documents.
5. Check iPad/iPhone layouts, VoiceOver, large text, dark appearance, and keyboard/sheet behavior.
6. Check native PDFKit form behavior, encrypted PDFs, failing/cancelled imports, low storage, and representative large documents.
7. Background/resume with edits open, retain original backups, and test persistence and memory pressure.

No physical-device testing, signing, installation, comprehensive visual QA, App Store review, or production-readiness certification is claimed. Documentation-only updates after the tested source commit do not change the app binary.

## Version 1.0.1 import regression checks

The importer now stages app-owned copies using a worker thread. Tests confirm that a blocked reader leaves the main thread responsive, a stalled reader times out, invalid input leaves a visible error and clears progress, and a later valid PDF still imports after an invalid file in the same batch. These four tests and the preceding twelve passed in the build above. The native Files-picker flow and the user-reported file still require confirmation on the physical device.
