# Architecture

How Noto is wired. Each feature's internals are in [features/](README.md#features). The rules for new
code are in [standards.md](standards.md).

## The layers

The code sits in four layers. The `Tests/` harnesses hold the first two apart.

```
┌─ PURE ─────────────────────────────────────────────────────────────────────┐
│ Foundation (and CoreGraphics) only. No AppKit, no clock, no filesystem.    │
│ A harness compiles these files as they ship, so they cannot drift.        │
│                                                                            │
│ Notes/Model/*: NoteEditAction, NoteFormatting, NoteTitle (over PolarMark), │
│ NoteSearch, FuzzyMatch, NoteDocument, NoteFontSettings, NoteHighlightColor,│
│ NoteAccentColor, NoteSwitcherInteraction, NoteWindowPlacement              │
│ HotKeys/Model/HotKeyCommand                                                │
└──────────────────────────────────┬─────────────────────────────────────────┘
                                   │ consumed by
┌─ EFFECT ─────────────────────────▼─────────────────────────────────────────┐
│ All platform I/O.                                                          │
│ NotesRepository · NotesWatcher · CloudSettingsMirror · HotKeyCenter ·      │
│ KeyShortcut · Platform/*                                                   │
└──────────────────────────────────┬─────────────────────────────────────────┘
                                   │ published through
┌─ OBSERVABLE STATE ───────────────▼─────────────────────────────────────────┐
│ @MainActor @Observable: AppCore · NotoSettings · NotesStore ·              │
│ NotesCoordinator · CloudNotesLocation · HotKeyManager ·                    │
│ ShortcutCaptureSession · UpdateCoordinator · SettingsWindowController      │
└──────────────────────────────────┬─────────────────────────────────────────┘
                                   │ rendered by
┌─ VIEW ───────────────────────────▼─────────────────────────────────────────┐
│ SwiftUI views, the AppKit window controllers and the MDTextKit editor host │
└────────────────────────────────────────────────────────────────────────────┘
```

In the folder tree these are `Model/`, `Service/` and `UI/`. Observable state lives in the folder of
its owner.

- `Model/` decides. It is pure: Foundation only, plus CoreGraphics where the data needs it
  (`NoteWindowPlacement`). Every environment fact is a parameter: the clock, the filesystem, the
  directory.
- `Service/` does. `NotesRepository` owns every `FileManager` call on the notes and takes its
  directory, its Trash operation and its clock as parameters. `NotesStore` drives it off the main
  actor. `NotesWatcher` and `CloudNotesLocation` own the iCloud calls for the notes. `HotKeyCenter`
  owns every Carbon call.
- `UI/` shows. Views, window controllers and the feature's coordinator. It holds no policy.

The rule is mechanical. A file under `Model/` may not import AppKit or SwiftUI, because the harnesses
compile the shipped files. A harness that stops compiling tells you that a decision leaked into the
effect layer, or an effect into the decision layer. `KeyShortcut` is the worked example: it is a value
type, but it converts `NSEvent.ModifierFlags`, so it lives in `HotKeys/Service/`.

A confirmation gate lives in the coordinator, never in the repository. `NotesCoordinator.trash` asks
through `NotesDialogs` before `NotesStore.trash` runs. So the store compiles in a harness, and the
question cannot be bypassed.

`DesignSystem/` and `Platform/` sit outside the features. They hold the shared primitives and the
system shims. Neither may depend on a feature.

## One owner

`AppCore.shared` (`Noto/App/AppCore.swift`) is a `@MainActor` singleton. It owns every long-lived
object:

| Property | Type | Does |
| --- | --- | --- |
| `settings` | `NotoSettings` | every preference |
| `notesStore` | `NotesStore` | the notes and the draft |
| `hotKeys` | `HotKeyManager` | the global shortcuts |
| `settingsMirror` | `CloudSettingsMirror` | copies the synced preferences to and from iCloud |
| `cloudNotes` | `CloudNotesLocation` | the iCloud folder for the notes, or why there is none |
| `notesWatcher` | `NotesWatcher` | changes to the iCloud notes from other devices |
| `updates` | `UpdateCoordinator` | Sparkle |
| `activationPolicy` | `ActivationPolicy` | the Dock icon |
| `notesCoordinator` | `NotesCoordinator`, built lazily | the Notes actions and windows |
| `settingsWindow` | `SettingsWindowController`, built lazily | the Settings window |

`AppDelegate.applicationDidFinishLaunching` calls `AppCore.shared.start()` and nothing else. `start()`
is the boot sequence:

1. Apply the Dock preference.
2. Start the hotkeys.
3. Start the settings mirror. A remote change to the shortcuts registers the hotkeys again.
4. Start the updater.
5. Start the iCloud location, and connect the watcher's report to `NotesStore`.
6. Observe the notes location (the Notes Folder setting, the iCloud switch and the iCloud state), and
   apply it once.
7. Observe the Dock preference.
8. With Show in Dock on, show the note window.

[sync.md](features/sync.md) describes steps 3, 5 and 6.

A feature's actions live on its coordinator. A view never reaches past a coordinator into a store to
mutate it. `AppCore` holds only the wiring: `run(_:)` maps a `HotKeyCommand` to a `NotesCoordinator`
call, `showSettings()` builds the Settings window, `handleReopen()` answers a Dock click, and
`flushNotesForTermination()` is what quit waits on.

- `NotesView`, `NoteSwitcherView`, `NoteBarMenuView` and `NoteFormattingBar` receive only
  `NotesCoordinator`, through `@Environment`.
- `SettingsView` receives `AppCore`, `NotoSettings` and `HotKeyManager`. It uses `AppCore` to reach
  `notesCoordinator` (iCloud Sync, Choose… and Use Default) and `updates` (the Updates row). It
  reads `notesStore.notesDirectory` and `cloudNotes.state` for the captions. A view may read a store to render it. It may not
  decide with one.
- The scene-level menus in `NotoApp` and `MenuBarItem.swift` call `AppCore.shared` directly. A scene
  has no injected environment.

New long-lived state goes on `AppCore`, wired in `start()`. Never add a second singleton.

### Settings

`NotoSettings` (`Noto/Features/Settings/NotoSettings.swift`) holds every preference. Each property
writes `UserDefaults` in its `didSet`. The keys are the file's private `Key` enum. `UserDefaults` is
the source of truth.

| Property | Key | Default |
| --- | --- | --- |
| `showsFormattingBar` | `notesShowsFormattingBar` | on |
| `notesFolder` | `notesFolder` | nil: the default folder in Application Support |
| `showsInDock` | `showsInDock` | off |
| `keepsOnTop` | `notesKeepsOnTop` | off |
| `fonts` | `notesTextFont`, `notesHeadingFont`, `notesCJKFont`, `notesCodeFont`, `notesFontSize` | nil: see [notes.md](features/notes.md#fonts) |
| `highlightColor` | `notesHighlightColor` | nil: see [notes.md](features/notes.md#highlight-colour) |
| `accentColor` | `notesAccentColor` | nil: see [notes.md](features/notes.md#accent-colour) |
| `shortcuts` | `hotKeys` | empty: see [hotkeys.md](features/hotkeys.md#persistence) |
| `syncsWithICloud` | `iCloudSync` | off: see [sync.md](features/sync.md#the-switch) |

`NotoSettings.Synced` lists the preferences that sync to iCloud: `syncsWithICloud`,
`showsFormattingBar`, `fonts`, `highlightColor`, `accentColor` and `shortcuts`. Each of these calls
`onSyncedChange` after it writes, and `CloudSettingsMirror` sends it. `notesFolder`, `showsInDock` and
`keepsOnTop` never sync. A new preference is not synced until you add it to `Synced`. See
[sync.md](features/sync.md#the-settings-mirror).

Two values are not preferences:

- Check for updates automatically is Sparkle's own `SUEnableAutomaticChecks` default.
  `UpdateCoordinator.checksAutomatically` reads and writes it. See
  [updates.md](features/updates.md).
- The active note (`notesActiveFileName`) and the formatting bar's state (`notesFormattingBarExpanded`)
  are window state. `AppCore` reads and writes them and hands them to their owners as closures.
  AppKit autosaves the note window's frame under the name `Notes Window`.

## Windows

`NotoApp` (`@main`) declares one `MenuBarExtra` scene and its `.commands`. AppKit drives everything
else.

- The menu bar item: `MenuBarLabel` (the `text.page` symbol) and `MenuBarMenu` with Show Notes, New
  Note, Search Notes, Keep on Top, Settings…, Check for Updates… and Quit. It shows in both Dock
  modes, so the app is always reachable.
- The main menu: `NotoApp`'s `.commands` put Check for Updates… after About, Settings… (⌘,) in the
  app-settings group, and New Note (⌘N), Show Notes and Search Notes in the new-item group. The menu
  is declared, not assigned to `NSApp.mainMenu`, because SwiftUI rebuilds it on each scene change.
- The note window: a persistent, titled, non-activating `NotesPanel`, managed by
  `NotesWindowController`. Its height fits the note up to 860pt, and AppKit autosaves the frame. Its
  hosting view sets `sizingOptions = []`, so SwiftUI never drives the window size.
- The switcher and the bar menu: two more `NotesPanel`s, borderless child windows of the note window,
  managed by `NoteSwitcherWindowController` and `NoteBarMenuWindowController`. The switcher takes key
  and dismisses when it resigns key. The bar menu never becomes key, so the editor keeps its caret.
  See [notes.md](features/notes.md).
- The Settings window: a titled `NSWindow` with a preference toolbar, built by
  `SettingsWindowController` and hosting `SettingsView`. SwiftUI's `Settings` scene is unreliable for
  an accessory app. The window is built on first show and torn down on close, so its SwiftUI tree
  deallocates. Escape closes it. It never quits the app.
- Dialogs: system `NSAlert`s, presented only through the injected `NotesDialogs`.

Noto sets no `NSApp.appearance`. Every surface follows macOS.

### Dock mode

`ActivationPolicy` (`Noto/Platform/ActivationPolicy.swift`) is the only caller of
`NSApp.setActivationPolicy`. The app is `.regular` when `showsInDock` is on or a titled window is open,
and `.accessory` otherwise. `SettingsWindowController` reports its window's open and close. The note
panel does not. So with Show in Dock off, the Dock icon shows only while Settings is open. Open windows
are tracked by identity, not by a count, so a repeated open or close cannot strand the icon.

- With Show in Dock on, launch shows the note window and the app stays in the Dock.
- A Dock icon click arrives at `applicationShouldHandleReopen` and calls `NotesCoordinator.show()`,
  which only brings the window forward.
- With Show in Dock off, Quit in the Dock icon's menu closes the open windows and does not quit: the
  icon stands for those windows only. `AppDelegate` tells that case apart by the sender of the quit
  Apple Event. ⌘Q and the menu bar's Quit always quit.
- Closing the last window never quits. The agent outlives its windows.

### Termination

`applicationShouldTerminate` answers `.terminateLater`, awaits `AppCore.flushNotesForTermination()`,
then replies. A draft inside the 300 ms autosave debounce reaches disk. A failed save cannot veto the
quit.

## Observation

Nine types are `@MainActor @Observable`: `AppCore`, `NotoSettings`, `NotesStore`, `NotesCoordinator`,
`CloudNotesLocation`, `HotKeyManager`, `ShortcutCaptureSession`, `UpdateCoordinator` and
`SettingsWindowController`. Nothing
uses `ObservableObject` or `@Published`. Views read state through `@Environment`.

`AppCore.observeNotesLocation` is the pattern for a reaction to a settings change outside a view.
`withObservationTracking`'s `onChange` fires before the write lands, and it fires once. So the closure
defers the re-read into a `Task` and re-arms the tracking there. Both halves are required.

The rules for new observable code are in [standards.md](standards.md#observation).

## Concurrency

The target builds in Swift 6 language mode with complete strict concurrency. Almost everything is
`@MainActor`. Cross-actor model types are `Sendable`. `NotesStore` pushes every `NotesRepository` call
and the full-text search off the main actor with `Task.detached`. `CloudNotesLocation.refresh` does
the same for the iCloud container lookup, which can block. There is no custom actor.

The idioms in use:

- `NotificationToken` (`Noto/Platform/NotificationToken.swift`) is an RAII handle for a block
  observer. `NoteEditorView.Coordinator`, `NotesWindowController`, `CloudSettingsMirror`,
  `CloudNotesLocation` and `NotesWatcher` hold their observers this way.
- `NotesStore` uses `isolated deinit` to cancel its debounce and search tasks on its actor.
- `HotKeyCenter` decodes the raw Carbon event to a plain `EventHotKeyID` before it enters actor code.
- `NotesCoordinator.runOperation` cancels an in-flight select, rename or Trash when a newer one
  starts. A presentation generation retires an older operation's right to show what it loaded.

The rules are in [standards.md](standards.md#concurrency-and-lifetime).

## The tree

```
Noto/
  App/              NotoApp (@main), AppDelegate, AppCore (the composition root), MenuBarItem
  DesignSystem/     Theme (the token source), InterfaceMetrics, BarButton, KeyCapChip, Tooltip,
                    SymbolImage, GlassEffectView, Scrolling/OverflowFade
  Platform/         system shims: AppPaths, AppDisplayName, AppVersion, ActivationPolicy, Appearance,
                    ASCIIKeyboardLayout, CloudKeyValueStore, FileViewer, FolderPicker, FontCatalog,
                    NotificationToken, Signposts, SyncLog (Logger.sync)
  AppIcon.icon      the app icon, an Icon Composer document
  Assets.xcassets/  empty; actool compiles the icon into it
  Info.plist        LSUIElement, the Sparkle keys, the iCloud container and the bundle keys; a build
                    input
  Noto.entitlements sandbox off, iCloud Documents and key-value storage; read by code signing
  Features/
    Notes/
      Model/        pure: the harness inputs
      Service/      NotesRepository, NotesStore, CloudNotesLocation, NotesWatcher
      UI/           NotesCoordinator, NotesDialogs, NotesPanel, the window controllers, the editor
                    host and its theme, the switcher, the formatting bar, the bar menus
    HotKeys/
      Model/        HotKeyCommand
      Service/      KeyShortcut, HotKeyCenter, HotKeyManager, ShortcutCaptureSession
      UI/           ShortcutRecorder, ShortcutRecorderPopover, CalloutShape, CalloutPlacement
    Settings/       NotoSettings, CloudSettingsMirror, SettingsPane, SettingsView,
                    SettingsWindowController
    Updates/        UpdateCoordinator, the Sparkle updater's owner
Noto.xcodeproj/     edited directly; Noto/ is a file-system synchronized group
Tests/              the standalone harnesses, one Swift file each
Scripts/            run-tests.sh, lint.sh
Resource/           Brand/ (the icon source and renders), Screenshots/ (the README images)
.github/            the release dispatcher; the build runs in AFutureD/noto-releases
```

`Settings/` and `Updates/` stay flat. A small feature does not need the three sub-folders.
