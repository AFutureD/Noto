# Development

The local loop: set up, build, run. [testing.md](testing.md) tells you how to verify a change.

## Requirements

- macOS 26 or later.
- Xcode 27 or later. It provides the SwiftUI macros, the SDK and the `actool` that compiles the
  Icon Composer icon.
- An Apple Developer account in the team of the target (`8GSN8K4KD9`), signed in to Xcode
  (Xcode > Settings > Accounts).
- The MDTextKit checkout as a sibling folder, `../MDTextKit`, for the harnesses.
- For lint: `brew install swiftlint`.

Xcode resolves two packages from GitHub on the first build, MDTextKit and Sparkle, so that build
needs the network. Code signing is automatic with the Apple Development identity of the team in the
target. The iCloud entitlements need a development provisioning profile that includes the container
`iCloud.app.huanan.noto`. Xcode makes it with the account above. Noto asks for no permission: its
hotkeys are Carbon registrations, so it does not need Accessibility.

## Build and run

```sh
open Noto.xcodeproj    # then ⌘R
```

From the command line:

```sh
xcodebuild -project Noto.xcodeproj -scheme Noto -configuration Debug \
    -derivedDataPath build/DerivedData -allowProvisioningUpdates build
open "build/DerivedData/Build/Products/Debug/Noto Dev.app"
```

`-allowProvisioningUpdates` lets `xcodebuild` make or update the development profile with the account
that is signed in to Xcode. Without it, or without the account, the build cannot sign the iCloud
entitlements and fails.

`xcodebuild` uses the toolchain that `xcode-select` points at. If that is the Command Line Tools, set
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` first. The SwiftUI macros need Xcode's
macOS platform.

`-configuration Release` builds `build/DerivedData/Build/Products/Release/Noto.app` with the hardened
runtime on. `build/` is git-ignored. A release is not built here; see [release.md](release.md).

The app is a menu bar agent. A fresh launch shows only the `text.page` item in the menu bar. Pick Show
Notes there to open the window.

## Debug and Release

A Debug build is `Noto Dev.app`. A Release build is `Noto.app`. Both carry the bundle id
`app.huanan.noto`, and every persisted value is keyed by that id:

- `~/Library/Preferences/app.huanan.noto.plist` holds every `NotoSettings` key, the hotkey bindings,
  the active note, the formatting bar's state and the window frame.
- `~/Library/Application Support/app.huanan.noto/Notes/` holds the notes, unless a folder is chosen.
- The iCloud container `iCloud.app.huanan.noto` holds the notes while iCloud Sync is on. The
  iCloud key-value store of the bundle id holds the synced settings.

So the two builds share one state. A Debug run edits the real notes and the real settings. With Sync
with iCloud on, it also edits them on each device of the iCloud account. See
[sync.md](features/sync.md#testing-notes). Do not run
both builds at the same time: they would write the same files, and the second one cannot register the
hotkeys the first one holds. `Bundle.main.appDisplayName` puts "Noto Dev" in the menu bar item, the
Quit item and the Settings title.

To test a first run without loss of that state, see [testing.md](testing.md#clean-install).

## The project

`Noto.xcodeproj` is the source of truth. Edit it in Xcode or by hand in `project.pbxproj`. Nothing
generates it. There is no `Package.swift`, and never `Bundle.module`.

- One app target, `Noto`, and one shared scheme, `Noto`. The scheme builds Debug for Run and Release
  for Archive.
- `Noto/` is a file-system synchronized group. Every file under it is a member of the target. To add,
  move or delete a source file, change the file system; the project needs no edit.
- `Noto/AppIcon.icon` is the app icon, an Icon Composer document. `actool` compiles it into
  `Assets.car` and `AppIcon.icns`.
- `Noto/Info.plist` is a build input (`INFOPLIST_FILE`), not a bundle resource.
- `Noto/Noto.entitlements` turns the App Sandbox off, because Noto reads and writes a folder the user
  names. It also gives iCloud Documents (`CloudDocuments`) in the container `iCloud.app.huanan.noto`,
  and iCloud key-value storage under `$(TeamIdentifierPrefix)$(CFBundleIdentifier)`. These
  entitlements need a provisioning profile: a development profile for Debug, and the Developer ID
  profile for a release (see [release.md](release.md#secrets)).
- MDTextKit and Sparkle are remote package references, pinned in
  `Noto.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`, which is committed.
  MDTextKit is pinned to an exact version. Change a version in Xcode's package editor and commit both
  files. The release build checks out Noto alone, so a local package reference cannot ship.
- `Scripts/run-tests.sh` compiles MDTextKit's sources from `MDTEXTKIT_DIR` (default `../MDTextKit`),
  so the harnesses see the checkout, not the pin. Keep the checkout at the pinned tag, or at the
  change you are about to release.
- `Tests/` shows in the navigator but belongs to no target. Each harness has its own `@main`, and
  `Scripts/run-tests.sh` compiles it. `Scripts/` is outside the project.

The build settings that define the app:

| Setting | Debug | Release |
| --- | --- | --- |
| `PRODUCT_NAME` | `Noto Dev` | `Noto` |
| `PRODUCT_BUNDLE_IDENTIFIER` | `app.huanan.noto` | `app.huanan.noto` |
| `MACOSX_DEPLOYMENT_TARGET` | 26.0 | 26.0 |
| `ARCHS` | arm64 | arm64 |
| `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION` | the version | the version, equal to the tag; see [release.md](release.md#the-version-rule) |
| `SWIFT_VERSION`, `SWIFT_STRICT_CONCURRENCY` | 6.0, `complete` | 6.0, `complete` |
| `CODE_SIGN_IDENTITY`, `CODE_SIGN_STYLE` | Apple Development, Automatic | Apple Development, Automatic |
| `ENABLE_HARDENED_RUNTIME` | off | on |

`Info.plist` takes its name, identifier, versions and minimum system from these settings. It adds
`LSUIElement`, the three Sparkle keys `SUFeedURL`, `SUPublicEDKey` and `SUEnableAutomaticChecks`, and
`NSUbiquitousContainers`. That key makes the `Documents` folder of `iCloud.app.huanan.noto` public in
iCloud Drive with the name `Noto`.

## Lint

```sh
./Scripts/lint.sh          # lint the whole project
./Scripts/lint.sh --fix    # auto-correct the mechanical rules first
```

SwiftLint is the only code-quality tool. `.swiftlint.yml` covers `Noto/` and `Tests/` with rules that
catch defects. Errors block, warnings do not. The comment rules in
[standards.md](standards.md#comments) are not linted. There is no formatter: format with Xcode's
re-indent (⌃I). `.swift-format` at the root gives an editor that uses `swift-format` this tree's
4-space indent and 110-column lines.

## Editor support

`xcodebuild` never compiles the harnesses, so an editor on SourceKit-LSP cannot resolve `Tests/`.
`./Scripts/run-tests.sh --index` writes one compile command per harness into a git-ignored `.compile`
file at the root. It needs Node. A build server that reads `.compile` is not part of the repository.
