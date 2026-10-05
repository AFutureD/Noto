# Notes

Notes is an unlimited local collection of plain Markdown files in one persistent editor window, which
renders the Markdown in place. One window edits one active note at a time; a title-bar button opens the
searchable switcher, and the menu bar item, the main menu, global shortcuts and the Dock icon can show,
search, or extend the collection. Notes is the app: there is no switch that turns it off.

## Invariants

- One regular, non-hidden `.md` file is one note. Its filename without the extension is its title;
  the source contains no frontmatter, embedded ID, or title field, and there is no database or sidecar.
- A note the user has not named shows its first line instead. Only the names `create` claims yield
  it, it is presentation and nothing else, and naming the note replaces it.
- The storage is the source. The string in `NSTextView`, `NotesStore`, search, and the file are
  identical; rendering is attributes and drawing over that string, never a second string or an offset
  map.
- The caret's line is raw. Every line under the selection shows its Markdown; an unfocused editor
  reveals nothing.
- Styling never reaches undo. Attribute passes bypass `shouldChangeText`; every edit a Markdown
  gesture makes goes through `NoteTextView.performEdit`.
- Render Markdown off is the literal editor, with native Return, Tab and shortcuts and no parsing.
- The formatting bar is another way to press a shortcut. Each button sends its chord's
  `NoteEditAction` through `NoteTextView.format`, so it has the chord's gate, undo step and autosave,
  and a button is lit exactly when its toggle would remove that formatting.
- Only the active note can be dirty. Switching, creating, renaming, and deleting first flush it, so
  collection navigation cannot abandon an in-memory draft.
- Noto is the only writer. There is no watcher and no revision check: a save replaces the file
  with what is in the editor. Every show re-lists the folder, so a note added outside appears, but the
  active draft is never re-read from disk.
- Search is on demand and unindexed. An empty switcher query reads metadata plus the head of every
  unnamed note; a nonempty query reads bodies sequentially off-main and retains no collection-sized
  source cache.
- The collection may be empty. Deleting the last note is allowed and creates no replacement; the
  window shows its empty state and Create Note still works from there.
- The user owns the window size. AppKit resizes and autosaves the frame; the controller only
  clamps it to the floor below which the title bar's own parts collide.
- Notes code asks through `NotesDialogs`, never builds an alert itself. The coordinator names the
  question; `NotesDialogs.alerts` is the one place an `NSAlert` is constructed.
- The editor gets each font from `NoteMarkdownTypography`. Only `NoteMarkdownStyler.apply` changes the
  fonts, because it also builds the attributes again.

## Storage and identity

The default directory is:

```text
~/Library/Application Support/<bundle-id>/Notes/
```

Notes Folder in Settings (`NotoSettings.notesFolder`, UserDefaults key `notesFolder`) uses another
folder, absolute or under `~/`, as it is: nothing moves out of the old one. `AppCore` observes the
setting and calls `NotesStore.relocate`, which saves the open draft where it was before it lists the
new folder; a draft the old folder cannot take yet holds the move until its save lands.
`AppPaths.contentFolder` resolves the stored path and `AppPaths.contentFolderSetting` stores a chosen
one `~`-relative where it can be, or nil when it is the default. Nothing is migrated from Tinycast.

`NoteID` is the relative filename, so a rename returns a new identity. Immediate regular `.md` children
are sorted by modification date, then localized title. Subdirectories, hidden files, and symbolic links
are ignored.

Create uses `Untitled.md`, then `Untitled 2.md`, and so on, and rename claims a free name by the same
rule. Collisions with another note are case- and diacritic-insensitive, so `plán` beside `Plan`
becomes `plán 2.md`. A note never collides with itself: only an exact filename match is a no-op, which
is what lets a rename change nothing but the case or the accents. The active filename is local UI state
under the UserDefaults key `notesActiveFileName`, read and written by closures `AppCore` hands the
store.

## Derived titles

A note still carrying a name `create` claimed — `Untitled`, `Untitled 2`, … — shows the first line of
its source that carries visible text. `NoteTitle` owns that rule: blank, rule and fence lines are
skipped, block and inline Markdown markers are dropped whether or not rendering is on, and the line is
capped to 120 characters so no row or title bar has to carry a paragraph. `NoteSummary.title` remains
the filename; `displayTitle` is what every surface renders — switcher rows and their VoiceOver labels,
the Trash confirmation, the window title, and the title band of `NoteSearch`, so a fuzzy query reaches
a note nobody has named.

`list()` reads at most 4 KB of each unnamed note to derive it, and a named note costs nothing beyond
the enumeration it already pays for. The active note derives from the live draft rather than the
last listing, so its window title follows the first line as it is typed while its switcher row catches
up on the next autosave. Renaming edits the filename, so the rename field starts from `title`: a
derived line stands in for a name, and is never one.

`NotesRepository` owns list, create, load, save, rename, Trash, and search reads. Every
URL is validated as an immediate child of the injected directory. It lives in `Service/` because it
performs filesystem effects; `NotesStore` drives its blocking work from detached tasks.

## Ownership

`AppCore` owns `NotesStore` and lazily constructs `NotesCoordinator`, handing it the store,
`NotoSettings`, `NotesDialogs.alerts`, and the formatting bar's saved state. `NotesView` receives only
the coordinator through `@Environment`; it never receives `AppCore` or mutates the store.

The coordinator lazily owns three window controllers: `NotesWindowController` (the note window),
`NoteSwitcherWindowController` and `NoteHeadingMenuWindowController` (its two child windows). Nothing
lists or creates the Notes directory until the first show, create or search — which, with Show in Dock
on, is launch.

## Commands, switcher, and window

- Show Notes shows the last active note. From a global shortcut or the menu bar item it is a toggle
  (`NotesCoordinator.toggle`), so a second press hides a visible window; from the main menu and the
  Dock icon it only brings the window forward (`show`).
- Create Note creates and selects one unique Untitled note, including from an empty folder.
- Search Notes shows the same panel with the switcher open and its search field focused.

Every route lands on `AppCore.run(_:)` or straight on the coordinator:

| Entry point | Reaches |
| --- | --- |
| Menu bar item (`MenuBarMenu`) | `AppCore.run` for the three commands; Keep on Top writes the setting |
| Main menu, File (`NotoApp`) | New Note ⌘N and Search Notes through `AppCore.run`; Show Notes calls `show()` |
| Global shortcuts (`HotKeyManager`) | `AppCore.run`; see [hotkeys.md](hotkeys.md) |
| Dock icon click | `AppCore.handleReopen` → `show()` |
| Launch with Show in Dock on | `AppCore.start` → `show()` |

Command-N creates, Command-P opens or refocuses the switcher, Command-O reveals the active note in
Finder (or opens the folder when there is none), and Command-F opens AppKit's find bar in the active
note. Escape closes the find bar, the heading menu or the switcher before hiding; Command-W and the red
traffic light both hide directly. Hiding restores the prior external application or Noto window and
flushes without delaying the order-out — but only while that app is still the frontmost one, so closing
a window the user has already left behind leaves them in whatever app they moved to.
Command-Q quits Noto: `AppDelegate.applicationShouldTerminate` awaits the draft's flush first.

All three windows are one `NotesPanel`, a non-activating panel that owns the Escape rule and
reads ⌘⌫. They differ only in style mask, key acceptance and the chords their controller installs: the
note window claims ⌘N, ⌘P, ⌘O, ⌘F and ⌘W in `commandChords` and ⌥⌘T and ⌥⌘P in `optionCommandChords`; the
switcher reads ⌘N plus ⌘W and ⌘P as dismissals; the heading menu never becomes key.

AppKit draws the note window's frame and traffic lights; `NotesView` draws the rest of the chrome. Its
52-point title band holds the traffic lights, the centred active title, and one frosted capsule of
Create, Browse, and Open Folder. The title is drawn, not native, so it centres on the window; it is not
hit-testable, so the drag region under it moves the window. The yellow and green traffic lights are
disabled; double-clicking the free title bar moves the unchanged window to the top-right of its current
screen's visible area, 40 points in.

The switcher is a borderless child window centred on its host and hung below the title bar, not an
in-window screen — a note window may be 180pt tall, and the list must not be. It is regular glass on a
`menuPanel` corner, and its 240-point height is a ceiling rather than a size: the list reports
its own height and the window shrinks to it with the top edge pinned. It travels with its host, dismisses
like a popover when it resigns key, and closes outright when the last note goes. An empty query lists
metadata by recency; a nonempty query searches titles and literal bodies after a 120-millisecond
debounce. Results are capped at 200, and generation checks prevent superseded search or selection work
from publishing.

Arrow keys and Return do not intercept an inline rename. Command-Delete moves the selected row to Trash
only while the switcher is not renaming; in the editor and title field it remains a native text command.
Trash asks first through `NotesDialogs.confirm`; after confirmation it chooses its successor from the
current visible ordering. Each row exposes VoiceOver actions to activate, rename, and move the actual
note title to Trash.

## Dialogs

`NotesDialogs` is two injected closures: `confirm` (title, message, confirm button) and `reportFailure`
(title, message, optional recovery button). `NotesDialogs.alerts` backs both with `NSAlert.runModal`,
activating the app first because the note panel never does. The coordinator uses them for the Trash
confirmation and for the three `NotesStore.Issue` cases: a load failure and a save failure offer Retry,
an operation failure only reports. One issue is presented at a time; a second one waits for the first.

## Editor

`NoteEditorView` is one TextKit 2 `NSTextView` inside an `NSScrollView`. It installs
`NoteEditorInput.source` as `NSTextView.string` and never swaps that string for a display version.
Rendering is attributes and drawing over the source.

### Parsing

`Model/NoteMarkdownParser` splits the source on the same boundaries as `NSString.lineRange(for:)`, so
one line is one TextKit paragraph. `NoteMarkdown` gives each line its kind, UTF-16 ranges for its
content, block marker and task checkbox, and a list level from an indent stack. A source ending in a
terminator, and an empty source, get a final zero-length line, so a caret on the empty last row sits on
a real line like any other. Inline spans are not stored: `NoteMarkdown.inlines(of:)` scans the one line
asked for, which is all the styler, the editing rules and `NoteTitle` ever need.

It covers headings 1 to 6 (4 to 6 look like 3), bold, italic, bold italic, strikethrough, inline code,
links, bare `http` and `https` URLs, bullet, numbered and task lists with nesting, quotes, fenced code
blocks and horizontal rules. Inline spans never cross a line. Images, underline, HTML, setext headings,
indented code, footnotes, reference links and blocks nested inside quotes stay plain text. A GFM table
(a pipe row, a delimiter row with as many cells, then the pipe rows after it) also stays plain text, but
is recognised so it gets no inline styling: it shows in the code font, with wrapped rows hanging under
their first line, and a delimiter row typed under existing rows restyles all of them.
The whole note is reparsed on each edit.

### Rendering

`UI/NoteMarkdownRenderer` holds the parse and the set of revealed lines, and is the text storage's
delegate. Every mutation reports its edited range and length delta there, including the undo, redo and
marked-text ones that post no `textDidChange`, and several are folded into one pending edit.
`textDidChange`, `textViewDidChangeSelection` and any read of the parse consume it and reparse. The
edited lines and one neighbour on each side are restyled, widened to the rest of the note when a fenced
block moved and to any list line whose depth changed.

`NoteMarkdownStyler` turns one line into attributes. `NoteMarkdownTypography` sets the body one
system text style up (title3) and headings at largeTitle, title1 and title2, with or without
rendering. A hidden marker gets a 0.01-point system font and
a clear colour, so it stays in the string at almost no width. Fence and rule lines are cleared at their
normal font instead, so they keep their row height. Every list item (bullet, numbered or task) gets 8
points of space after it, rendered or revealed, so items read as separate rows and moving the caret
never shifts them; a wrapped item keeps normal line spacing. A restyle writes straight to
`NSTextStorage` inside `beginEditing` and `endEditing`, then invalidates layout for those lines. It
never calls `shouldChangeText`, which is what keeps styling off the undo stack.

A bullet or numbered marker becomes a list only after a space or tab; a lone `-` or `1.` stays literal.

`NoteRevealPolicy` picks the lines that show raw Markdown: every line under the selection, plus both
fences of a code block the selection is in. Nothing is revealed unless the editor is first responder in
the key window. Revealed markers use `textTertiary`. During a drag selection the reveal waits for
mouse-up, because revealing moves text under the pointer. Bullets keep their dot under the caret;
other revealed list markers keep the rendered marker's `textSecondary` colour. Revealed non-bullet list
and quote lines hang their source marker left of the content indent, so text stays where the rendered
line had it. Empty list items keep body-sized invisible markers so their line height does not collapse.
Other caret lines are raw, keeping the caret out of hidden text.

### Block drawing

`NoteLayoutFragmentProvider` is the text layout manager's delegate. A paragraph whose first character
carries a `NoteBlockDecoration` (the `noto.note.blockDecoration` attribute) is laid out by
`NoteBlockLayoutFragment`, which draws code bands with their language label, quote bars, rules,
bullets, the source's own list numbers, and checkboxes, all list markers in a neutral gray. Vertical
spacing comes from paragraph styles: overriding the fragment's frame would leave the caret above the
glyphs. There are no text attachments, overlay controls, `NSTextList`, `NSTextTable` or private API.

### Editing

`Model/NoteMarkdownEditing` turns a gesture into a `NoteEditPlan`, one replacement plus the selection
after it. Nil means AppKit handles the key natively. `NoteTextView.performEdit` applies a plan through
`shouldChangeText`, `replaceCharacters` and `didChangeText`, so each gesture is one undo step and
reaches autosave.

- Return continues a list or quote and leaves it on an empty item. Tab and Shift-Tab nest list items
  by four spaces. Backspace at an item's content start outdents it, then removes its marker. These
  edits renumber the ordered run they touch in the same undo step.
- Typing `[] ` or `[ ] ` at the start of a paragraph makes `- [ ] `.
- ⌥⌘C wraps the touched lines in a fenced block, or removes the fences of the block the selection is
  in. On an empty line it opens an empty block with the caret inside.
- ⇧⌘B adds `> ` to each touched line, or removes one `>` from each when all of them are quotes. Blank
  lines inside a selection, code, tables and rules are left alone.
- Pasting a single `http` or `https` URL over text selected on one line makes `[text](url)`.
- Clicking a checkbox toggles `[ ]` and `[x]` without moving the caret. The hit test uses
  `NoteCheckboxGeometry`, the rect the fragment draws, grown by 3 points.
- Clicking a rendered link opens it, unless the click lands in the outer 30% of the label's first or
  last glyph, which places the caret. Only `http`, `https` and `mailto` open. A revealed line carries
  no link attribute, so its URL is edited as text.

| Shortcut | Does |
| --- | --- |
| ⌘Z, ⇧⌘Z | undo, redo |
| ⌘B, ⌘I, ⌘E | bold, italic, inline code |
| ⇧⌘X | strikethrough |
| ⌥⌘C | code block |
| ⇧⌘B | quote |
| ⌘K | link |
| ⇧⌘7, ⇧⌘8, ⇧⌘9 | numbered, bullet, task list |
| ⌥⌘1, ⌥⌘2, ⌥⌘3 | heading 1, 2, 3 |
| ⌥⌘0 | plain paragraph |

Digits match by key code. The text view sees these chords before `NotesPanel` claims its own, and none
collide. In a note, ⌘E replaces AppKit's Use Selection for Find.

AppKit still owns typing, selection, Cut, Copy, Paste, Select All, Find, marked text, emoji, combining
characters and undo grouping. The editor handles ⌘Z and ⇧⌘Z while focused, including in the
non-activating panel and with rendering off. Its own `UndoManager` holds one linear history in
memory; editing after undo discards redo. The editor's coordinator observes undo and redo completion
with main-actor notifications, so both reach autosave, rendering, formatting and the character count.
Copy yields raw Markdown and VoiceOver reads the source. Changing the note
identity or editor epoch reinstalls and restyles the string and clears the previous document's undo
history. The empty-note placeholder is drawn in the text view, so opening the find bar moves it with
the editor content.

### The formatting bar

While Render Markdown and Show Formatting Bar are both on, the band under the editor holds the
character count at its leading edge and the formatting bar at its trailing edge. The bar is
`NoteFormattingBar`, a frosted capsule in the title bar's recipe. It starts collapsed to one round
`paintbrush` button; ⌥⌘T or a click expands it, and the buttons slide out from behind that button:
a heading menu, Bold, Italic, Strikethrough, Inline Code and Link, then Code Block and Quote, then
Numbered, Bullet and Task List. Hovering a button shows its name and shortcut. Each button is a
28-point square. The count hides when the row leaves it no lane, and the band never widens the note.

Expanded or collapsed is window state, not a preference: `AppCore` reads and writes it under
`notesFormattingBarExpanded` in `UserDefaults` and hands it to `NotesCoordinator`, the way it hands
the store the active note's filename. It is deliberately not a `NotoSettings` property. With Show
Formatting Bar off there is no round button at all and the count returns to its own footer.

`NoteEditorView` reports `NoteMarkdownEditing.formatting(source:selection:markdown:)` on every
install, edit and selection change, and `NotesCoordinator` publishes it only when it changed. That
function uses the same span and line rules as the toggles, so a lit button always undoes. A click goes
`NotesCoordinator.format` → `NotesWindowController.format` → `NoteTextView.format`. The buttons never
take focus, so the caret and its revealed line stay put.

The heading button opens `NoteHeadingMenuView` (Heading 1 to 3 and Text, the current one checked) in a
borderless child window that never becomes key, so it can extend past a short note window while the
editor keeps its caret and chords. It closes on a choice, Escape, any mouse down in the note window,
an edit, the note window losing key, opening the switcher, and hiding.

### The settings

Settings > Editor > Render Markdown is `NotoSettings.rendersMarkdown` (UserDefaults key
`notesRendersMarkdown`), on when absent. `NotesCoordinator` exposes it and `NotesView` hands it to
`NoteEditorView`. Off gives the literal editor: one font and colour, native Return, Tab and shortcuts,
and no parsing. Flipping it restyles the open note without touching its undo history or marking it
dirty.

Settings > Editor > Show Formatting Bar is `NotoSettings.showsFormattingBar` (key
`notesShowsFormattingBar`), on when absent. It only takes effect while Render Markdown is on, and its
row is disabled otherwise.

An empty note shows a `Start writing…` placeholder at the text container's origin. The
character count comes straight off `NSTextStorage.length` and sits in a footer under the editor, or at
the leading end of the formatting bar's band while the bar shows. Both belong to the editor surface,
so neither appears when no note is active.

### Keep on Top

Settings > Window > Keep on Top is `NotoSettings.keepsOnTop` (key `notesKeepsOnTop`). It is off when
absent.

| State | Window level | Spaces |
| --- | --- | --- |
| Off | `.normal`. Other windows can cover the note window. | The window moves to the Space where you show it. |
| On | `.floating`. The note window stays above other windows. | The window shows on every Space. |

Four controls change the setting:

- The Keep on Top row in Settings.
- The Keep on Top item in the menu bar menu. A check mark shows the state.
- ⌥⌘P in the note window.
- The Keep on Top global shortcut. See [hotkeys.md](hotkeys.md).

`NotesPanel.staysOnTop` applies the level and the Space behaviour.
`NotesWindowController.observeKeepsOnTop` copies the setting to the open panel, thus a change applies
immediately. The switcher and the heading menu take the value of the note window when they open.

### Fonts

Settings > Fonts sets four values. `NotoSettings.fonts` holds them as one `NoteFontSettings`.

| Setting | Member | UserDefaults key | When absent |
| --- | --- | --- | --- |
| Text Font | `textFamily` | `notesTextFont` | the system font |
| CJK Font | `cjkFamily` | `notesCJKFont` | the fallback that macOS selects |
| Code Font | `codeFamily` | `notesCodeFont` | the system monospaced font |
| Size | `size` | `notesFontSize` | the `title3` size |

- The text family draws body text, headings and ordered list numbers.
- The code family draws inline code, code blocks and tables.
- The size is the body size. Headings, list indents, bullets and checkboxes scale with it.
- The size range is 10 to 32 points.
- If a family is not installed, the editor uses the system font. The setting keeps its value.

`NotesView` gives `notes.fonts` to `NoteEditorView`. `Coordinator.setFonts` calls
`NoteMarkdownStyler.apply`, then `NoteMarkdownRenderer.reset()`. A font change applies to the open
note immediately. It does not change the undo history and does not make the note dirty.

#### The CJK family

The CJK family is a font cascade, not a second font attribute. `NoteMarkdownTypography` adds the CJK
family to the cascade list of each text font and each code font. Core Text uses the cascade for each
character that the primary family does not have. Thus one `NSFont` is sufficient for a mixed line,
and the literal editor uses the same font.

- A bold font gets a bold cascade entry. The traits of a font descriptor do not apply to its cascade
  list.
- The primary family draws each character that it has. Thus a Latin family draws the curly quotes
  and the ellipsis in CJK text.
- If the text family has Han characters, the CJK family has no effect on body text.
- The CJK font menu shows only the families that have Han characters.

#### Missing faces

Many families have no italic face, and some have no bold face. `Monaco`, `PingFang SC` and
`Songti SC` are examples. `NoteMarkdownTypography.emphasized` and `headingLook` use the face when the
family has it. If the family does not have it, they add a drawn substitute:

- `.obliqueness` for italic.
- A negative `.strokeWidth` for bold.

#### Monospaced families

- The code font menu shows only fixed-pitch families.
- A fixed-pitch text family is permitted. Inline code then differs from body text only by its
  background.
- CJK characters do not align with Latin columns in most monospaced families. In `Menlo`, a Han
  character is 1.66 times the width of a Latin character. Use a family with a 2:1 design to align
  them.

## Autosave

Editor changes update the main-actor draft immediately and debounce save for 300 milliseconds. Only the
active source is retained. A successful save refreshes metadata ordering; switching waits for the same
flush before loading another source. Termination awaits that flush before the app exits, but never
vetoes the quit.

A save overwrites whatever is on disk. There is no watcher, no revision comparison and no conflict
state: editing the active note in another app while Noto has it open loses that edit the next time
the debounce fires. Open Notes Folder (⌘O) invites exactly that, and this is the accepted trade for an
app whose whole job is one local editor. Every other external change is picked up, because showing
the window re-lists the folder before it presents anything.

## Verification

`Tests/notes-test.swift` compiles the shipped Notes model and service sources with the real fuzzy
matcher. It covers repository safety, unique-name claiming, derived titles, search, selection,
autosave, empty collections, relocation, switcher interaction, window placement and cancellation, plus
the Markdown parser, every edit plan, the formatting each selection reports and the reveal policy.

`Tests/notes-editor-test.swift` uses real TextKit 2 and AppKit undo objects. It runs the native
Cut/Copy/Paste, the native find bar, Unicode and marked-text cases with rendering off and on, and covers
undo isolation, undo and redo shortcut routing, source publication and character count, linear history,
exact source after styling, hidden and revealed markers, restyling after edits and after undo, block
decorations and layout fragments, list keys, chords, the task rule, checkbox toggles, link schemes,
pasting a URL, and the formatting reports and `format(_:)` the formatting bar uses.
`Tests/notes-editor-performance.swift` times install, typing and caret moves on a
100,000-character note; its budget is in [testing.md](../testing.md#performance-measurement). Window
chrome is not automated: the Notes manual sweep in [testing.md](../testing.md#notes) covers commands,
shortcuts, switcher, focus restoration, Finder, Trash recovery, and accessibility.
