# Noto

A native macOS Markdown note app: an unlimited collection of plain `.md` files in one editor window
that renders the Markdown in place, with four global shortcuts. SwiftUI + AppKit, running as a
menu-bar agent (`LSUIElement`) with an optional Dock icon. Zero third-party dependencies.

Noto was extracted from the Notes feature of [Tinycast](https://github.com/abue-ammar/tinycast) and is
licensed AGPL-3.0; see [NOTICE.md](NOTICE.md).

## Posture: latest-only, always

Noto targets one macOS — the current stable release — and nothing else. macOS 26+, the Xcode 26
toolchain, Swift 6 language mode with complete strict concurrency. There is no compatibility floor to
defend, no shim layer and no deprecation debt.

Write code as if the platform released yesterday:

- Prefer the modern Apple API, always. Observation over `ObservableObject`. Swift Concurrency over
  `DispatchQueue` or completion handlers. Structured concurrency over detached bookkeeping.
- Migrate, never wrap. When an API gains a modern replacement, adopt it and delete the old call
  site.
- A deprecated API is a defect, not a warning to live with.
- No compatibility layers, no legacy workarounds, no older architectural patterns. Delete rather
  than deprecate.
- Never introduce backwards compatibility unless explicitly asked for it. No version flags, no
  migration scaffolding, no "just in case" fallbacks. The codebase carries no migration — nothing is
  migrated from Tinycast either — and adding one needs an explicit task saying so.

Carbon is a deliberate capability-gap dependency rather than inertia: nothing modern registers a
system-wide chord, and HIToolbox's TIS APIs remain the public way to read a key's glyph from the
keyboard layout. Full reasoning in [standards.md](docs/standards.md#posture).

## Where things are

| Folder | Holds |
| --- | --- |
| `Noto/App/` | `NotoApp` (`@main`), `AppDelegate`, `AppCore` — the composition root — and `MenuBarItem` |
| `Noto/DesignSystem/` | shared visual primitives; `Theme.swift` is the only design-token source |
| `Noto/Platform/` | system shims: `AppPaths`, `ActivationPolicy`, `FolderPicker`, `Signposts`, `NotificationToken`, … |
| `Noto/Windows/` | `AppWindowController`, the titled window Settings opens in |
| `Noto/Features/Notes/` | the note collection and editor, split `Model/` `Service/` `UI/` |
| `Noto/Features/HotKeys/` | the four global shortcuts and their recorder, split `Model/` `Service/` `UI/` |
| `Noto/Features/Settings/` | `NotoSettings` (every preference) and `SettingsView` |
| `Tests/` | the standalone harnesses — one Swift file each, no XCTest target |
| `Scripts/` | `run-tests.sh` and `lint.sh` |

| Read it before you | Doc |
| --- | --- |
| change how anything is wired or owned | [architecture.md](docs/architecture.md) |
| write Swift — naming, style, concurrency, comments | [standards.md](docs/standards.md) |
| claim a change is done | [testing.md](docs/testing.md) |
| build or run | [development.md](docs/development.md) |
| add or restyle any view | [ui.md](docs/ui.md) |
| touch one feature's internals | [features/](docs/features/) — each opens with its invariants |

## Non-negotiables

Never break these without an explicit task to do so. Anything feature-specific lives in that
feature's doc, under its own `## Invariants`.

- `AppCore` is the sole owner. New long-lived state goes on `AppCore`, wired in `start()` — never a
  competing singleton. A feature's views reach its coordinator through `@Environment`; `NotesView`
  never sees `AppCore`.
- A file under `Noto/Features/*/Model/` may not import AppKit or SwiftUI, and takes every environment
  fact — clock, filesystem, directory — as an injected parameter. The harnesses compile the shipped
  sources, so this is enforced by compilation rather than convention. `KeyShortcut` lives in
  `HotKeys/Service/` for exactly this reason: it imports AppKit.
- Swift 6 language mode: data-race violations are hard errors. `@MainActor` is the default,
  cross-actor model types are `Sendable`, and heavy or IO-bound work goes off-main as `nonisolated`
  work driven by `Task.detached`. Do not add an actor.
- Dark is the baseline, and a colour's dark branch is a fixed literal. `Theme.Colors` resolves per
  appearance through `ramp`/`adaptive`. Retune a light branch freely — change a dark one only when the
  task is to change Dark. Noto sets no appearance of its own; it follows macOS.
- Notes code asks through `NotesDialogs`, never builds an alert itself. `NotesDialogs.alerts` in
  `Noto/Features/Notes/UI/NotesDialogs.swift` is the one place an `NSAlert` is constructed, which is
  what keeps the coordinator free of presentation.
- Anything persisted stays keyed by `Bundle.main.bundleIdentifier`, so a Debug build never shares
  preferences or notes with an installed copy.

## Conventions worth knowing up front

- A type's suffix says what it is — `Store`, `Coordinator`, `Controller`, `Manager`, `Policy` and the
  rest each name a specific responsibility. Semantic correctness always wins over suffix consistency:
  pick the suffix that describes the type honestly, add a new one when none fits, and never rename a
  well-named type just to match the table. Full table: [standards.md#naming](docs/standards.md#naming).
- Comments are rare, one line, and explain the why — the gotcha or invariant, never the what.
  Never two in a row, never extended into a block: if one line can't carry it, name a function,
  constant or type instead. Cap 100 characters, delete rather than update, and never comment a change
  you just made. Nothing lints this; get it right the first time.
  Full rules: [standards.md#comments](docs/standards.md#comments).
- Debug and Release share one bundle id, `app.huanan.noto`; only the name differs (`Noto Dev.app`).
  A local run reads and writes the real preferences and the real notes folder, so treat them as such.
- The project is edited directly. `Noto.xcodeproj` is the source of truth; there is no project
  generator, no SwiftPM, and never `Bundle.module`. The `Noto/` folder is a file-system synchronized
  group, so adding, moving or deleting a file under it needs no project edit. See
  [development.md](docs/development.md#the-project).
- A new preference is a property on `NotoSettings` with its key in that file's `Key` enum. Window
  state that is not a preference rides `UserDefaults` from `AppCore` instead.

## Documentation language

Write all documentation in ASD-STE100 Simplified Technical English. This rule applies to `AGENTS.md`,
`README.md`, `NOTICE.md` and each file in `docs/`.

- Use one word for one meaning. Use the same word for the same thing each time.
- Use the active voice. Use the imperative for instructions.
- Write short sentences: a maximum of 20 words for an instruction, 25 words for a description.
- Give one instruction in each sentence. Put a condition before the instruction it controls.
- Use the simple present, the simple past or the simple future tense. Do not use the `-ing` form as
  a verb.
- Do not use idioms, metaphors or noun clusters of more than three words.
- Use a vertical list for a sequence of steps or a set of items.

Names of types, files, settings and commands are technical names. Write them as the code writes them.

## Before you finish

Each item is explained in [testing.md](docs/testing.md#definition-of-done).

- `./Scripts/run-tests.sh` passes.
- The Debug build compiles with zero warnings.
- `./Scripts/lint.sh` is clean.
- `grep -rln 'import AppKit\|import SwiftUI\|import Cocoa' Noto/Features/*/Model/` returns nothing.
- Any doc your change made wrong is fixed in the same change.
- Each doc sentence you added or changed obeys [Documentation language](#documentation-language).
