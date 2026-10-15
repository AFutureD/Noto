# Testing and verification

How to check that a change holds up. Noto has no XCTest target and no UI tests. The automated half is
three standalone harnesses. The manual half is the sweep at the end of this file.

## Definition of done

Every check in the table passes before a change is finished. No workflow runs them; run them locally.

| Check | Command |
| --- | --- |
| The harnesses | `./Scripts/run-tests.sh` |
| Lint | `./Scripts/lint.sh` |
| Model purity | `grep -rln 'import AppKit\|import SwiftUI\|import Cocoa' Noto/Features/*/Model/` returns nothing |
| A clean build | the Debug `xcodebuild` below, with zero warnings |
| Docs still true | each doc your change made wrong, fixed in the same change |
| Docs in the house style | each doc sentence you added or changed obeys [Documentation language](README.md#documentation-language) |
| Changelog | a change the user can notice has a line under `Unreleased` in `CHANGELOG.md` |
| Commit message | the form in [`AGENTS.md`](../AGENTS.md#0x00-重要性): a human reviewed the change, and the message says so |

Then run the part of the [manual sweep](#manual-regression-sweep) that covers what you touched.

## The harnesses

```sh
./Scripts/run-tests.sh                      # all
./Scripts/run-tests.sh notes-editor-test    # one, while you iterate
```

`Scripts/run-tests.sh` is the only list of harnesses: one `run` line per harness, with the shipped
sources it compiles. Each harness is one Swift file in `Tests/` with its own `@main`. The runner
compiles it with `swiftc -swift-version 6` beside those sources into `$TMPDIR/noto-harness/` and runs
the binary. A non-zero exit is a failed assertion, a signal is a crash, and a harness that did not
compile is reported apart from both.

Before the first harness, the runner compiles MDTextKit's modules from `MDTEXTKIT_DIR` (default
`../MDTextKit`) into `$TMPDIR/noto-harness/modules/` as static libraries, and links every harness
against them. It repeats that only when a package source changed. So a harness sees the package the
app sees, and a package change breaks a harness before it breaks the app.

| Harness | Compiles | Covers |
| --- | --- | --- |
| `notes-test` | all of `Notes/Model/` and `Notes/Service/`, `Signposts`, `SyncLog`, `NotesLog` and `NotificationToken`, with the real `FuzzyMatch` and PolarMark | the repository, autosave, external reloads, draft preservation, conflict copies, the copy into iCloud, selection, relocation, derived titles, search, image paths and imports, the emoji catalog, the highlight and accent colours, switcher interaction, window placement |
| `notes-editor-test` | the editor host, its theme, `Theme.swift` and `InterfaceMetrics.swift`, with the real MDTextKit modules and AppKit | the Markdown round trip, styling, keys, chords, headings, links, checkboxes, tables, undo, the character count, the fonts, the colours, the text height, the emoji query |
| `settings-sync-test` | `NotoSettings`, `CloudSettingsMirror`, `CloudKeyValueStore` and the value types of the synced preferences | the settings mirror: what is sent, what is taken, when iCloud wins, no echo, values from another build |

Nothing automated covers `HotKeys/`, `Updates/`, `App/`, `SettingsView`, the Notes window chrome,
`CloudNotesLocation` or `NotesWatcher`. The manual sweep verifies a change there.

Rules for the harnesses:

- A harness compiles the shipped sources, never a copy. That is what makes the `Model/` boundary
  real. When you add a source file to the editor, add it to the `notes-editor-test` and
  `notes-editor-performance` lists. When `NotoSettings` or the mirror needs a new file, add it to the
  `settings-sync-test` list. `notes-test` globs `Model/` and `Service/`.
- A harness runs in your login session against the real system. It must never change state the
  machine shares with your apps. `notes-test` roots its scratch folders under a UUID-suffixed
  `temporaryDirectory`. `notes-editor-test` uses `NSPasteboard.withUniqueName()` instead of the general
  pasteboard, and records a clicked link instead of opening a browser. `settings-sync-test` uses a
  `UserDefaults` suite with a UUID name, a fake key-value store and a private `NotificationCenter`, so
  it never touches iCloud.
- Never join a compile to its run with `&&` in a `set -e` script. `set -e` ignores a failure inside an
  AND-OR list, so the script would continue past a compile error. The runner keeps the two steps
  apart.

Runner options: up to four harnesses run at a time (`NOTO_TEST_JOBS`); a harness that runs longer than
`NOTO_TEST_TIMEOUT` seconds (default 300) is killed. A `run` line takes markers before the name: `-O`
compiles optimised, `slow` dispatches in the first wave, and `index` records the source list without
a run (see [Performance measurement](#performance-measurement)).

## Model purity

The layering rule reduces to one grep, which must return nothing:

```sh
grep -rln 'import AppKit\|import SwiftUI\|import Cocoa' Noto/Features/*/Model/
```

The injected-environment half is not mechanical. When you touch a pure file, check that:

- `Notes/Model/` reads no file, clock or `UserDefaults`.
- `NotesRepository` is handed its directory, its Trash operation and its clock.
- `CloudSettingsMirror` is handed its key-value store and its `NotificationCenter`, and `NotoSettings`
  its `UserDefaults`.
- `NotesStore` takes the saved selection as two closures.
- `NoteWindowPlacement` takes the visible frame as a parameter and touches no `NSScreen`.

## Build and lint

```sh
xcodebuild -project Noto.xcodeproj -scheme Noto -configuration Debug \
    -derivedDataPath build/DerivedData -allowProvisioningUpdates build
./Scripts/lint.sh
```

- Zero compiler warnings. The `appintentsmetadataprocessor` "Metadata extraction skipped" line is
  tool output, not a warning.
- No `@unchecked Sendable`, `nonisolated(unsafe)` or `assumeIsolated` added without a stated reason.
- The type-checker did not time out. The fix for a timeout is an annotation, not a restructure.
- Lint errors block; warnings do not. See [development.md](development.md#lint).

## Performance measurement

`Noto/Platform/Signposts.swift` emits one interval, `Notes.search`, on the `app.huanan.noto.perf`
subsystem. Filter the `os_signpost` instrument to that subsystem.

`Tests/notes-editor-performance.swift` installs a 100,000-character note in a rendered editor and
prints, as JSON, the median over 30 runs of: the install with its restyle, one typed character at the
end, middle and start, the window fit's height read after each of those, and a caret move between
distant lines. `NOTO_PERF_RUNS` lowers the run count.

| Measure | Budget | 2026-10-13 |
| --- | --- | --- |
| Install | 150 ms | 800 ms |
| A character at the end, middle, start | 8, 8, 4 ms | 12, 15, 16 ms |
| The fit's read after the install, after a character | 10, 1 ms | 3, 0.01 ms |

The install styles and lays out the whole note. The keystroke cost that remains is the styling of the
edited block and TextKit's attribute fixing. Both are tasks in the MDTextKit repository.

It is a timing harness, so it stays out of the suite: `run-tests.sh` lists it as `run -O index`.
Compile it by hand from the repository root, and keep this command equal to that list:

```sh
N=Noto/Features/Notes
M="$TMPDIR/noto-harness/modules"    # built by run-tests.sh
C=../MDTextKit/Sources/MDTextStorageCore
NOTO_LINK="-I $M -I $C/include -L $M -lMDTextKitUI -lMDTextKit -lMDTextStorageCore -lSFThemeKit -lTextBundle -lPolarMark"
swiftc -O -swift-version 6 $NOTO_LINK \
    Noto/Platform/{Signposts,Appearance,NotificationToken}.swift \
    Noto/DesignSystem/{Theme,InterfaceMetrics}.swift \
    $N/Model/{NoteDocument,NoteFontSettings,NoteHighlightColor,NoteAccentColor,NoteEditAction,NoteFormatting}.swift \
    $N/UI/{NoteEditorTheme,NoteTextView,NoteEditorView}.swift \
    Tests/notes-editor-performance.swift -o "$TMPDIR/notes-editor-performance"
"$TMPDIR/notes-editor-performance"
```

Measure on a quiet machine, a few fresh processes per build, against the same run on the unchanged
tree. One machine's numbers are not another's.

## Manual regression sweep

Run the section for what you touched. Run all of it for a change to `AppCore`, `AppDelegate` or a
window controller.

Run it against a Debug build. It shares `app.huanan.noto` with a Release build, so the sweep works on
the real preferences and the real notes. Use throwaway notes, or choose a scratch Notes Folder first.
With iCloud Sync on, the sweep also works on the notes and settings of each device of the iCloud
account. Use an iCloud account with no real notes for the iCloud sync section.

### Notes: commands and the collection

- Show Notes opens the last active note. From a global shortcut or the menu bar item a second press
  hides the window. From the main menu or the Dock icon it only brings the window forward.
- Create Note makes one unique Untitled file, also as the first action in an empty folder.
- ⌘P and the Browse button focus search; arrows move the selection, Return opens, ⌘N creates.
- An empty switcher search lists every note by recency. Title and body searches rank correctly, and a
  superseded query never publishes.
- An Untitled note titles itself from its first line as you type, in the title bar, and after the
  autosave in the browse list. A name replaces that. The derived title shows no Markdown markers.
- Inline rename changes the folder name and not the source. It starts from the folder name, also where the
  row shows a derived title. A collision receives a suffix.
- Delete confirms through an alert that opens in front and moves the note's folder to Trash. Selecting another
  note never loses an unsaved edit.
- Deleting every note closes the browse list and shows the empty state with no character count. ⌘N
  from there creates and selects one note.
- A folder with a `text.md` inside, put in the notes directory from Finder, appears the next time the
  window shows. A loose `.md` file does not.

### Notes: rendering

- A note with every construct renders in Dark and Light: sized headings, emphasis, strikethrough,
  underline, a highlight behind `==text==`, inline code, links with their icon, bullets, numbers,
  checkboxes, nested lists, quote bars, a callout box, a code band, a rule, an image and a table grid.
- The caret's construct shows its markers in the tertiary colour and hides them when the caret leaves.
  A heading's `#` attachment shows while the caret is on its line, at the centre of the left margin.
- A click before a heading marker puts the caret after the marker. ← from the start of the heading
  text moves the caret to the end of the line above.
- A click on another app hides every marker. A click back reveals the caret's construct.
- Inside a code block both fences show, and Markdown inside it stays literal.
- A table shows as a grid. A click on a cell edits it in place, Tab moves to the next cell, and the
  `⋮` menu adds a row. The file on disk holds pipe-table Markdown.
- ⌘-click on a heading marker folds its section to a pill. A click on the pill unfolds it.
- Bullets, numbers and checkboxes are a neutral gray.
- A narrow window wraps list items under their text, not under the marker.
- New lines, wrapped text and a paste grow the window and do not change its width. A delete shrinks
  it back to the 180pt floor. The top edge holds until the bottom reaches the screen's bottom; then the
  window moves up. It stops at 860pt or the screen's usable height and scrolls. A switch to a shorter
  note shrinks it. Repeat with Find and the formatting bar open, and on a second display.
- Typing, Return and Delete in a list grow or shrink the window by whole rows. They never shrink it
  for one frame, scroll the first line away or flash the scrollbar.
- A system appearance switch repaints the open note: text, markers, bands, bars, checkboxes and the
  table follow it.

### Notes: editing

- A checkbox click toggles without a caret move, autosaves, and ⌘Z restores it. The file shows `[x]`.
- A link icon click opens the browser. A `file:` link does nothing. Link text on the caret's line is
  editable text.
- Return continues and leaves lists and quotes. Tab and Shift-Tab nest. Ordered lists renumber. Every
  formatting shortcut works and undoes in one step.
- ⌥⌘C and ⇧⌘B toggle a code block and a quote. ⌘K wraps a selection as a link and unwraps a link.
- A URL pasted over selected text makes a link. Pasted rich text becomes Markdown.
- Copy from a rendered line pastes raw Markdown into another app.
- A list item dragged by its text moves as a whole line.
- Edit one note, switch to a shorter note, then Undo and Redo: the new note stays intact and the app
  does not terminate.
- ⌘Z and ⇧⌘Z undo and redo a typing run, a deletion and a paste while another app's menu bar is
  visible. Both update the count and autosave. An edit after undo discards redo. A note reopened
  after a switch starts with no history.
- Marked-text input, emoji, combining marks, Copy, Cut, Paste, Select All, Undo and Redo preserve the
  exact source. ⌘F finds in the active note, and Escape closes the find bar before it hides the window.
- An empty note shows `Start writing…`. ⌘F moves it below the find bar. The count is right after
  typing, a paste and an undo.
- Paste an image, and drop an image file from Finder. Each one shows in the note, and the file lands
  in the note's `assets` folder with a free name. `text.md` holds `![](assets/<name>)`. Rename the
  note: the images still show.
- Type `:smi` after a space. The emoji list opens under the `:`. The arrows move the selection,
  Return inserts the emoji, and ⌘Z restores `:smi`. Escape closes the list and keeps the window. In a
  code block, `:smi` opens no list.

### Notes: the formatting bar

- With Show Formatting Bar on, the band under a note holds the count on the left and the round
  formatting button on the right. With it off, the centred count footer is back.
- The bar starts collapsed. ⌥⌘T and the round button expand and collapse it, the buttons slide out
  from behind that button, and the state survives a note switch, a hide and a relaunch.
- Each bar button applies its formatting, undoes in one step and autosaves. A click keeps the caret
  where it was, and the caret's line stays revealed.
- A button lights for the selection: inside bold, on a list, quote, heading or code line. A click on a
  lit button removes that formatting.
- Hover shows the name and shortcut above the button, not clipped by the capsule. A menu button's
  tooltip does not show while its menu is open.
- The Heading menu opens above the capsule, aligned to its left edge, with the current level checked.
  It closes on Escape, on a click anywhere in the note window (also on the Heading button, which must
  not reopen it), on typing, on ⌘P, and when another app is clicked.
- The List menu lists Bullet, Numbered and Task List. The More menu lists Underline, Strikethrough,
  Inline Code and Code Block, and it stays inside the window. A click on the List button while the
  More menu is open swaps the menus.
- At the smallest window size all nine controls show and the count is hidden. Each menu opens in full
  above the capsule. A wider window brings the count back.
- With VoiceOver, the bar reads as "Formatting", each button is named, a lit one is selected, the round
  button announces Expanded or Collapsed, the Heading button its level, and a menu row reads its title.

### Notes: the window

- The traffic lights sit top-left, the title is centred, and the capsule is top-right, on one line. The
  yellow and green lights are disabled.
- Each capsule button shows a hover capsule and a native tooltip, and fires its action.
- A drag on the title bar moves the window. A drag on an edge resizes it, never below the minimum.
  Both survive a relaunch. A dragged height holds until the next keystroke. A double-click on the free
  title bar moves the window to the top-right of the screen.
- A click on another app leaves the panel visible. Escape, ⌘W and the red light hide it.
- A hide restores the previous external app, or the Settings window when that was in front. If another
  app came forward meanwhile, focus stays there.
- Open Notes Folder opens Finder with the active note's folder selected, or the notes directory when
  there is no note.
  Finder comes to the front also with the Settings window open or Show in Dock on.
- The browse list fades only at its bottom edge and rests opaque at the end.
- ⌘Q quits. A quit inside the debounce window saves the last edit.
- Over a light desktop, the 26-point corner is clean, the shadow follows it, and no dark edge shows
  around the glass controls.

### Hotkeys

- Each of the four recorders starts empty on a clean install and reads "Record Hotkey".
- A click on a recorder shows the callout above it with the `⌥ A` example. Held modifiers show live
  with "Add a key". A full combo saves, closes the callout and shows as keycaps.
- Show Notes toggles the window from any app. Create Note and Search Notes do what their menu items do.
- The old binding does not fire while a recorder listens.
- A combo another Noto command holds is rejected: the callout names its owner in orange and keeps
  listening.
- A bare letter is ignored. A bare function key and a Globe combo both record.
- Escape cancels, Delete clears, the hover ✕ clears, a click on another recorder moves the recording
  there, and a switch to another app cancels.
- A recorder near the top of the Settings list opens its callout below the field, with the caret
  still aimed at it.
- Every binding survives a quit and relaunch.
- A combo another app holds records but does not fire, and Console shows the "could not register
  hotkey" line.

### Settings

- Settings… opens from the menu bar item and with ⌘,. A second request raises the same window. Escape
  and the red light close it. It reopens centred.
- The toolbar shows General, Editor, Shortcuts and Sync. For each pane the title changes, the height
  changes, and the top edge does not move.
- Keep on Top is off on a clean install. With it off, another app's window can cover the note window.
  With it on, the note window stays above other windows and shows on each Space.
- Each Keep on Top control changes the state at once: the Settings row, the menu bar item, ⌥⌘P and the
  global shortcut. The check mark in the menu bar menu agrees.
- Each font setting applies to the open note at once: Text font, Heading font, CJK font, Code font and
  Text size.
- With Heading Font set, headings use that family and body text does not change.
- With Text Font `Menlo` and CJK Font `Songti SC`, Latin text is Menlo and Han text is Songti.
- With Text Font `Monaco`, bold text is heavier and italic text stays upright: Monaco has no italic
  face.
- Each Aa button opens a list with a search field. Each name shows in its own font, the list scrolls to
  the chosen family, and a click applies it and closes the list.
- Restore Editor Defaults restores the fonts, the text size, both colours and the formatting bar. It
  is disabled when each of them is at its default.
- A colour picked in the Highlight well applies at once, in both appearances. Use Default appears,
  restores the yellow and disappears.
- A colour picked in the Accent well colours an underline, a link and the selection at once. Use
  Default restores the macOS accent colour.
- Show Formatting Bar takes effect in the open note at once.
- Check Now opens Sparkle's update window, and Check for Updates… in the menu bar item is disabled
  while it is open. Check for updates automatically survives a quit and relaunch.
- Choose… opens in front. A picked folder switches the note window to that folder's notes with
  nothing moved. The row shows the new path with `~`, and Use Default appears.
- A folder change with an unsaved edit saves that edit into the old folder first.
- Use Default returns to the Application Support folder, and the button disappears.
- Every setting survives a quit and relaunch.

### iCloud sync

Use two Macs with the same iCloud account, A and B. Watch `Logger.sync` on each:
`log stream --level info --predicate 'subsystem == "app.huanan.noto" AND category == "sync"'`.

- With iCloud Drive off, iCloud Sync on A shows "iCloud Drive Is Off", and the switch stays off.
- With notes in the local folder, iCloud Sync on A asks "Copy N Notes to iCloud?". Copy puts them
  in iCloud Drive › Noto with their modification order. The local folder does not change. Don't Copy
  turns sync on with no copy.
- With no notes in the local folder, sync turns on with no question.
- Turn sync off and on again with Copy: a note with the same title and text is not copied again. A
  note with the same title and other text takes the next name, as `Plan 2`.
- While sync is on, the Notes folder buttons are disabled and the caption reads "iCloud Drive › Noto".
  Sync off shows the local folder and its notes again, and the iCloud notes stay in iCloud Drive.
- The switch turned on in A turns on in B, and B shows the iCloud notes with no question. Off in A
  turns it off in B.
- A note created, edited, renamed or moved to Trash on A shows on B, also while B's window is open.
  A clean active note on B reloads; a note that B is typing in keeps the draft.
- Type in the same note on A and B with the network off on one Mac, then turn it on. Both texts stay:
  one in the note, the other in `<title> (Conflict <date> <time>)`.
- Edit the active note in another app through Open Notes Folder while Noto holds a draft, in a local
  folder too. After the autosave, the draft is in the note and the other edit is a conflict copy.
- Delete the active note's folder in Finder while Noto holds a draft. The autosave creates it again.
- Text size, fonts, the highlight and accent colours, Show formatting bar and each shortcut set on A
  apply on B at once. A shortcut from A fires on B. Keep on Top, Show in Dock and the Notes folder do
  not sync.
- Sync on in Settings while iCloud Drive is off on B: B keeps its local notes, and the iCloud caption
  says that iCloud Drive is off.
- A note that iCloud has not downloaded yet shows its folder name in the switcher, then its first
  line when it arrives.

### Menu bar and Dock

- The menu bar item shows in both modes. Each item works, and its Quit quits.
- With Show in Dock off: no Dock icon at launch and no window. The icon appears while Settings is open
  and goes when it closes. The note window alone never brings it.
- With Show in Dock off and Settings open, Quit from the Dock icon's menu closes Settings, and Noto
  keeps running in the menu bar.
- Show in Dock turned on shows the icon at once, and it stays after Settings closes. Turned off, the
  icon goes when Settings closes.
- With Show in Dock on: launch shows the note window. A Dock icon click brings it back after a hide and
  never hides a visible one. Quit from the Dock icon's menu quits.
- Closing every window never quits the app.

### Clean install

The realistic storage failure is a store that crashes on an absent file instead of a start with no
notes. Debug and Release share one bundle id, so this state is the real one. Quit Noto, move the state
aside, and put it back afterwards:

```sh
mv "$HOME/Library/Application Support/app.huanan.noto" "$HOME/Library/Application Support/app.huanan.noto.aside"
defaults export app.huanan.noto "$TMPDIR/noto-defaults.plist" && defaults delete app.huanan.noto
```

Restore with the reverse `mv` and `defaults import app.huanan.noto "$TMPDIR/noto-defaults.plist"`.

- Noto launches with the folder absent: no crash, no hang, no window, a menu bar item.
- The `Notes` folder is created at the first Show, Create or Search, and accepts its first edit. With
  no notes the window shows "No Notes" and Create Note works.
- Every setting shows its default: Show Formatting Bar on, the default folder, Show in Dock off, no
  shortcuts, iCloud Sync off.
- The moved state is local only. If iCloud Sync is on for the iCloud account, the switch comes
  back on from iCloud with the synced settings. For a true first run, turn sync off first, or sign
  out of iCloud.
- After a quit and relaunch, everything created above persists.
