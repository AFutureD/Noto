# Engineering standards

How code in Noto is written. This is guidance — it describes what the codebase already looks
like so that new code reads like it was there all along, and a good reason to depart from it is a good
reason. What is actually checked is the bar in
[testing.md](testing.md#definition-of-done); the rules that may not be broken at all are the
Non-negotiables in [`AGENTS.md`](../AGENTS.md).

When this document and the code disagree, the code is probably right and this file is stale. Fix it.

## Posture

The rule — latest-only, prefer modern APIs, no compatibility layers, never add backwards compatibility
unasked — is stated in [`AGENTS.md`](../AGENTS.md#posture-latest-only-always). This section is the
reasoning and the concrete shape it takes.

The reason it is worth being strict about: a compatibility floor is not a one-time cost. Every shim
outlives the platform that needed it, gets copied by the next feature that sees it, and turns a
one-line call into a layer nobody dares delete. Noto has no external API, no plugin surface and one
supported OS, so it has nothing to be compatible with.

In practice that means Observation and never `ObservableObject` or `@Published`; `async`/`await` and
never a completion handler or a `DispatchQueue` hop; structured concurrency and never detached
bookkeeping you have to remember to cancel. When one of these gains a successor, the migration is the
change — not a wrapper preserving the old spelling.

Carbon has two deliberate capability-gap uses. `HotKeyCenter` uses `RegisterEventHotKey` because
nothing modern can register a system-wide chord. `ASCIIKeyboardLayout` uses HIToolbox's TIS APIs and
`UCKeyTranslate` because they remain the public way to turn a key code into the glyph the current
layout prints. Neither use is inertia, and raw C pointers never cross an asynchronous actor boundary.

## Architecture and feature organization

Full detail in [architecture.md](architecture.md); the rules a new feature has to satisfy:

- One folder per feature under `Noto/Features/<Name>/`, holding everything that feature owns.
- A larger feature splits into `Model/` (pure), `Service/` (effects) and `UI/` (views, window
  controllers and the feature's coordinator). A small one stays flat, as `Settings/` does. Split when
  the flat folder stops being scannable, not on principle.
- `Model/` may not import AppKit or SwiftUI. Everything from the environment is injected. This is the
  enforced rule.
- New long-lived state belongs on `AppCore`, wired in `start()`. Do not create a second singleton.
- Shared visual primitives go in `DesignSystem/`, system shims in `Platform/`. Neither may depend on a
  feature.
- A new file under `Noto/` needs no project edit; see [development.md](development.md#the-project).

Feature work reaches the app through a coordinator, called by `AppCore` and by views via
`@Environment`. Confirmation gates live in the coordinator, never in the store or repository.

## Naming

A type's suffix says what it is. Semantic correctness comes first: pick the suffix that names the
responsibility honestly, and add a row here when none of them does. Do not rename a well-named type to
fit the table.

| Suffix | Means | Here |
| --- | --- | --- |
| `Store` | Owns state and publishes it | `NotesStore` |
| `Repository` | File semantics a `Store` does not imply — validation, unique-name claiming | `NotesRepository` |
| `Coordinator` | A feature's action surface, called by `AppCore` and views | `NotesCoordinator` |
| `Controller` | Owns one AppKit window or surface | `NotesWindowController`, `AppWindowController` |
| `Manager` | Owns a subsystem's lifecycle and its policy; started from `AppCore.start()` | `HotKeyManager` |
| `Center` | The Carbon registration layer specifically | `HotKeyCenter` |
| `Session` | Transient state for one in-progress interaction | `ShortcutCaptureSession` |
| `Policy` | A pure decision — no state, no effects | `NoteRevealPolicy` |
| `Settings` | Every preference, mirrored to `UserDefaults` | `NotoSettings` |

`Manager` is the one worth thinking twice about. It means lifecycle plus policy, which is a lot for one
type, so there is only one. Another is fine if it genuinely owns both halves — but check first whether
`Store` or `Coordinator` describes it better, because usually one of them does.

`ActivationPolicy` is named for `NSApplication.ActivationPolicy`, which it applies, not for this
table. SwiftUI-layer names (`View`, `Row`, `Bar`, `Button`) are a separate vocabulary and are not
governed by it either.

### Files

- One top-level type per file, named for it. A `View` file is named for its view; a namespace `enum` for
  the namespace. A file that groups a few small siblings is named for what they share:
  `MenuBarItem.swift` (label and menu), `NoteDocument.swift` (the note value types).
- Private nested helpers are free to be named for their job — the table governs top-level types only.

## Swift style

Match the surrounding code. Beyond that:

- Early returns over nesting. A `guard` at the top beats an `if` wrapping the body.
- `let` unless mutation is needed. No abbreviations in names — `index`, not `idx`.
- Prefer a named constant or a small type to a comment explaining a literal.
- Keep types and functions to a single responsibility. If a function needs a section comment, it wants to
  be two functions.
- Views stay declarative and thin. Business logic lives in a model, a store or a coordinator — a `body`
  that decides things is the most common way a codebase like this gets worse.
- Prefer composition over a long `body`. Extract a subview before extracting a `@ViewBuilder` helper.
- A Notes failure the user must know about goes through `NotesDialogs.reportFailure`, published as a
  `NotesStore.Issue`. Never a `print`, never a silent `try?` on a path the user cares about.
- Timings go through `Noto/Platform/Signposts.swift`.
- Delete dead code rather than commenting it out or leaving a compatibility path behind it.

## Concurrency and lifetime

Swift 6 language mode: data-race violations are hard errors, and that is the design, not an obstacle.

- `@MainActor` is the default. Almost everything has UI coupling or identity; assume main actor
  unless there is a reason.
- Heavy or IO-bound work goes off-main explicitly, through `Task.detached` over `Sendable` values —
  `NotesStore.detached` is the shape. Keep that boundary; do not introduce a custom actor.
- Cross-actor model types are `Sendable`. Reach for `@unchecked Sendable` or `nonisolated(unsafe)` only
  with a written reason, and never for convenience. There are none today.
- No new `MainActor.assumeIsolated`. It traps at runtime if the assumption is ever wrong. The existing
  uses are in `ShortcutCaptureSession`, inside AppKit event-monitor and notification handlers that
  predate actor annotations.
- Any long-lived `Task` is stored and cancelled when superseded, in `stop()`, or in `deinit`. An
  un-owned `Task` is a leak with extra steps.
- A block observer held by a view goes through the RAII `NotificationToken`
  (`Noto/Platform/NotificationToken.swift`), not a bare `addObserver` plus removal in `deinit`.
- Every escaping closure capturing `self` uses `[weak self]`, or `unowned` where the closure's owner
  cannot outlive the captured object (as the Notes window controllers hold their coordinator).
- `DispatchQueue.main.async` is not a fix for an ordering problem. If order matters, make it explicit.
  The one use, in `AppWindowController.raise`, re-asserts key status after an asynchronous
  `NSApp.activate`.
- `NotesStore` uses `isolated deinit` — the idiom to copy for state that must be torn down on its
  actor.

Two gotchas worth knowing before they cost an afternoon:

- `withObservationTracking`'s `onChange` is a willSet hook. It fires before the write lands, so a
  re-read must be deferred into a `Task` — which is also where the tracking is re-armed, since the
  closure is one-shot. `AppCore.observeNotesFolder` is the shape to copy.
- A signpost interval leaks if the wrapped work throws. The end emit is skipped on the throw path
  unless it is in a `defer`. `Signposts.interval` already does this.

### Observation

Nothing uses `ObservableObject` or `@Published`. Adding anything new to this model:

- `@ObservationIgnored` on lazily-built collaborators, tasks and bookkeeping. Without it, reading one
  registers a dependency and a view re-renders for no visible reason.
- Never write a type annotation on `@Environment` for an `@Observable` type — the macro resolves the
  keyless overload by type, and an annotation changes which overload is chosen.
- The compiler is blind to a missed injection site. A view reading `@Environment(NotoSettings.self)`
  from a hierarchy nobody injected into compiles and traps at runtime, so check the injection when adding
  a new hosting view.
- `swiftc -parse` does not expand macros. Use `-typecheck` when checking an `@Observable` type standalone.

## Performance and memory

- Launch stays cheap. Work added to `AppCore.start()` or to an initialiser is the most expensive place
  to put it; defer it into a `Task` or do it on first use. Nothing lists the notes folder until the
  first show.
- The editor has a budget on a 100,000-character note; it and the way to measure it are in
  [testing.md](testing.md#performance-measurement).
- Zero leaks and no retain cycles. Ownership is a tree with `AppCore` at the root.
- Measure before optimising, and measure before caching. A new cache needs a number, not an intuition.
- Avoid repeated work and needless allocation in code that runs per keystroke or per caret move.
- Prefer a cheaper data structure to a cache over an expensive one.
- Do not add an abstraction to make something faster later.

## Simplicity and maintainability

- Prefer the simplest correct solution. Clever is a cost paid by whoever reads it next.
- Do not add an abstraction until it removes more complexity than it adds. A protocol with one
  conformer, a generic with one instantiation and a factory for one type are all worse than the concrete
  thing.
- Preserve existing behaviour unless the task is to change it. Behaviour changes are decisions, and
  decisions get discussed.
- Delete rather than deprecate. There is no audience for a compatibility layer in an app with no API.
- Leave the codebase cleaner than you found it — but as a separate change from the one that noticed.

## Comments

Minimal code, not annotated prose.

1. One line. Never two consecutive comment lines. If it needs two, it needs a named function, a named
   constant, or a type.
2. Hard cap 100 characters, including indentation. Longer belongs in a doc under `docs/`.
3. Comment the why, the gotcha, or the invariant. Never restate the code, never narrate a sequence,
   never argue a decision at length in-line.
4. Prefer deleting a comment to updating it.
5. Never add a comment explaining a change you just made. The diff is not the audience.
6. A `///` doc comment on a type or method follows the same rules. It is not a licence to stack
   lines.

None of this is linted, by choice. A rule that fires after the comment is written buys a second edit;
these are cheap to get right on the first pass instead.

## Accessibility

Every custom control carries a label and the traits that describe it. The note window is almost
entirely custom controls, so nothing comes for free — a bar button, a switcher row, a recorder field
and a heading-menu row all need saying explicitly. Adding it as the view is written costs a line;
retrofitting it costs a rewrite.

## What is actually checked

Everything above is guidance. The mechanical bar — the harnesses, the purity grep, lint, a clean
build — is one list, in [testing.md](testing.md#definition-of-done), so that it cannot drift by being
written down twice. Anything not on it is a judgement call: make it, and say why if it is not obvious.
