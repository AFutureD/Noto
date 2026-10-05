# Development

The local loop: set up, build, run. Verifying a change is [testing.md](testing.md).

## Requirements

- macOS 26 or later (Liquid Glass).
- Xcode 26 or later — it provides the SwiftUI macro plugin and the SDK.
- For linting: `brew install swiftlint`.

That is the whole setup. There is no package to resolve and no project to generate. Signing is
automatic with the Apple Development identity of the team set in the target, and Noto asks for no
permission — its hotkeys are Carbon registrations, so not even Accessibility.

## Build & run

```sh
open Noto.xcodeproj    # then ⌘R
```

Or from the command line:

```sh
xcodebuild -project Noto.xcodeproj -scheme Noto -configuration Debug \
    -derivedDataPath build/DerivedData build
open "build/DerivedData/Build/Products/Debug/Noto Dev.app"
```

`xcodebuild` uses whatever `xcode-select` points at; if that's the Command Line Tools rather than
Xcode, prefix with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (the SwiftUI
`@State`/`@FocusState` macros need Xcode's macOS platform).

`-configuration Release` builds `build/DerivedData/Build/Products/Release/Noto.app` the same way, with
the hardened runtime on. `build/` is git-ignored.

The app is a menu-bar agent: a fresh launch shows only the `text.page` item in the menu bar, and no
window until you pick Show Notes there.

### Debug and Release

A Debug build is `Noto Dev.app`, a Release build is `Noto.app`, and both carry the bundle id
`app.huanan.noto`. Every persisted thing is keyed by that id — `~/Library/Preferences/app.huanan.noto.plist`
(every `NotoSettings` key, the hotkey bindings, the active note, the formatting bar's state and the
window frame) and `~/Library/Application Support/app.huanan.noto/Notes/` (the notes, unless a folder
is chosen) — so the two builds share one state. `Bundle.main.appDisplayName` is what puts "Noto Dev"
in the menu bar item's label, the Quit item and the Settings window title.

Consequences worth knowing:

- A Debug run edits the real notes and the real settings.
- Don't run both builds at once: they would be two writers of the same files, neither watching the
  other, and the second to launch fails to register the hotkeys the first holds.

To test a first run without losing that state, see [testing.md](testing.md#clean-install).

## The project

`Noto.xcodeproj` is maintained directly — in Xcode, or by hand in `project.pbxproj`. Nothing generates
it. There is no `Package.swift`, and `Bundle.module` must never be used.

- One app target, `Noto`, and one shared scheme, `Noto`, which builds Debug for Run and Release for
  Archive.
- The `Noto/` folder is a file-system synchronized group (`PBXFileSystemSynchronizedRootGroup`, project
  object version 77). Every file under it is a member of the target by being there: adding, renaming,
  moving or deleting a source file, or adding an asset, needs no project edit and produces no
  `project.pbxproj` diff.
- `Noto/Info.plist` is the one membership exception: it is a build input (`INFOPLIST_FILE`), not a
  bundle resource. `Noto/Noto.entitlements` is consumed by signing (`CODE_SIGN_ENTITLEMENTS`).
- `Tests/` shows in the Xcode navigator but belongs to no target, and `Scripts/` is outside the project.
  Keep it that way: each harness has its own `@main`. The harnesses are compiled by
  `Scripts/run-tests.sh`, so a new shipped source that a harness needs is added to that script's list —
  that is the only list there is.

Build settings are edited in Xcode's target editor (or the two `XCBuildConfiguration` blocks per level
in `project.pbxproj`). The ones that define the app:

| Setting | Debug | Release |
| --- | --- | --- |
| `PRODUCT_NAME` | `Noto Dev` | `Noto` |
| `PRODUCT_BUNDLE_IDENTIFIER` | `app.huanan.noto` | `app.huanan.noto` |
| `MACOSX_DEPLOYMENT_TARGET` | 26.0 | 26.0 |
| `SWIFT_VERSION` / `SWIFT_STRICT_CONCURRENCY` | 6.0 / `complete` | 6.0 / `complete` |
| `CODE_SIGN_IDENTITY` / `CODE_SIGN_STYLE` | Apple Development / Automatic | Apple Development / Automatic |
| `ENABLE_HARDENED_RUNTIME` | off | on |

`Info.plist` takes its name, identifier, versions and minimum system from those settings and adds
`LSUIElement`. The entitlements file turns the App Sandbox off: Noto reads and writes a folder the user
names by path.

## Editor

Xcode works out of the box and needs nothing here.

`xcodebuild` never compiles the harnesses, so in an editor driven by SourceKit-LSP nothing in `Tests/`
resolves by default. `./Scripts/run-tests.sh --index` exists for that: instead of running anything it
merges one compile command per harness — including `notes-editor-performance` — into a git-ignored
`.compile` at the repo root, with absolute paths and an explicit `-sdk`, claiming only the files under
`Tests/`. It needs Node, and it is only useful to a build server that reads `.compile`; the repo ships
no script that sets one up, so that part is yours.

## Linting

```sh
./Scripts/lint.sh          # lint the whole project
./Scripts/lint.sh --fix    # auto-correct the mechanical subset first
```

[SwiftLint](https://github.com/realm/SwiftLint) is the only code-quality tool here. `.swiftlint.yml` at
the repo root covers `Noto/` and `Tests/`, sticks to rules that catch defects, and stays quiet about
style. Errors block, warnings do not; `force_try` is an error and `force_cast` a warning. The comment
policy in [standards.md](standards.md#comments) is deliberately not among its rules. Nothing runs the
script for you.

There is no formatter and no format script. Formatting is Xcode's re-indent (⌃I). A `.swift-format`
config sits at the repo root so that an editor formatting through `swift-format` uses this tree's
4-space indent and 110-column lines instead of the stock defaults; it is not part of the bar.
