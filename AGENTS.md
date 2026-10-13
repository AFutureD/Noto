# Noto

A native macOS Markdown note app: a folder of notes, each one a folder with a `text.md` file, edited
one at a time in one window that renders the Markdown in place, with four global shortcuts. SwiftUI + AppKit, run as a menu bar
agent (`LSUIElement`) with an optional Dock icon. Two packages: MDTextKit, the Markdown editor
engine, and Sparkle, which updates the app.

Noto was extracted from the Notes feature of [Tinycast](https://github.com/abue-ammar/tinycast) and still
contains its code, so Noto is licensed AGPL-3.0; see [NOTICE.md](NOTICE.md). Noto no longer takes
changes from Tinycast.

## Posture: latest-only, always

Noto targets one macOS: the current stable release. macOS 26+, the Xcode 27 toolchain, Swift 6
language mode with complete strict concurrency. There is no compatibility floor, no shim layer and no
deprecation debt.

- Prefer the modern Apple API, always. Observation over `ObservableObject`. Swift Concurrency over
  `DispatchQueue` or completion handlers. Structured concurrency over detached bookkeeping.
- Migrate, never wrap. When an API gains a modern replacement, adopt it and delete the old call site.
- A deprecated API is a defect, not a warning to live with.
- No compatibility layers, no legacy workarounds, no older architectural patterns. Delete rather than
  deprecate.
- Never add backwards compatibility unless asked. No version flags, no migration scaffolding, no
  "just in case" fallbacks. The code carries no migration, and nothing is migrated from Tinycast.

Three dependencies are deliberate gaps in the modern platform: Carbon registers the system-wide
chords and reads a key's glyph from the layout; Sparkle updates an app outside the App Store;
MDTextKit is TextKit 1 and has its own repository. A change to the editor engine is a task there,
never a shim in Noto. The reasons are in [standards.md](docs/standards.md#posture).

## Where things are

| Folder | Holds |
| --- | --- |
| `Noto/App/` | `NotoApp` (`@main`), `AppDelegate`, `AppCore` (the composition root) and `MenuBarItem` |
| `Noto/DesignSystem/` | the shared visual primitives; `Theme.swift` is the only design-token source |
| `Noto/Platform/` | system shims: `AppPaths`, `ActivationPolicy`, `FolderPicker`, `Signposts`, `NotificationToken`, … |
| `Noto/Features/Notes/` | the note collection and the MDTextKit editor host, split `Model/` `Service/` `UI/` |
| `Noto/Features/HotKeys/` | the four global shortcuts and their recorder, split `Model/` `Service/` `UI/` |
| `Noto/Features/Settings/` | `NotoSettings` (every preference), `SettingsWindowController` and `SettingsView` |
| `Noto/Features/Updates/` | `UpdateCoordinator`, the owner of the Sparkle updater |
| `Tests/` | the standalone harnesses, one Swift file each, no XCTest target |
| `Resource/` | `Brand/` holds the icon source and renders; `Screenshots/` holds the README images |
| `Scripts/` | `run-tests.sh` and `lint.sh` |
| `.github/` | the release dispatcher; the build runs in [noto-releases](https://github.com/AFutureD/noto-releases) |

The documents in [docs/](docs/README.md) are in reading order. Read the one that covers what you
change:

| Before you | Read |
| --- | --- |
| build or run | [development.md](docs/development.md) |
| change how anything is wired or owned | [architecture.md](docs/architecture.md) |
| write Swift: naming, style, concurrency, comments | [standards.md](docs/standards.md) |
| add or restyle a view | [ui.md](docs/ui.md) |
| touch one feature's internals | [features/](docs/features/); each opens with its invariants |
| claim a change is done | [testing.md](docs/testing.md) |
| ship a version | [release.md](docs/release.md) |

## Non-negotiables

Never break these without an explicit task to do so. A feature's own invariants are in its document,
under `## Invariants`.

- `AppCore` is the sole owner. New long-lived state goes on `AppCore`, wired in `start()`, never on a
  competing singleton. A feature's views reach its coordinator through `@Environment`; `NotesView`
  never sees `AppCore`.
- A file under `Noto/Features/*/Model/` may not import AppKit or SwiftUI. It takes every environment
  fact (the clock, the filesystem, the directory) as a parameter. The harnesses compile the shipped
  sources, so compilation enforces this. `KeyShortcut` lives in `HotKeys/Service/` for this reason:
  it imports AppKit.
- Swift 6 language mode: a data-race violation is a hard error. `@MainActor` is the default,
  cross-actor model types are `Sendable`, and heavy or IO-bound work goes off-main as `nonisolated`
  work in `Task.detached`. Do not add an actor.
- Dark is the baseline, and a colour's dark branch is a fixed literal. `Theme.Colors` resolves per
  appearance through `ramp` and `adaptive`. Retune a light branch freely; change a dark one only when
  the task is to change Dark. Noto sets no appearance of its own.
- Notes code asks through `NotesDialogs`, never builds an alert itself. `NotesDialogs.alerts` in
  `Noto/Features/Notes/UI/NotesDialogs.swift` is the one place an `NSAlert` is constructed.
- Everything persisted is keyed by `Bundle.main.bundleIdentifier`, which a Debug build shares with an
  installed copy. A local run reads and writes the real preferences and the real notes.
- `SUPublicEDKey` in `Noto/Info.plist` pairs with the `SPARKLE_ED_PRIVATE_KEY` secret in
  noto-releases. Never change one without the other.

## Conventions

- A type's suffix says what it is: `Store`, `Coordinator`, `Controller`, `Manager`, `Policy` and the
  rest each name one responsibility. Pick the honest suffix, add a new one when none fits, and never
  rename a well-named type to match the table. The table is in
  [standards.md](docs/standards.md#naming).
- Comments are rare, one line, and explain the why: the gotcha or the invariant, never the what.
  Never two in a row. If one line cannot carry it, name a function, a constant or a type. Cap 100
  characters, delete rather than update, and never comment a change you just made. Nothing lints
  this. The rules are in [standards.md](docs/standards.md#comments).
- `Noto.xcodeproj` is the source of truth. There is no project generator, no `Package.swift` and never
  `Bundle.module`. `Noto/` is a file-system synchronized group, so a file added, moved or deleted
  under it needs no project edit. MDTextKit and Sparkle are remote package references pinned by the
  committed `Package.resolved`; the harnesses compile MDTextKit from the sibling checkout `../MDTextKit`.
- A new preference is a property on `NotoSettings` with its key in that file's `Key` enum. Window
  state that is not a preference rides `UserDefaults` from `AppCore` instead.

## Documentation language

Write all documentation in ASD-STE100 Simplified Technical English. This applies to `AGENTS.md`,
`README.md`, `NOTICE.md`, `CHANGELOG.md` and each file in `docs/`.

- Use one word for one meaning. Use the same word for the same thing each time.
- Use the active voice. Use the imperative for an instruction.
- Write short sentences: at most 20 words for an instruction, 25 for a description.
- Give one instruction per sentence. Put a condition before the instruction it controls.
- Use the simple present, past or future tense. Do not use the `-ing` form as a verb.
- Do not use idioms, metaphors or noun clusters of more than three words.
- Use a vertical list for a sequence of steps or a set of items.

Names of types, files, settings and commands are technical names. Write them as the code writes them.

`README.zh-CN.md` is the Chinese translation of `README.md`. When you change one, change the other.

## Before you finish

Each item is explained in [testing.md](docs/testing.md#definition-of-done).

- `./Scripts/run-tests.sh` passes.
- The Debug build compiles with zero warnings.
- `./Scripts/lint.sh` is clean.
- `grep -rln 'import AppKit\|import SwiftUI\|import Cocoa' Noto/Features/*/Model/` returns nothing.
- Each doc your change made wrong is fixed in the same change.
- A change the user can notice has a line under `Unreleased` in `CHANGELOG.md`.
- Each doc sentence you added or changed obeys [Documentation language](#documentation-language).
