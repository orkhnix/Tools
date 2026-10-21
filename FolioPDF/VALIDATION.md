# Validation status

Updated 21 October 2026. An unsigned iOS device IPA was compiled, packaged, downloaded, and verified. It still requires signing and a matching provisioning profile before installation.

## Build evidence

- Repository: https://github.com/orkhnix/Tools/tree/folio-pdf-build/FolioPDF
- Build: https://github.com/orkhnix/Tools/actions/runs/39642201220
- Tested source commit: `740b6dc3010337d7c5cc856f360e37d83ad56ffe`
- Xcode: 16.4 (16F6), GitHub macOS runner
- Simulator compilation: succeeded
- XCTest: 12 tests executed, zero failures
- Release iOS device archive: succeeded
- IPA packaging/upload: succeeded
- Artifact: `FolioPDF-unsigned.ipa`, 233146 bytes
- IPA SHA-256: `d746170cf48a8a074a0e5709797f6702ca9e68044b134bdb8de4c5c732efa0fb`
- Bundle ID: `com.example.FolioPDF`, version 1.0 (build 1)
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
