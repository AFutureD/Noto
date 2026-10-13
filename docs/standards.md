# Engineering standards

How code in Noto is written. This is guidance: it describes the codebase as it is, so new code reads
as if it was always there. A good reason to depart from it is a good reason. The checks that must
pass are in [testing.md](testing.md#definition-of-done). The rules that may never break are the
invariants; [`AGENTS.md`](../AGENTS.md#0x04-改动之前) lists where each set lives.

When this document and the code disagree, the code is probably right and this file is stale. Fix it.

## Posture

Noto targets one macOS: the current stable release, built with the current Xcode toolchain in Swift 6
language mode with complete strict concurrency. The versions are in
[development.md](development.md#requirements). There is no compatibility floor, no shim layer and no
deprecation debt. This section gives the reason and the shape.

A compatibility floor is not a one-time cost. Each shim outlives the platform that needed it, the next
feature copies it, and a one-line call becomes a layer nobody dares delete. Noto has no external API,
no plugin surface and one supported OS. It has nothing to be compatible with.

In practice:

- Observation, never `ObservableObject` or `@Published`.
- `async`/`await`, never a completion handler or a `DispatchQueue` hop.
- Structured concurrency, never detached bookkeeping you have to remember to cancel.
- When an API gains a successor, the migration is the change. Do not wrap the old spelling.
- A deprecated API is a defect, not a warning to live with.
- No backwards compatibility unless asked: no version flag, no migration scaffolding, no "just in
  case" fallback. The code carries no migration, and nothing is migrated from Tinycast.

Three dependencies are deliberate gaps in the modern platform:

- Carbon: `HotKeyCenter` uses `RegisterEventHotKey`, because nothing modern registers a system-wide
  chord. `ASCIIKeyboardLayout` uses the TIS APIs and `UCKeyTranslate`, because they remain the
  public way to turn a key code into the glyph the current layout prints.
- Sparkle: macOS does not update an app outside the App Store.
- MDTextKit: the editor engine, a TextKit 1 package in its own repository. Noto adopts it whole. A
  gap in the engine is a change to the package, never a workaround in `NoteTextView`.

## Organization

The detail is in [architecture.md](architecture.md). A new feature must satisfy these rules:

- One folder per feature under `Noto/Features/<Name>/`.
- A larger feature splits into `Model/` (pure), `Service/` (effects) and `UI/` (views, window
  controllers, the coordinator). A small one stays flat, as `Settings/` does. Split when the flat
  folder stops being scannable.
- `Model/` may not import AppKit or SwiftUI. Every environment fact is injected. The harnesses enforce
  this.
- New long-lived state goes on `AppCore`, wired in `start()`. Never a second singleton.
- Shared visual primitives go in `DesignSystem/`, system shims in `Platform/`. Neither may depend on a
  feature.
- A new file under `Noto/` needs no project edit.
- A feature's actions live on its coordinator. A confirmation gate lives in the coordinator, never in
  the store or the repository.

## Naming

A type's suffix says what it is. Pick the suffix that names the responsibility honestly. Add a row
when none fits. Do not rename a well-named type to fit the table.

| Suffix | Means | Here |
| --- | --- | --- |
| `Store` | Owns state and publishes it | `NotesStore` |
| `Repository` | File semantics a `Store` does not imply: validation, unique-name claiming | `NotesRepository` |
| `Coordinator` | A feature's action surface, called by `AppCore` and views | `NotesCoordinator` |
| `Controller` | Owns one AppKit window or surface | `NotesWindowController`, `SettingsWindowController` |
| `Manager` | Owns a subsystem's lifecycle and its policy; started from `AppCore.start()` | `HotKeyManager` |
| `Center` | The Carbon registration layer | `HotKeyCenter` |
| `Session` | Transient state of one in-progress interaction | `ShortcutCaptureSession` |
| `Policy` | A pure decision: no state, no effects | none at present |
| `Settings` | Every preference, mirrored to `UserDefaults` | `NotoSettings` |

`Manager` means lifecycle plus policy, which is a lot for one type, so there is one. Before you add
another, check whether `Store` or `Coordinator` describes it better.

`ActivationPolicy` is named for `NSApplication.ActivationPolicy`, which it applies. SwiftUI names
(`View`, `Row`, `Bar`, `Button`, `Menu`) are a separate vocabulary.

Files: one top-level type per file, named for it. A file that groups small siblings is named for what
they share: `MenuBarItem.swift` (label and menu), `NoteDocument.swift` (the note value types). The
table governs top-level types only.

## Swift style

Match the surrounding code. Beyond that:

- Early returns over nesting. A `guard` at the top beats an `if` around the body.
- `let` unless mutation is needed. No abbreviations: `index`, not `idx`.
- Prefer a named constant or a small type to a comment that explains a literal.
- One responsibility per type and per function. If a function needs a section comment, split it.
- Views stay declarative and thin. Logic lives in a model, a store or a coordinator.
- Prefer composition to a long `body`. Extract a subview before a `@ViewBuilder` helper.
- A Notes failure the user must know about goes through `NotesDialogs.reportFailure`, as a
  `NotesStore.Issue`. Never a `print`, never a silent `try?` on a path the user cares about.
- Timings go through `Noto/Platform/Signposts.swift`.
- Delete dead code. Do not comment it out.

## Concurrency and lifetime

Swift 6 language mode: a data-race violation is a hard error, by design.

- `@MainActor` is the default. Assume the main actor unless there is a reason.
- Heavy or IO-bound work goes off-main through `Task.detached` over `Sendable` values.
  `NotesStore.detached` is the shape. Do not add a custom actor.
- Cross-actor model types are `Sendable`. Use `@unchecked Sendable` or `nonisolated(unsafe)` only with
  a written reason. There are none today.
- `MainActor.assumeIsolated` is allowed only inside an AppKit callback that AppKit documents as
  main-thread: a local event monitor, a notification observer with no queue, a KVO closure. It traps
  if the assumption is wrong. The uses are in `ShortcutCaptureSession`, `NoteEditorView.Coordinator`
  and `NotesWindowController`.
- Store every long-lived `Task` and cancel it when superseded, in `stop()` or in `deinit`.
- A block observer goes through `NotificationToken`, not a bare `addObserver` plus a removal in
  `deinit`.
- An escaping closure that captures `self` uses `[weak self]`, or `unowned` where the owner cannot
  outlive the captured object. The Notes window controllers hold their coordinator `unowned`.
- `DispatchQueue.main.async` is not a fix for an ordering problem. The one use, in
  `SettingsWindowController.raise`, re-asserts key status after an asynchronous `NSApp.activate`.
- State that must be torn down on its actor uses `isolated deinit`, as `NotesStore` does.

Two gotchas:

- `withObservationTracking`'s `onChange` fires before the write lands, and it fires once. Defer the
  re-read into a `Task` and re-arm the tracking there. `AppCore.observeNotesFolder` is the shape.
- A signpost interval leaks when the wrapped work throws. `Signposts.interval` ends it in a `defer`.

### Observation

- Put `@ObservationIgnored` on a lazily built collaborator, a task and bookkeeping. Without it, a read
  registers a dependency and a view re-renders for no visible reason.
- Never write a type annotation on `@Environment` for an `@Observable` type. The macro resolves the
  keyless overload by type, and an annotation changes which overload is chosen.
- The compiler cannot see a missed injection site. A view that reads `@Environment(NotoSettings.self)`
  from a hierarchy nobody injected into compiles and traps at runtime. Check the injection when you add
  a hosting view. The sites are `AppCore.showSettings()` and the three Notes window controllers.
- `swiftc -parse` does not expand macros. Use `-typecheck` to check an `@Observable` type alone.

## Performance

- Launch stays cheap. Work in `AppCore.start()` or in an initializer is the most expensive place to
  put it. Defer it into a `Task` or do it on first use. Nothing lists the notes folder until the first
  show.
- The editor has a budget on a 100,000-character note; see
  [testing.md](testing.md#performance-measurement).
- Zero leaks and no retain cycles. Ownership is a tree with `AppCore` at the root.
- Measure before you optimise, and before you cache. A new cache needs a number.
- Avoid repeated work and allocation in code that runs per keystroke or per caret move.
- Do not add an abstraction to make something faster later.

## Simplicity

- Prefer the simplest correct solution. Clever code is a cost paid by the next reader.
- Add an abstraction only when it removes more complexity than it adds. A protocol with one
  conformer, a generic with one instantiation and a factory for one type are worse than the concrete
  thing.
- Preserve existing behaviour unless the task is to change it. A behaviour change is a decision.
- Delete rather than deprecate. An app with no API has no audience for a compatibility layer.
- Leave the code cleaner than you found it, in a separate change from the one that noticed.

## Comments

Minimal code, not annotated prose.

1. One line. Never two consecutive comment lines. If it needs two, name a function, a constant or a
   type.
2. Hard cap 100 characters, with the indentation. Longer belongs in `docs/`.
3. Comment the why, the gotcha or the invariant. Never restate the code, never narrate a sequence.
4. Prefer to delete a comment rather than update it.
5. Never comment a change you just made. The diff is not the audience.
6. A `///` doc comment follows the same rules.

Nothing lints this. Get it right the first time.

## Accessibility

Every custom control carries a label and the traits that describe it. The note window is almost all
custom controls: a bar button, a switcher row, a recorder field and a menu row each need it said. Add
it as you write the view.
