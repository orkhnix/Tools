# Folio PDF for iPhone and iPad

An original, native SwiftUI PDF workspace built with Apple's PDFKit, Vision, and VisionKit. Requires iOS/iPadOS 17 or later. No third-party app dependencies, login, subscription, analytics, or app-operated document uploads.

**Build status: version 1.0.1 (2), unsigned IPA produced successfully.** GitHub Actions built the iOS device archive with Xcode 16.4 on macOS and all 16 automated iPhone Simulator tests passed. [Successful build](https://github.com/orkhnix/Tools/actions/runs/39646444971), source commit `d11d5cb3290654ca5a84873dc2f0fdab2d90faf6`. The downloaded IPA was checked for ZIP integrity, arm64 executable architecture, iOS device platform, required assets, and absence of encryption, a developer signature, and a provisioning profile. It requires iOS 17.0 or later and must be signed with your certificate and matching provisioning profile before installation. Physical-device behavior and visual/UI workflows have not been comprehensively verified. No Adobe binaries, source code, private APIs, or assets were examined or copied, and no reverse engineering of Adobe Acrobat was performed.

## Implemented in source

| Area | Included behavior |
| --- | --- |
| Library | Import PDFs from Files/Open In; search filenames; thumbnails; rename; duplicate; delete with confirmation |
| Reader | Scroll, zoom, text selection, text search and result navigation; iPhone and iPad layouts |
| Markup | Highlight selected text; place free-text annotations and notes; draw ink; remove annotations; bounded undo |
| Sign | Draw a signature and tap to place it as native PDF ink |
| Pages | Rotate; move up/down; extract selected pages into a new PDF; delete selected pages while retaining at least one |
| Combine | Select PDFs in the desired merge order and create a new document |
| Capture | Scan paper using the system document camera; import up to 20 selected photos into a PDF |
| Recognize | On-device OCR of the current page into selectable/shareable plain text |
| Protect | Unlock protected PDFs for reading; export an editable working document as a password-protected copy |
| Export | Save PDF annotations; share a PDF copy using the system share sheet |

Imports are copied into the app's private document directory. Original source files are not overwritten. Save, Close, and application inactivity save the working copy. Changes that occur after the last completed save can be lost if the process is terminated unexpectedly. The document list remains private to the app; use Share to export copies. iOS backup settings may include app documents. User-initiated sharing sends content to the destination selected in the system sheet.

## Build on a Mac

1. Install Xcode 16 or later with an iOS SDK and Simulator runtime.
2. Open `FolioPDF.xcodeproj` and select the **FolioPDF** scheme.
3. For the Simulator, select an available iPhone/iPad and choose **Product → Run**.
4. For a physical iPhone, choose your team in **Signing & Capabilities** and replace `com.example.FolioPDF` with your own unique bundle ID. Connect the phone, enable Developer Mode when required, and run.
5. Run **Product → Test** or `bash scripts/test_ios.sh` before trusting edited documents.

There is no CocoaPods, npm, Swift Package Manager, or XcodeGen setup step. A shared scheme and complete Xcode project are included. If you add source files later, regenerate references using `python3 scripts/generate_project.py` or add the files through Xcode.

## Export a signed IPA

On a Mac with Xcode, an Apple account configured in Xcode, and an appropriate signing identity/provisioning profile:

```bash
TEAM_ID=YOURTEAMID \
BUNDLE_ID=com.yourcompany.foliopdf \
EXPORT_METHOD=debugging \
bash scripts/export_ipa.sh
```

The resulting file is written to `build/export/` only after archive and export succeed. Other script methods are `release-testing` and `app-store-connect`. The script uses automatic signing and may update your developer provisioning assets through Xcode. Distribution methods have Apple account, membership, device registration, and provisioning requirements. Personal Team device development is not equivalent to an unrestricted distributable IPA. Do not put Apple passwords or private signing keys in source control or chat.

The Xcode alternative is **Product → Archive → Distribute App**, then choose the distribution route appropriate for your account and device. A signed archive must be exported with a profile that permits its intended installation. A source ZIP or an unsigned IPA cannot be installed directly as a normal signed iPhone app.

## Cloud Mac build

The repository-root `.github/workflows/folio-ios.yml` builds the project in `FolioPDF/` on the `folio-pdf-build` branch. It compiles for the Simulator, runs the tests, builds an unsigned device archive, and publishes `FolioPDF-unsigned.ipa` after those steps succeed. [Build 39646444971](https://github.com/orkhnix/Tools/actions/runs/39646444971) completed successfully. Account billing and runner availability follow your GitHub plan.

The unsigned artifact still needs a legitimate signing/provisioning step before iPhone installation. No signing certificates are included. The workflow does not deploy an app, upload to the App Store, or grant App Store Connect access.

## Important scope limits

- This is an original PDF utility, not Adobe Acrobat or a full replacement for its feature set.
- Existing PDF paragraphs/fonts are not rewritten; the Text tool creates an annotation. Existing text annotations are removed and recreated to change their contents.
- There is no PDF-to-Word conversion, cloud sync, e-signature service, certificate-based signing, secure redaction, PDF/A validation, or general PDF compression.
- OCR returns plain text in the system-supported recognition languages. It does not add a searchable text layer to the PDF or guarantee a specific language's accuracy.
- Encrypted and permission-restricted PDFs are read-only, even after unlocking. They cannot be merged or extracted through the app. Sharing a protected original preserves its original file bytes. No password bypass is implemented.
- Handwritten signatures are ordinary ink annotations. They do not authenticate identity or provide certificate-backed integrity.
- Undo stores up to eight snapshots, with a 60 MB total budget. Individual documents over 30 MB do not get full-document undo snapshots. Native PDFKit form edits are not individually tracked by this undo history.
- PDF imports are limited to 150 MB per file. Very complex or large documents may still cause memory pressure. No performance certification is claimed.
- The camera scanner needs supported hardware and camera permission; it cannot be verified using the iOS Simulator alone.
- Some existing PDF form widgets may work through PDFKit; XFA forms and arbitrary form compatibility are not claimed or verified.
- The app contains no jailbreak, DRM removal, or Adobe subscription-unlocking functionality.

## Validation and release checklist

See `VALIDATION.md` for completed checks and required Mac/device checks. Keep backups and test export/reopen behavior with representative PDFs before using important documents. The XCTest suite covers page extraction/deletion, annotation persistence, images-to-PDF, import isolation, safe names, merge order, undo/save, encryption preservation, and invalid-file protection.

## Platform documentation

- [Apple PDFKit](https://developer.apple.com/documentation/pdfkit)
- [Apple document camera](https://developer.apple.com/documentation/visionkit/vndocumentcameraviewcontroller)
- [Apple: distribution to registered devices](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices)
- [Apple: beta testing and release distribution](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases)
- [Apple: privacy manifest API categories](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)
- [GitHub-hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)

No Adobe affiliation or endorsement is claimed.

## Version 1.0.1 import fix

Import PDF now uses the native copy-mode document picker. Reading, coordinating, validating, and staging a provider file happen off the main thread; the app displays progress and a 30-second timeout/error instead of waiting indefinitely. Import starts after the picker dismisses. Successful imports clear the filename search and show a confirmation. Four additional regression tests cover main-thread responsiveness during a blocked reader, provider timeout, visible failure/progress cleanup, and a batch containing an invalid file. All 16 tests pass. Confirmation with the reported PDF on the physical iPhone is still pending.
