# Testing and verification

How to check that a change holds up. Noto has no XCTest target and no UI tests: the automated half
is a pair of standalone harnesses, and the manual half is the sweep at the bottom of this file.

## Definition of done

The mechanical bar, in one place so it cannot drift. All five pass before a change is finished.

| Check | Command |
| --- | --- |
| The harnesses | `./Scripts/run-tests.sh` |
| Lint | `./Scripts/lint.sh` |
| Pure-layer purity | `grep -rln 'import AppKit\|import SwiftUI\|import Cocoa' Noto/Features/*/Model/` returns nothing |
| A clean build | the Debug `xcodebuild` below, zero warnings |
| Docs still true | any doc your change made wrong, fixed in the same change |

There is no CI: every item is on you, run locally. Each is expanded below; the manual sweep at the end
of this file is the sixth, judged by what you touched.

## The harnesses

```sh
./Scripts/run-tests.sh                      # both
./Scripts/run-tests.sh notes-editor-test    # just one, while iterating
```

`Scripts/run-tests.sh` is the only place the harness set is written down: one `run` line per harness,
naming the shipped sources it compiles. Each harness is one Swift file in `Tests/` with its own
`@main`; the runner compiles it with `swiftc -swift-version 6` beside those sources into
`$TMPDIR/noto-harness/` and runs the binary. A non-zero exit is a failed assertion, a signal is a
crash, and both are reported apart from a harness that did not compile.

Up to four harnesses run at a time; `NOTO_TEST_JOBS` overrides that. Each result is numbered against
the total and shows its run and compile time, a quiet stretch names the harnesses still running, and a
harness that runs longer than `NOTO_TEST_TIMEOUT` seconds (default 300) is killed and reported as timed
out. Status lines arrive in completion order, and a failing harness's compiler diagnostics or assertion
output are replayed together at the bottom, under its name, rather than streamed where they happened.

A `run` line takes optional markers before the harness name. `-O` compiles that harness optimised.
`slow` dispatches it in the first wave. `index` marks a harness that is compiled by hand rather than by
the suite: the runner never queues it (see [Performance measurement](#performance-measurement)).

Each harness compiles the shipped sources it guards rather than a copy of them, which is what makes
the pure-layer boundary real: a harness that stops compiling means AppKit or SwiftUI has leaked into a
`Model/` folder, or an effect has leaked into a decision. That is a more common failure than a broken
assertion, and it is the more important one. Adding a source file to the editor means adding it to the
`notes-editor-test` and `notes-editor-performance` lists; `notes-test` globs `Model/` and `Service/`.

A harness also runs in your own login session against the real system, with no sandbox and no fixture
world, so it must never mutate state the machine shares with the apps you use. `notes-test` roots its
scratch folders under a UUID-suffixed `temporaryDirectory`. `notes-editor-test` drives the
`writeSelection(to:types:)` and `readSelection(from:)` primitives against
`NSPasteboard.withUniqueName()` rather than calling `copy:` or `paste:` on the general pasteboard, and
records a clicked link instead of opening a browser. A new harness must keep doing that.

Never join a compile to its run with `&&` in a `set -e` script. `set -e` is specified to ignore a
failing command in a non-final AND-OR list member, so `swiftc … && /tmp/x` swallows a compile error and
the script sails on. `run-tests.sh` keeps the two steps separate and records both kinds of failure.

### What to run when

If a change touches anything in the right column, the harness on the left is mandatory. The whole
suite takes about ten seconds, so in practice run both.

| Harness | Guards |
| --- | --- |
| `notes-test` | all of `Noto/Features/Notes/Model/` and `Noto/Features/Notes/Service/`: the repository, the store's autosave, selection and relocation, derived titles, search with the real `FuzzyMatch`, the Markdown parser, every edit plan, the formatting reports, the reveal policy, switcher interaction and window placement |
| `notes-editor-test` | the Notes editor, rendered and literal, with real TextKit 2 and AppKit editing objects: styling, reveal, layout fragments, keys, chords, checkboxes, links, undo and the character count. Also compiles `Noto/DesignSystem/Theme.swift` and `InterfaceMetrics.swift`, so a token those lose breaks it |

Nothing automated covers `Noto/Features/HotKeys/`, `Noto/Features/Settings/`, `Noto/App/`,
`Noto/Windows/` or the Notes window chrome. A change there is verified by the manual sweep.

### Purity checks

The layering rule reduces to one grep, and it must return nothing:

```sh
grep -rln 'import AppKit\|import SwiftUI\|import Cocoa' Noto/Features/*/Model/
```

Beyond the imports, the injected-environment half is not mechanically checkable, so it is worth an eye
when touching a pure file:

- `Notes/Model/` still reads no file, clock or `UserDefaults`; `NotesRepository` is handed its
  directory and its Trash operation
- `NotesStore` still takes the saved selection as two closures rather than reading `UserDefaults`
- `NoteWindowPlacement` still takes the visible frame as a parameter and touches no `NSScreen`

## Build check

A clean build is part of the bar; nothing builds the app for you.

```sh
xcodebuild -project Noto.xcodeproj -scheme Noto -configuration Debug \
    -derivedDataPath build/DerivedData build
xcodebuild -project Noto.xcodeproj -scheme Noto -configuration Release \
    -derivedDataPath build/DerivedData build
```

The products are `build/DerivedData/Build/Products/Debug/Noto Dev.app` and
`build/DerivedData/Build/Products/Release/Noto.app`.

- Zero compiler warnings. The `appintentsmetadataprocessor` "Metadata extraction skipped" line is
  build-tool output, not one.
- No `@unchecked Sendable`, `nonisolated(unsafe)` or `assumeIsolated` added without a stated reason.
- The type-checker did not time out. The fix for a timeout is an annotation, not a restructure.

### Lint

```sh
./Scripts/lint.sh
./Scripts/lint.sh --fix    # auto-correct the mechanical subset first
```

SwiftLint owns the rules that catch defects, over `Noto/` and `Tests/`. Errors block; warnings do not.
The comment rules in [standards.md](standards.md#comments) are not among them. There is no formatter,
deliberately — see [development.md](development.md#linting).

## Performance measurement

`Noto/Platform/Signposts.swift` emits one interval, `Notes.search`, on the `app.huanan.noto.perf`
subsystem. Open the `os_signpost` instrument in Instruments and filter to that subsystem; nothing needs
recompiling.

`Tests/notes-editor-performance.swift` installs a 100,000-character note in a real rendered editor and
prints, as JSON, the median over 30 runs of the install with its full restyle, one typed character at
the end, middle and start, and a caret move between distant lines. The budget is 150 ms for the
install, 8 ms per character at the end and middle, and 4 ms at the start.

It is a timing harness, not an assertion one, so it stays out of the suite: `run-tests.sh` registers it
as `run -O index`, which records its source list without queueing it. Compile it by hand, from the repo
root, and keep this command and that list matching:

```sh
N=Noto/Features/Notes
swiftc -O -swift-version 6 Noto/Platform/{Signposts,Appearance,NotificationToken}.swift \
    Noto/DesignSystem/{Theme,InterfaceMetrics}.swift \
    $N/Model/{NoteDocument,NoteMarkdown,NoteMarkdownParser,NoteInlineScanner}.swift \
    $N/Model/{NoteEditPlan,NoteEditAction,NoteFormatting,NoteMarkdownEditing,NoteRevealPolicy}.swift \
    $N/UI/{NoteMarkdownTypography,NoteBlockDecoration,NoteMarkdownStyler,NoteMarkdownRenderer}.swift \
    $N/UI/{NoteCheckboxGeometry,NoteBlockLayoutFragment,NoteLayoutFragmentProvider}.swift \
    $N/UI/{NoteTextViewEditing,NoteTextView,NoteEditorView}.swift \
    Tests/notes-editor-performance.swift -o "$TMPDIR/notes-editor-performance"
"$TMPDIR/notes-editor-performance"
```

Measure before optimising, and measure the same way twice: on a quiet machine, a few fresh processes
per build, compared against the same run on the unchanged tree. No baseline is recorded here, because
one machine's numbers are not another's.

`Signposts.interval` owns an explicit `defer` around the wrapped work on purpose. The obvious spelling
leaks the interval when the work throws, because the end emit is skipped on the throw path and the
instrument then shows an interval that never closes.

## Manual regression sweep

There is no UI test suite, so this is it. Run the section for whatever you touched; run all of it for a
change to `AppCore`, `AppDelegate` or a window controller.

Run against a Debug build (`Noto Dev.app`). It shares `app.huanan.noto` with a Release build, so the
sweep works on the real preferences and the real notes folder: use throwaway notes, or choose a
scratch Notes Folder in Settings first.

### Notes

Commands and the collection:

- Show Notes opens the last active note; from a global shortcut or the menu bar item a second press
  hides the window, from the main menu or the Dock icon it only brings it forward
- Create Note makes one unique Untitled file, including as the first action in an empty folder
- Command-P and the Browse button focus search, arrows move selection, Return opens, and Command-N
  creates
- Empty switcher search reads the complete recent list; title and body searches rank correctly and a
  superseded query never publishes
- An Untitled note titles itself from its first line as it is typed, in the title bar and — after the
  autosave — in the browse list; naming it replaces that, and the derived title shows no Markdown
  markers
- Inline rename updates the Markdown filename without changing source, and starts from that filename
  even where the row shows a derived title; collisions receive a suffix
- Delete confirms through an alert that opens in front, moves the file to Trash, and selecting another
  note never loses an unsaved edit
- Deleting every note closes the browse list and leaves one clean empty state with no character count;
  Command-N from there creates and selects one note
- A `.md` file dropped into the folder from Finder appears the next time the window is shown

Rendering:

- A note using every construct renders in Dark and Light: sized headings, emphasis, strikethrough,
  inline code, coloured links, bullets, numbers, checkboxes with space between tasks, lists nested at
  two and four spaces, quote bars, a code band with its language label, and a rule
- The caret's line shows raw Markdown in the tertiary colour and re-renders when the caret leaves; a
  multi-line selection reveals every selected line, and Select All shows the whole source
- Dragging a selection across rendered lines does not jump under the pointer; the lines reveal on
  mouse-up
- Clicking another app renders the whole note; clicking back reveals the caret line again
- Inside a code block both fences show and Markdown inside it stays literal
- A table shows as its literal source in the code font, with no styling inside it; adding the `| --- |`
  row under existing rows turns them all into the table at once
- Bullets, numbers and checkboxes are a neutral gray, bullet, numbered and task items are evenly spaced,
  and revealing a bullet or numbered line leaves its text where it was
- A narrow window wraps list items under their text, not under the marker

Editing:

- A checkbox click toggles without moving the caret, autosaves, and Command-Z restores it; the file on
  disk shows `[x]`
- A link click opens the browser, a click at the label's edge places the caret, a `file:` link does
  nothing, and a link on the caret's line is editable text
- Return continues and leaves lists and quotes, Tab and Shift-Tab nest, ordered lists renumber, `[] `
  becomes a task, and every formatting shortcut works and undoes in one step
- ⌥⌘C and ⇧⌘B toggle a code block and a quote
- Pasting a URL over selected text makes a link; pasting anything else is plain text
- Copy from a rendered line pastes raw Markdown into another app
- With Render Markdown off, the note is fully literal (markers visible, links inert, task syntax
  plain) and Return, Tab, Delete, and formatting-looking shortcuts keep native plain-text behavior;
  flipping it back re-renders without dirtying the note or touching undo
- Edit one note, switch to a shorter note, then Undo and Redo: the new note remains intact and the app
  does not terminate
- With rendering on and off, ⌘Z undoes and ⇧⌘Z redoes typing, deletion and paste while another app's
  menu bar is visible; both update the count and autosave the restored source. Editing after undo
  discards redo; reopening a note after switching away starts with no history
- Marked-text input, emoji, combining marks, Copy, Cut, Paste, Select All, Undo, and Redo preserve
  exact source; ⌘F finds occurrences in the active note with rendering on and off, and Escape closes
  the find bar before hiding the window
- An empty note shows `Start writing…`; ⌘F moves it below the find bar without overlap, and closing Find
  restores its position. The count is right after typing, pasting and undoing

The formatting bar:

- With Render Markdown and Show Formatting Bar on, the band under a note holds the character count on
  the left and the round formatting button on the right; with either setting off, the centred count
  footer is back and nothing else moved
- The bar starts collapsed, ⌥⌘T and the round button both expand and collapse it, the buttons slide out
  from behind that button, and the state survives switching notes, hiding the window and a relaunch
- Every bar button applies its formatting, undoes in one step with ⌘Z, and autosaves; clicking keeps the
  caret where it was and the caret's line stays revealed
- Buttons light for the selection: inside bold, on a list, quote, heading or code line; clicking a lit
  button removes that formatting and the button goes dark
- Hovering a button shows its name and shortcut above it, fully visible and not clipped by the capsule;
  the heading button's tooltip does not show while its menu is open
- The heading menu opens above the capsule, aligned to its left edge, shows the current level checked,
  and applies a level on click; it closes on Escape, on a click anywhere in the note window (including
  the heading button itself, which must not reopen it), on typing, on ⌘P, and when another app is clicked
- At the smallest window size all eleven controls show and the count is hidden, the note's text keeps
  its inset in both states, the heading menu still opens in full above the capsule, and widening the
  window brings the count back
- With VoiceOver, the bar reads as "Formatting" with each button named, lit ones as selected, the round
  button announcing Expanded or Collapsed, and the heading button its level; menu rows read their titles
  and the current one as selected

The window:

- Traffic lights sit top-left, the title is centred on the window, and the capsule is top-right, all
  on one line; the yellow and green lights are disabled
- Each capsule button shows a hover capsule and a native tooltip, and fires its action
- Dragging the title bar moves the window and dragging an edge resizes it, never below the minimum;
  both survive relaunch. A double-click on the free title bar moves it to the top-right of the screen
- Clicking another app leaves the panel visible; Escape, Command-W, and the red light hide it
- Hiding restores the previous external app, or the Settings window when that was in front; if another
  app was brought forward meanwhile, focus stays there
- Open Notes Folder opens Finder with the active Markdown file selected, or the folder with no note
- The browse list fades only at its bottom edge and rests opaque once it reaches the end
- Command-Q quits; quitting inside the debounce window saves the last edit
- Over a light desktop, the 26-point corner is clean, the shadow follows it, and no dark edge shows
  around the glass controls

### Hotkeys

- Each of the three recorders starts empty on a clean install and reads "Record Hotkey"
- Clicking a recorder shows the callout above it with the `⌥ A` example; holding modifiers shows them
  live with "Add a key"; a full combo saves, closes the callout and shows as keycaps
- Show Notes toggles the window from any app; Create Note and Search Notes each do what their menu
  item does
- The old binding does not fire while any recorder is listening
- A combo another Noto command holds is rejected: the callout names its owner in orange and keeps
  listening
- A bare letter is ignored; a bare function key and a Globe combo both record
- Escape cancels, Delete clears, the hover ✕ clears, a click on another recorder moves the recording
  there, and switching to another app cancels
- A recorder near the top of the Settings list opens its callout below the field instead, with the
  caret still aimed at it
- Every binding survives quit and relaunch
- A combo another app already owns records but does not fire, and Console shows the
  "could not register hotkey" line

### Settings

- Settings… opens from the menu bar item and with ⌘,; a second request raises the same window; Escape
  and the red light close it; it reopens centred
- Render Markdown and Show Formatting Bar take effect in the open note immediately; Show Formatting Bar
  is disabled while Render Markdown is off
- Choose… opens in front, and picking a folder switches the note window to that folder's notes with
  nothing moved; the row shows the new path, `~`-abbreviated, and Use Default appears
- Changing the folder with an unsaved edit saves that edit into the old folder first
- Use Default returns to the Application Support folder and the button disappears
- Every setting survives quit and relaunch

### Menu bar and Dock

- The menu bar item shows in both modes; each of its five items works, and its Quit quits
- With Show in Dock off: no Dock icon at launch and no window; the icon appears while Settings is open
  and goes when it closes; the note window alone never brings it
- With Show in Dock off and Settings open, Quit from the Dock icon's menu closes Settings and Noto
  keeps running in the menu bar
- Turning Show in Dock on shows the icon at once and it stays after Settings closes; after turning it
  off the icon goes when Settings closes
- With Show in Dock on: launch shows the note window; clicking the Dock icon brings it back after a
  hide and never hides a visible one; Quit from the Dock icon's menu quits
- Closing every window never quits the app

### Clean install

The realistic storage failure is a store that crashes on an absent file rather than starting empty.
Debug and Release share one bundle id, so this state is the real one: quit Noto and move it aside
rather than deleting it, then put it back afterwards.

```sh
mv "$HOME/Library/Application Support/app.huanan.noto" "$HOME/Library/Application Support/app.huanan.noto.aside"
defaults export app.huanan.noto "$TMPDIR/noto-defaults.plist" && defaults delete app.huanan.noto
```

Restore with the reverse `mv` and `defaults import app.huanan.noto "$TMPDIR/noto-defaults.plist"`.

- Launches with the folder absent — no crash, no hang, no window, a menu bar item
- The `Notes` folder is not created until Show, Create, or Search is first used, then accepts its first
  edit; with no notes the window shows "No Notes" and Create Note works
- Every setting shows its intended default: Render Markdown on, Show Formatting Bar on, the default
  folder, Show in Dock off, no shortcuts
- Quit and relaunch: everything created above persisted
