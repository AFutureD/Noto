# iCloud sync

iCloud Sync keeps the notes and the Editor and Shortcuts settings the same on each Mac that uses
the same iCloud account. It is off by default. Settings > Sync > iCloud Sync turns it on and
off.

The parts:

- `NotoSettings.syncsWithICloud` and `NotoSettings.Synced` (`Features/Settings/`): the switch, and the
  list of the preferences that sync.
- `CloudSettingsMirror` (`Features/Settings/`): copies the synced preferences to and from iCloud
  key-value storage.
- `CloudNotesLocation` (`Features/Notes/Service/`): finds the iCloud folder for the notes.
- `NotesWatcher` (`Features/Notes/Service/`): watches that folder for changes from other devices.
- `NotesRepository.save(id:source:base:)` and `resolveConflicts(id:)`: keep a conflict copy, so no
  text is lost.
- `NotesCoordinator.setSyncsWithICloud`: the action of the Settings switch.
- `CloudKeyValueStore` and `SyncLog` (`Platform/`): the key-value store surface, and `Logger.sync`.

`AppCore` owns the mirror, the location and the watcher, and wires them in `start()`. See
[architecture.md](../architecture.md#one-owner).

## Invariants

- `UserDefaults` is the source of truth for each preference. iCloud key-value storage holds a copy.
  The app reads a preference from `UserDefaults` only.
- The switch always syncs. The other synced preferences sync only while the switch is on:
  `showsFormattingBar`, `fonts`, `highlightColor`, `accentColor` and `shortcuts`. The General
  preferences (`notesFolder`, `showsInDock`, `keepsOnTop`) and the window state never sync.
- When sync turns on, iCloud wins where it has a value. A preference that only this Mac has set goes
  to iCloud.
- A remote value goes into `UserDefaults` first. Then the reader that runs at launch parses it. There
  is no second parser.
- The mirror compares before each write, to iCloud and to the settings. An equal value writes
  nothing, so a change does not come back as an echo.
- Only the Mac that turns sync on in its own Settings asks about its notes. When another Mac turns the
  switch on, this Mac only moves to the iCloud folder.
- Sync off moves back to the folder on this Mac. Nothing is copied and nothing is deleted.
- When a save replaces text that the store did not read, it keeps that text as a conflict copy. This
  applies in each folder, also a local one.
- A version that iCloud cannot merge becomes a conflict copy before Noto marks it resolved.

## The switch

`NotoSettings.syncsWithICloud` has the key `iCloudSync`. It is off when absent.

The Settings checkbox calls `NotesCoordinator.setSyncsWithICloud`. It does not write the setting
directly.

To turn sync on:

1. `CloudNotesLocation.refresh` asks for the iCloud container. If there is none, the alert "iCloud
   Drive Is Off" tells the user to sign in to iCloud and turn on iCloud Drive. The switch stays off.
2. If the folder on this Mac has notes, the alert "Copy N Notes to iCloud?" asks with Copy and Don't
   Copy. Neither answer cancels: both turn sync on.
3. The setting turns on, and `NotesStore.relocate` moves the store to the iCloud folder. The move
   comes first, so nothing writes into the folder that the copy reads.
4. With Copy, `NotesStore.copyNotes(from:)` copies the notes in.

The copy rules:

- A note with the same title and the same text is already in iCloud. The copy skips it. The title
  match ignores case and accents.
- Each other collision takes the next free name, as `Plan 2`.
- A copy keeps the modification date of its `text.md`, so it keeps its position in the list.
- The folder on this Mac does not change.

To turn sync off, the setting turns off and the store moves back to the folder on this Mac. That is
the default folder, or the Notes Folder setting. The notes in iCloud stay there. A turn-off cancels a
turn-on that is still in progress.

When another Mac flips the switch, the mirror writes the setting here. `AppCore` moves the store.
There is no alert and no copy.

## The settings mirror

`CloudSettingsMirror` connects `NotoSettings` to `NSUbiquitousKeyValueStore.default`, through the
`CloudKeyValueStore` protocol.

Each `NotoSettings.Synced` case is one iCloud key, `settings.<case>`. Its value is a dictionary of
the `UserDefaults` keys of that preference.

| Case | iCloud key | Dictionary keys |
| --- | --- | --- |
| `syncsWithICloud` | `settings.syncsWithICloud` | `iCloudSync` |
| `showsFormattingBar` | `settings.showsFormattingBar` | `notesShowsFormattingBar` |
| `fonts` | `settings.fonts` | `notesTextFont`, `notesHeadingFont`, `notesCJKFont`, `notesCodeFont`, `notesFontSize` |
| `highlightColor` | `settings.highlightColor` | `notesHighlightColor` |
| `accentColor` | `settings.accentColor` | `notesAccentColor` |
| `shortcuts` | `settings.shortcuts` | `hotKeys` |

- A dictionary holds only the keys that the user set. An empty dictionary is the default.
  `NotoSettings.storedValue(of:)` makes it.
- `NotoSettings.restore(_:from:)` writes a remote dictionary into `UserDefaults`, then parses it as a
  launch does. It removes each key that the dictionary does not have, so that member goes back to its
  default. A value that does not parse also gives the default.
- The mirror reads only the keys of the preference from an iCloud value. A value from another build
  cannot write a different key.
- `shortcuts` is JSON with sorted keys, so equal shortcuts are equal bytes on each Mac.

What the mirror does:

| Event | Result |
| --- | --- |
| `start()` | Observes the store, then calls `synchronize()` and catches up |
| Catch-up | Takes the switch from iCloud when iCloud has one. If the switch is on, reconciles |
| Reconcile | For each other preference: takes the iCloud value if there is one, else sends a value that this Mac has set |
| A local change (`NotoSettings.onSyncedChange`) | Sends the switch always, then reconciles if it is on. Sends another preference only while the switch is on |
| A server change | A changed switch causes a catch-up. Else, while the switch is on, takes each changed preference |
| The first download, or an account change | Catches up |
| A quota violation | Logs an error. The settings do not sync |

After it takes a value from iCloud, the mirror calls `onRemoteChange`. `AppCore` uses it to register
the hotkeys again when the shortcuts changed.

## The notes location

`AppCore.applyNotesLocation` selects the folder that `NotesStore` uses. It runs at launch, and again
when `notesFolder`, `syncsWithICloud` or `CloudNotesLocation.state` changes.

| Switch | `CloudNotesLocation.state` | Folder | Watcher |
| --- | --- | --- | --- |
| off | any | the Notes Folder setting, or the default folder | stopped |
| on | `unknown` | no change; `refresh()` asks, and the answer applies again | no change |
| on | `unavailable` | the Notes Folder setting, or the default folder | stopped |
| on | `available` | the `Documents` folder of the iCloud container | started |

`NotesStore.relocate` saves the open draft into the old folder before it lists the new one. See
[notes.md](notes.md#storage).

`CloudNotesLocation`:

- The container is `iCloud.app.huanan.noto`. `Info.plist` makes its `Documents` folder public with the
  name `Noto`, so Finder shows it as iCloud Drive › Noto.
- `refresh()` looks up the container off the main actor, because the lookup can block. It creates
  `Documents` if it is absent.
- It asks again when the iCloud account changes (`NSUbiquityIdentityDidChange`).

In Settings, while sync is on:

- The Notes folder buttons are disabled. The setting keeps its value and applies again when sync is
  off.
- The Notes folder caption shows "iCloud Drive › Noto" while the store uses the iCloud folder.
- When iCloud is not available, the notes stay in the folder on this Mac, and the iCloud caption
  says so.

## The watcher

`NotesWatcher` runs only while the store uses the iCloud folder. It is an `NSMetadataQuery` on the
ubiquitous documents scope, for files named `text.md`. It uses only a `text.md` directly in a note
folder that is directly in the notes folder.

At each gather and each update:

1. It starts the download of each `text.md` that is not current.
2. It records each note that has unresolved conflicts.
3. After 500 ms with no further update, it reports. With no conflicts, `AppCore` calls
   `NotesStore.reload()`. With conflicts, `AppCore` calls `NotesStore.resolveConflicts(_:)`, which
   reloads after it.

The reload follows the rules in [notes.md](notes.md#autosave): a clean active note reloads, and a
dirty draft stays. The next save of that draft finds the remote text and keeps it as a conflict copy.

Before the first show, a report does not reload: the first show lists the folder and sees the
change. A report with conflicts still resolves them, and lists only when the store has loaded.

A file that iCloud has not downloaded has no content on this Mac. A read of it waits for the
download, so the repository does not read it:

- `list()` does not read the first line of an unnamed note that is not downloaded. The note shows its
  folder name until it arrives.
- Search matches such a note by its title only.

## Conflicts

A conflict copy is an ordinary note named `<title> (Conflict yyyy-MM-dd HH.mm)`, in the local time of
this Mac. If that name is in use, the copy takes the next free name. Noto does not merge text and
shows no alert. The user compares the two notes and deletes one.

There are two sources of conflict copies.

The save. `NotesStore` keeps the text that it last read or wrote for the active note. That is the
base. `NotesRepository.save(id:source:base:)` reads the file and writes the draft in one file
coordination, so no other writer can write between the two. Then:

- If the file held the base, or held the draft, there is no copy.
- If the file held other text, that text becomes a conflict copy first. Then the draft goes into the
  file. If the copy fails, the save fails and the file keeps the other text. The editor stays on the
  active note.
- If the note folder is gone, because another device deleted or renamed it, the save creates it
  again with the draft.

This applies in each folder. Another app that writes a note through Open Notes Folder is a writer too.

The iCloud versions. When two devices change one file before they sync, iCloud keeps one version and
marks the others as unresolved `NSFileVersion`s. `NotesRepository.resolveConflicts(id:)` keeps each
unresolved version as a conflict copy, marks them resolved and removes the other versions. The
current version stays in `text.md`.

## Logging

`Logger.sync` logs to the subsystem `app.huanan.noto`, category `sync`. It records the switch, the
iCloud folder, the settings that the mirror sends and takes, the copy count, each conflict copy, and
each download error. Titles and paths are private.

```sh
log stream --level info --predicate 'subsystem == "app.huanan.noto" AND category == "sync"'
```

## Testing notes

- `settings-sync-test` runs `NotoSettings` and `CloudSettingsMirror` against a fake key-value store,
  a private `NotificationCenter` and a `UserDefaults` suite with a UUID name. It does not use iCloud.
- `notes-test` covers the save conflict copy, two notes that share one folder, a recreated folder,
  and the copy rules.
- No harness covers `CloudNotesLocation`, `NotesWatcher`, `NSFileVersion` conflicts or the Settings
  switch. The [manual sweep](../testing.md#icloud-sync) covers them.
- Debug and Release share the bundle id. So they share `UserDefaults`, the iCloud container and the
  key-value store. A Debug run with sync on changes the real notes and settings on each device of the
  account. Use an iCloud account that has no real notes for sync tests.
- A Debug build needs a development provisioning profile for the iCloud entitlements. See
  [development.md](../development.md#build-and-run).
