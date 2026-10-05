# Architecture

How Noto is wired together. Per-feature internals live in [features/](README.md#features);
conventions for writing new code live in [standards.md](standards.md).

## The layering

Independently of the folder tree, the code sits in four layers, and the `Tests/` harnesses are what
hold them apart.

```
┌─ PURE ─────────────────────────────────────────────────────────────────────┐
│ Foundation (and CoreGraphics) only. No AppKit, no clock, no filesystem.    │
│ ⇒ Compiled verbatim by a harness, so it cannot drift.                      │
│                                                                            │
│ Notes/Model/* — NoteMarkdown, NoteMarkdownParser, NoteInlineScanner,       │
│ NoteMarkdownEditing, NoteEditAction, NoteEditPlan, NoteFormatting,         │
│ NoteRevealPolicy, NoteTitle, NoteSearch, FuzzyMatch, NoteDocument,         │
│ NoteFontSettings,                                                          │
│ NoteSwitcherInteraction, NoteWindowPlacement · HotKeys/Model/HotKeyCommand │
└──────────────────────────────────┬─────────────────────────────────────────┘
                                   │ consumed by
┌─ EFFECT ─────────────────────────▼─────────────────────────────────────────┐
│ All platform I/O.                                                          │
│ NotesRepository · HotKeyCenter · KeyShortcut ·                             │
│ Platform/* (AppPaths, ActivationPolicy, FolderPicker, ASCIIKeyboardLayout) │
└──────────────────────────────────┬─────────────────────────────────────────┘
                                   │ published through
┌─ OBSERVABLE STATE ───────────────▼─────────────────────────────────────────┐
│ @MainActor @Observable: AppCore · NotoSettings · NotesStore ·              │
│ NotesCoordinator · HotKeyManager · ShortcutCaptureSession                  │
└──────────────────────────────────┬─────────────────────────────────────────┘
                                   │ rendered by
┌─ VIEW ───────────────────────────▼─────────────────────────────────────────┐
│ SwiftUI views, the AppKit window controllers and the TextKit 2 editor      │
└────────────────────────────────────────────────────────────────────────────┘
```

In the folder tree those become `Model/`, `Service/` and `UI/` — observable state lives in whichever of
the last two owns it.

- `Model/` — pure. Foundation only, plus CoreGraphics where the data demands it
  (`NoteWindowPlacement`). Everything from the environment is injected. This is the layer that decides
  things: what a keystroke turns into, which lines reveal, how a search ranks, where the window lands.
- `Service/` — effects. `NotesRepository` owns every `FileManager` call and takes its directory and its
  Trash operation as parameters; `NotesStore` drives it off-main; `HotKeyCenter` owns every Carbon
  call. This is the layer that does things.
- `UI/` — views, window controllers, and the feature's coordinator. Declarative, thin, holding no
  policy.

The rule is checkable, which is the point: a file under `Model/` may not import AppKit or SwiftUI,
because the harnesses compile the shipped sources rather than a copy. A harness that stops compiling is
the signal that a decision leaked into the effect layer, or an effect into the decision layer.
`KeyShortcut` is the worked example: it is a value type, but it converts `NSEvent.ModifierFlags`, so it
lives in `HotKeys/Service/`.

Confirmation gates live in the coordinator, never in the repository — `NotesCoordinator.trash` asks
through `NotesDialogs` before `NotesStore.trash` runs, which is why the store stays
harness-compilable while the "are you sure?" step still cannot be bypassed.

`DesignSystem/` and `Platform/` sit outside any feature folder: the shared primitives and system shims
every feature draws on. Neither may depend on a feature.

## Single-owner core

`AppCore.shared` (`Noto/App/AppCore.swift`) is a `@MainActor` singleton owning every long-lived thing in
the app: `NotoSettings`, `NotesStore`, `HotKeyManager`, `ActivationPolicy`, the lazily-built
`NotesCoordinator`, and the `SettingsWindowController`.

`AppDelegate.applicationDidFinishLaunching` calls `AppCore.shared.start()` and nothing else. That is the
one wiring point, and `start()` reads as the app's whole boot sequence: apply the Dock preference,
start the hotkeys, observe the notes folder and the Dock preference, and — only with Show in Dock on —
show the note window.

Feature actions live on that feature's coordinator, and a view must never reach past a coordinator
into a store to mutate it. `AppCore` holds only the wiring: `run(_:)` maps a `HotKeyCommand` to a
`NotesCoordinator` call, `showSettings()` builds the Settings window, `handleReopen()` answers a Dock
click, and `flushNotesForTermination()` is what quit waits on.

- `NotesView`, `NoteSwitcherView`, `NoteHeadingMenuView` and `NoteFormattingBar` receive only
  `NotesCoordinator` through `@Environment`.
- `SettingsView` receives `AppCore`, `NotoSettings` and `HotKeyManager`. It uses `AppCore` as the
  locator for `notesCoordinator` (Choose… and Use Default) and reads `notesStore.notesDirectory` to
  render the path. Reading a store to render it is fine; deciding something with one is what the rule
  forbids.
- The scene-level menus in `NotoApp` and `MenuBarItem.swift` call `AppCore.shared` directly, since a
  scene has no injected environment.

New long-lived state belongs on `AppCore`, wired in `start()`. Do not create a competing singleton:
this is a singleton, not a container.

### Settings

`NotoSettings` (`Noto/Features/Settings/NotoSettings.swift`) holds every preference and mirrors each
to `UserDefaults` in its `didSet`. The keys are that file's private `Key` enum:

| Property | Key | Default |
| --- | --- | --- |
| `rendersMarkdown` | `notesRendersMarkdown` | on |
| `showsFormattingBar` | `notesShowsFormattingBar` | on |
| `notesFolder` | `notesFolder` | nil — the default folder in Application Support |
| `showsInDock` | `showsInDock` | off |
| `keepsOnTop` | `notesKeepsOnTop` | off |
| `fonts` | `notesTextFont`, `notesHeadingFont`, `notesCJKFont`, `notesCodeFont`, `notesFontSize` | nil — see [notes.md](features/notes.md#fonts) |
| `shortcuts` | `hotKeys` | empty — see [hotkeys.md](features/hotkeys.md#persistence) |

Two more values are window state rather than preferences, so `AppCore` reads and writes them itself
and hands them to their owners as closures: `notesActiveFileName` (the active note) and
`notesFormattingBarExpanded`. AppKit autosaves the note window's frame under the name `Notes Window`.

## Entry points and windows

`NotoApp` (`@main`) declares one `MenuBarExtra` scene and its `.commands`; everything else visible is
driven imperatively from AppKit.

- The menu bar item — `MenuBarLabel` (the `text.page` symbol) and `MenuBarMenu`: Show Notes, New Note,
  Search Notes, Settings…, Quit. It stays in both Dock modes, so the app is always reachable.
- The main menu — shaped by `NotoApp`'s `.commands`: Settings… (⌘,) replaces the app-settings group,
  and New Note (⌘N), Show Notes and Search Notes replace the new-item group. It is declared, not
  assigned to `NSApp.mainMenu`, because SwiftUI rebuilds the menu on any scene change.
- The note window — a persistent, titled, non-activating `NotesPanel`, managed by
  `NotesWindowController`. The user owns its size and AppKit autosaves the frame; its TextKit 2 editor
  renders Markdown over the literal source and stays visible on focus loss. Its hosting view sets
  `sizingOptions = []` so SwiftUI never drives the window size.
- The switcher and the heading menu — two more `NotesPanel`s, borderless child windows of the note
  window, managed by `NoteSwitcherWindowController` and `NoteHeadingMenuWindowController`. The switcher
  takes key and dismisses when it resigns it; the heading menu never becomes key, so the editor keeps
  its caret beneath it. See [features/notes.md](features/notes.md).
- The Settings window — a titled `NSWindow` with a preference toolbar, built by
  `Noto/Features/Settings/SettingsWindowController.swift`, hosting `SettingsView`. SwiftUI's `Settings` scene is unreliable for accessory apps, so this is
  deliberate. It is built on first show, torn down on close so its SwiftUI tree deallocates, closes on
  Escape, and never quits the app.
- Dialogs — system `NSAlert`s, presented only through the injected `NotesDialogs`
  (`Noto/Features/Notes/UI/NotesDialogs.swift`).

Noto assigns no `NSApp.appearance`; every surface follows macOS.

### Dock mode

`ActivationPolicy` (`Noto/Platform/ActivationPolicy.swift`) is the only caller of
`NSApp.setActivationPolicy`. The app is `.regular` when `showsInDock` is on or a titled window is open,
and `.accessory` otherwise. `SettingsWindowController` reports its window's open and close to it; the note
panel does not, so with Show in Dock off the Dock icon appears only while Settings is open. Open
windows are tracked by identity rather than a count, so a repeated open or close cannot strand the
icon.

- With Show in Dock on, launch shows the note window, and the app stays in the Dock.
- A click on the Dock icon arrives at `applicationShouldHandleReopen` and calls
  `NotesCoordinator.show()`, which only ever brings the window forward.
- Quit chosen from the Dock icon's menu with Show in Dock off closes the open windows instead of
  quitting: the icon only stands for those windows. `AppDelegate` tells that case apart by the sender
  of the quit Apple Event. ⌘Q and the menu bar's Quit always quit.
- Closing the last window never quits; the agent outlives its windows.

### Termination

`applicationShouldTerminate` answers `.terminateLater`, awaits `AppCore.flushNotesForTermination()`,
then replies. A draft inside the 300 ms autosave debounce therefore reaches disk, and a failed save
cannot veto the quit.

## Observation

Six types are `@MainActor @Observable`: `AppCore`, `NotoSettings`, `NotesStore`, `NotesCoordinator`,
`HotKeyManager` and `ShortcutCaptureSession`. Nothing uses `ObservableObject` or `@Published`, and
views read state through `@Environment` rather than `@EnvironmentObject`.

Three things about this model are easy to get wrong:

- `@ObservationIgnored` on lazily-built collaborators and bookkeeping. Without it, reading one
  registers a dependency. `AppCore.notesCoordinator` is `@ObservationIgnored private(set) lazy` for
  this reason, as are the coordinator's window controllers and tasks.
- Never annotate `@Environment` with a type for an `@Observable` value. The macro resolves the
  keyless overload by type, and an explicit annotation changes which overload is chosen.
- The compiler cannot see a missed injection site. A view reading `@Environment(NotoSettings.self)`
  from a hierarchy nobody injected into compiles fine and traps at runtime, so check the injection when
  adding a hosting view. `AppCore.showSettings()` and the three Notes window controllers are the
  injection sites today.

`AppCore.observeNotesFolder` is the pattern for reacting to a settings change outside a view.
`withObservationTracking`'s `onChange` is a willSet hook — it fires before the write lands and is
one-shot — so the closure defers the re-read into a `Task` and re-arms the tracking there. Both halves
are required; removing the `Task` reads the old value.

## Concurrency

The target builds in Swift 6 language mode with complete strict concurrency, so data-race violations
are hard errors. Almost everything is `@MainActor`; cross-actor model types are `Sendable`. The
IO-bound work — every `NotesRepository` call and the full-text search — is pushed off-main through
`Task.detached` from `NotesStore`. There is no custom actor, deliberately.

House idioms for the sharp edges:

- A block observer held by a view goes through the RAII `NotificationToken`
  (`Noto/Platform/NotificationToken.swift`), so its removal needs no `deinit`; `NoteTextView`'s key
  observers are the example.
- `NotesStore` uses `isolated deinit` to cancel its debounce and search tasks on its actor.
- Raw Carbon pointers are decoded to plain values before crossing into actor code (see
  `hotKeyCarbonEventHandler` in `HotKeyCenter.swift`).
- One operation at a time: `NotesCoordinator.runOperation` cancels an in-flight select, rename or
  Trash when a newer one starts, and a presentation generation retires an older operation's right to
  put what it loaded on screen.

## The tree

The folder layout is the layering above, made navigable.

```
Noto/
  App/              NotoApp (@main), AppDelegate, AppCore — the composition root — and MenuBarItem
  DesignSystem/     Theme (the token source), InterfaceMetrics, BarButton, KeyCapChip, Tooltip,
                    SymbolImage, GlassEffectView, Scrolling/OverflowFade
  Platform/         system shims: AppPaths, AppDisplayName, ActivationPolicy, FolderPicker,
                    FontCatalog, ASCIIKeyboardLayout, Appearance, NotificationToken, Signposts
  Assets.xcassets/  the app icon
  Info.plist        LSUIElement and the bundle keys; excluded from target membership
  Noto.entitlements sandbox off; read by code signing
  Features/
    Notes/
        Model/      pure — the harness inputs
        Service/    NotesRepository, NotesStore
        UI/         NotesCoordinator, NotesDialogs, the panel, the window controllers, the editor,
                    the styler and renderer, the switcher, the formatting bar, the heading menu
    HotKeys/
        Model/      HotKeyCommand
        Service/    KeyShortcut, HotKeyCenter, HotKeyManager, ShortcutCaptureSession
        UI/         ShortcutRecorder, ShortcutRecorderPopover, CalloutShape, CalloutPlacement
    Settings/       NotoSettings, SettingsView
Noto.xcodeproj/     edited directly; Noto/ is a file-system synchronized group
Tests/              the standalone harnesses, one Swift file each
Scripts/            run-tests.sh, lint.sh
```

`Settings/` stays flat: one model and one view do not need the three sub-folders.
