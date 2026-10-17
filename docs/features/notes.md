# Notes

Notes is the app: a folder of notes, each one a `.noto` package with a `text.md` file, edited one at
a time in one window that renders the Markdown in place. A title-bar button opens the searchable switcher. The menu bar item, the main
menu, the global shortcuts and the Dock icon show, search or extend the collection.

## Invariants

- One `<title>.noto` package with a regular `text.md` file inside is one note. The package name
  without `.noto` is the title, and `text.md` is the Markdown. The source holds no frontmatter, no
  embedded id and no title field. There is no database and no sidecar. The `assets` folder holds
  images, not data about the note. A loose `.md` file or a plain folder in the notes directory is
  not a note; a plain folder with a `text.md` is an old note and migrates.
- A note the user has not named shows its first line instead. Only the names `create` claims get a
  derived title. It is presentation only, and a name replaces it.
- The Markdown is the source. `NoteTextView.markdown`, `NotesStore`, search and the file are
  identical. The text storage holds an attachment per block marker, so its string is a display form
  that nothing outside the editor reads.
- The caret's construct is raw. Every construct under the selection shows its markers. An unfocused
  editor reveals nothing.
- Styling never reaches undo. A restyle writes with undo registration off. `MDTextView` records one
  undo step per typing run or format gesture. AppKit records none.
- The formatting bar is another way to press a shortcut. Each button sends its chord's
  `NoteEditAction` through `NoteTextView.format`, so it has the chord's gate, undo step and autosave.
  A button is lit exactly when its toggle would remove that formatting.
- Only the active note can be dirty. A switch, create, rename or delete flushes it first, so
  navigation cannot abandon a draft.
- Noto is not the only writer. Another app, or iCloud from another device, can change a note. When a
  save replaces text that the store did not read, it keeps that text as a conflict copy. See
  [sync.md](sync.md#conflicts).
- Every show re-lists the folder and reloads a clean active note. An unsaved draft stays in the
  editor, also after a failed save and after a remote change.
- Search is on demand and unindexed. An empty switcher query reads metadata plus the head of each
  unnamed note. A nonempty query reads bodies one by one off the main actor and keeps no cache of the
  collection's sources. Neither reads a file that iCloud has not downloaded.
- A note's images are files in its own `assets` folder, and the Markdown names them by a path
  relative to the package. A rename or a move keeps them. The editor shows no file outside the
  package and loads no remote image. An image the user's edits drop is deleted when the editing
  session ends, after a version keeps it. See [history.md](history.md#image-cleanup).
- The collection may be empty. The last note can be deleted. The window shows its empty state, and
  Create Note still works.
- The window's height fits the note. Each edit, note switch and bar toggle grows or shrinks it
  between the 180pt floor and 860pt, or the screen's visible height. Past that, the editor scrolls.
  The top edge holds until the bottom would leave the visible frame; then the window moves up. A
  dragged height lasts until the next edit. The height is the layout manager's used height, laid out
  from the top only until it passes the tallest window.
- Notes code asks through `NotesDialogs`, never builds an alert itself. The coordinator names the
  question; `NotesDialogs.alerts` is the one place an `NSAlert` is constructed.
- The editor gets each colour and font from `NoteEditorTheme`, which builds them from `Theme` and the
  settings. A theme change restyles the note. Nothing else sets a font.

## Storage

The notes directory is one of three folders:

| Folder | When |
| --- | --- |
| `~/Library/Application Support/<bundle-id>/Notes/` | the default |
| The Notes Folder setting (`NotoSettings.notesFolder`), absolute or under `~/` | a folder is chosen |
| The `Documents` folder of the iCloud container, iCloud Drive › Noto in Finder | iCloud Sync is on and iCloud is available; see [sync.md](sync.md#the-notes-location) |

A change of folder moves nothing. `AppCore` observes the settings and the iCloud state and calls
`NotesStore.relocate`, which saves the open draft into the old folder before it lists the new one. A
draft the old folder cannot take yet holds the move until its save lands. `AppPaths.contentFolder`
resolves the stored path. `AppPaths.contentFolderSetting` stores a chosen folder `~`-relative where it
can, or nil for the default.

A note is `<title>.noto/text.md` under the notes directory. `NotesRepository.contentFileName` names
the file and `packageExtension` the extension. `Info.plist` declares `noto` as the exported type
`app.huanan.noto.note`, which conforms to `com.apple.package`. So Finder shows a note as one item
(Show Package Contents opens it), and iCloud keeps versions of the whole note; see
[history.md](history.md). `NoteID` is the title, the package name without `.noto`, so a rename gives
a new identity. `packageURL(for:)` and `noteID(forPackage:)` are the only conversions between the
two. The immediate, non-hidden, unlinked `.noto` directories that hold a regular `text.md` are the
notes, sorted by the modification date of `text.md`, then localized title. A package that iCloud has
not downloaded lists by its own name and date, and nothing inside it is read. Other folders, loose
files, hidden entries and symbolic links are ignored. Anything else inside a package is left alone.
The `assets` folder holds the note's images; see [Images](#images).

### Migration

Noto 0.4 and earlier kept a note as a plain folder, `<title>/text.md`. A plain folder keeps no
versions in iCloud, so `NotesRepository.migrateLegacyNotes` makes each one a package. `NotesStore`
runs it before each listing, one run at a time, because a Mac with an older Noto can still add a
plain folder to iCloud.

| Case | Result |
| --- | --- |
| The folder is not in iCloud (`NotesRepository.isInICloud`) | A coordinated rename to `<title>.noto` |
| The folder is in iCloud: `isUbiquitousItem`, or any path under `~/Library/Mobile Documents` | A copy is built in a temporary folder and moved in; the old folder goes to the Trash. A rename would leave the iCloud server with a plain folder |
| `<title>.noto` exists with the same text | Another Mac migrated it. The old folder goes to the Trash |
| `<title>.noto` exists with other text | The copy takes the next free name |
| A file in the folder, or the package of that name, is not downloaded | The folder waits; its files start to download |
| A failure | The folder stays. "Couldn't Update Note" names it once; each listing tries again |

The copy keeps the modification date of `text.md`. The versions of the old `text.md` do not move into
the package. A Mac that still runs Noto 0.4 lists a package as a note named `<title>.noto`, and a save
there can make the plain folder again. Update each Mac.

Create uses `Untitled`, then `Untitled 2`, and so on. Rename claims a free name by the same rule. A
collision with another note is case- and diacritic-insensitive, so `plán` beside `Plan` becomes
`plán 2`. A note never collides with itself: only an exact name match is a no-op, which lets a rename
change only the case or the accents. The active folder name is window state under the `UserDefaults`
key `notesActiveFileName`, read and written through closures `AppCore` hands the store.

`NotesRepository` owns list, create, load, save, rename, Trash, the search reads, the copy into
iCloud, the conflict copies, the migration, the versions and the image cleanup. It takes its
directory, its Trash operation and its clock as parameters. It validates every package as an
immediate `.noto` child of the directory and every file as `text.md` inside one. Rename moves the
package; Trash moves the package. A load is a coordinated read
(`NSFileCoordinator`). A save reads and writes in one coordination. `NotesStore` drives its blocking
work from detached tasks.

## Derived titles

A note that still carries a name `create` claimed (`Untitled`, `Untitled 2`, …) shows the first line of
its source with visible text. `NoteTitle` owns that rule: it skips blank, rule and fence lines, drops
block and inline markers, and caps the line at 120 characters. `NoteSummary.title` stays the folder name.
`displayTitle` is what every surface renders: the switcher rows and their VoiceOver labels, the Trash
confirmation, the window title, and the title band of `NoteSearch`, so a fuzzy query reaches a note
nobody has named.

`list()` reads at most 4 KB of each unnamed note's `text.md`. A named note costs nothing beyond the
enumeration. An unnamed note that iCloud has not downloaded shows its folder name until it arrives.
The active note derives its title from the live draft, so the window title follows the first line as
you type, and its switcher row catches up on the next autosave. Rename edits the folder name, so the
rename field starts from `title`.

## Ownership

`AppCore` owns `NotesStore` and lazily builds `NotesCoordinator`, with the store, `NotoSettings`,
`CloudNotesLocation`, `NotesDialogs.alerts` and the formatting bar's saved state. `NotesView` receives
only the coordinator, through `@Environment`. It never sees `AppCore` and never mutates the store.

The coordinator lazily owns four window controllers: `NotesWindowController` (the note window),
`NoteSwitcherWindowController`, `NoteBarMenuWindowController` and `NoteEmojiPickerWindowController`
(three child windows). Nothing lists or
creates the Notes directory until the first show, create or search. With Show in Dock on, that is
launch.

## Commands and the window

- Show Notes shows the last active note. From a global shortcut or the menu bar item it is a toggle
  (`NotesCoordinator.toggle`): a second press hides a visible window. From the main menu and the Dock
  icon it only brings the window forward (`show`).
- Create Note creates and selects one unique Untitled note, also from an empty folder.
- Search Notes shows the window with the switcher open and its search field focused.

| Entry point | Reaches |
| --- | --- |
| Menu bar item (`MenuBarMenu`) | `AppCore.run` for the three commands; Keep on Top writes the setting |
| Main menu, File (`NotoApp`) | New Note ⌘N and Search Notes through `AppCore.run`; Show Notes calls `show()` |
| Global shortcuts (`HotKeyManager`) | `AppCore.run`; see [hotkeys.md](hotkeys.md) |
| Dock icon click | `AppCore.handleReopen`, then `show()` |
| Launch with Show in Dock on | `AppCore.start`, then `show()` |

In the window: ⌘N creates, ⌘P opens or refocuses the switcher, ⌘O reveals the active note's package in
Finder (or opens the notes directory when there is none), ⌘F opens AppKit's find bar, and ⌥⌘Y opens
the version browser ([history.md](history.md#the-version-browser)). Escape closes the emoji list, the
find bar, a bar menu or the switcher before it hides the window. ⌘W and the red traffic light hide at once. A hide
restores the previous external app or Noto window and flushes the draft, but only while that app is
still frontmost. ⌘Q quits: `applicationShouldTerminate` awaits the flush first.

All three windows are one `NotesPanel`, a non-activating panel that owns the Escape rule and reads
⌘⌫. They differ in style mask, key acceptance and the chords their controller installs. The note window
claims ⌘N, ⌘P, ⌘O, ⌘F and ⌘W in `commandChords`, and ⌥⌘T, ⌥⌘P and ⌥⌘Y in `optionCommandChords`. The
switcher reads ⌘N, and ⌘W and ⌘P as dismissals. A bar menu never becomes key.

AppKit draws the note window's frame and traffic lights. `NotesView` draws the rest: a 52-point title
band with the traffic lights, the centred active title, and one frosted capsule with Create, Browse
and Version History. The title is drawn, not native, so it centres on the window. It is not hit-testable,
so the drag region under it moves the window. The yellow and green lights are disabled. A double-click
on the free title bar moves the window to the top-right of its screen's visible area, 40 points in.

### The switcher

The switcher is a borderless child window, centred on its host and hung below the title bar. A note
window may be 180pt tall; the list must not be. It is regular glass on a `menuPanel` corner. Its
240-point height is a ceiling: the list reports its own height, and the window shrinks to it with the
top edge pinned. It travels with its host, dismisses like a popover when it resigns key, and closes
when the last note goes.

An empty query lists metadata by recency. A nonempty query searches titles and literal bodies after a
120 ms debounce. Results are capped at 200. Generation checks stop a superseded search or selection
from publishing.

Arrow keys and Return do not intercept an inline rename. ⌘⌫ moves the selected row to Trash only while
the switcher is not renaming; in the editor and the title field it stays a native text command. Trash
asks first through `NotesDialogs.confirm`, then picks its successor from the visible order. Each row
exposes VoiceOver actions to activate, rename and move the note to Trash.

### Dialogs

`NotesDialogs` is three injected closures:

| Closure | Arguments | Used for |
| --- | --- | --- |
| `confirm` | title, message, confirm button | the Trash confirmation |
| `reportFailure` | title, message, optional recovery button | the three `NotesStore.Issue` cases; "iCloud Drive Is Off" |
| `choose` | title, message, two answers, neither a cancel | "Copy N Notes to iCloud?" |

`NotesDialogs.alerts` backs all three with `NSAlert.runModal` and activates the app first, because the
note panel never does. Of the issues, a load failure and a save failure offer Retry; an operation
failure only reports. One issue shows at a time.

## Editor

`NoteEditorView` hosts one `NoteTextView`, an `MDTextView` from MDTextKit, in an `NSScrollView`.
MDTextKit is a TextKit 1 engine: PolarMark parses the Markdown into an AST, `MDTextStorage` keeps that
AST beside the attributed string, and `MDEditorController` styles each edit. The Markdown is the
source; `NoteTextView.markdown` expands the attachments back into it.

### Parsing

PolarMark re-parses the blocks an edit touches and reports the range to restyle. It covers headings 1
to 6, bold, italic, strikethrough, underline, highlight (`==text==`), inline code, links, bare URLs,
images, bullet, numbered and task lists with nesting by tab or indent, quotes, callouts (`> [!NOTE]`
and the other four kinds), fenced code blocks, rules, hard line breaks, pipe tables and folding
comments. A numbered item's label is decimal digits, then `.` or `)`. A table line joins the table only
after it ends in a newline, so the row under the caret stays text until Return. HTML, setext headings,
indented code, footnotes and reference links stay plain text.

### Rendering

`MDTextStorage` holds the AST and an attributed string in which a block marker is an attachment: a
heading's `#`, a bullet, a checkbox, a quote bar, a rule, a table, an image and a fold pill. Inline
markers stay in the string; `MDMarkdownHider` gives them a 0.01-point font until the caret enters
their construct. `MDLayoutManager` draws code bands, inline code and highlight backgrounds, quote bars
and callout boxes. A table is a grid attachment with a live cell editor: click a cell to edit it, Tab
and the arrows move between cells, and the `⋮` menu adds and removes rows and columns. A heading or
list item folds on ⌘-click on its marker.

`NoteEditorTheme` builds MDTextKit's theme from `Theme`. Every colour is a dynamic `NSColor`, so the
editor follows the appearance. `NoteTextView` restyles on an appearance change, because an attachment
caches its drawing. Body text is the `title3` size in `noteText`; headings scale from it.

Every construct under the selection shows its markers. `NoteTextView` hides every marker when it
resigns first responder or its window resigns key, and reveals the selection's constructs when it
becomes first responder again.

### Editing

`MDEditorController` turns Return, Tab, Shift-Tab, Delete and the format toggles into AST operations.
Each one is one undo step. Native typing and deletion go through `MDTextView`, which records one undo
step per typing run. AppKit's own undo is off: its records went stale when styling replaced typed text
with an attachment.

- Return continues a list or quote. On an empty item it removes the marker and keeps the line. Tab
  and Shift-Tab nest and unnest items. Delete at an item's content start removes its marker.
- ⌥⌘C wraps the paragraph in a fenced block, or removes the fences of the block the caret is in.
- ⇧⌘B adds `> ` to the paragraph, or removes it.
- ⌘K wraps the selection as `[selection]()` with the caret inside the parentheses, or unwraps the link
  under the caret to its label.
- A checkbox click toggles `[ ]` and `[x]`.
- A link icon click, or a click on link text while the editor is not first responder, opens the link.
  Only `http`, `https` and `mailto` open. `NoteEditorView.Coordinator.open` is the one place that
  leaves the app, and the harness replaces it.
- A URL pasted over selected text makes a link. Pasted rich text becomes Markdown.
- A whole list item, heading, table, rule or quote drags as a block and drops as whole lines.

| Shortcut | Does |
| --- | --- |
| ⌘Z, ⇧⌘Z | undo, redo |
| ⌘B, ⌘I, ⌘E, ⌘U | bold, italic, inline code, underline |
| ⇧⌘X, ⇧⌘H | strikethrough, highlight |
| ⌘K | link |
| ⌥⌘C, ⇧⌘B | code block, quote |
| ⇧⌘7, ⇧⌘8, ⇧⌘9 | numbered, bullet, task list |
| ⌥⌘1, ⌥⌘2, ⌥⌘3, ⌥⌘0 | heading 1, 2, 3, plain paragraph |
| ⌥⌘T | expand or collapse the formatting bar |

Digits match by key code. `NoteTextView` sees these chords before `NotesPanel` claims its own, and
none collide. `.setHeading` sets a level; the current level changes nothing, and Text removes the
heading.

AppKit owns typing, selection, Cut, Copy, Paste, Select All, Find, marked text, emoji and combining
characters. `MDTextView.editorUndoManager` holds one linear history in memory; an edit after undo
discards redo. The text view posts `MDTextViewTextDidChangeNotification` synchronously after each
change, undo and redo, and the coordinator observes it, so all of them reach autosave, the formatting
reports and the character count. Copy yields raw Markdown. A new note identity or editor epoch
reinstalls the Markdown and clears the history.

An empty note shows a `Start writing…` placeholder, drawn in the text view, so the find bar moves it
with the content. The character count is the Markdown's UTF-16 length. It sits in a footer under the
editor, or at the leading end of the formatting bar's band. Both belong to the editor surface, so
neither shows without a note.

### Images

A pasted image, or an image file dropped on the editor, becomes a file in the note's `assets`
folder and an `![](assets/<name>)` line at the paste. `NoteTextView.readSelection` reads dropped and
pasted files itself, because MDTextKit's reader looks only at the first file and inserts a folder's
path as text. Only image files import: a folder, a video or another file is skipped and logged.
Pasted image data, which has no file, goes through MDTextKit's reader as a temporary PNG. Both end
in `NoteTextView.addFilesBlock`. `NotesStore.importAssets` copies them off the main actor through
`NotesRepository.importAssets`, in one coordinated write. A dropped file keeps its name. A pasted
image is `Pasted yyyy-MM-dd HH.mm.ss.png`, so two Macs that paste into one note offline write two
files. A taken name becomes `<name> 2`, then `<name> 3`, case-insensitively. The original stays where
it was. An `assets` that is a symbolic link fails the import.

The Markdown goes where the paste was while no edit moved the text, else at the caret. Each image is
its own paragraph: a line break goes before it after other text on the line, and after it before
more text, so every image starts at the margin. A switch to
another note or a reload before the copy lands drops the Markdown and logs it; the copied file
stays until the cleanup. A failed copy reports an operation failure.

An image whose Markdown the user deletes stays while the editing session lasts, so ⌘Z can bring it
back. When the session ends, `NotesStore` deletes it; see [history.md](history.md#image-cleanup).

`imageFileResolver` resolves each image path with `NoteAssets.resolve` against `noteFolder`, the
active note's package. An absolute path, a remote URL and a path out of the package resolve to
nil, which shows a placeholder. When the notes folder moves under the same note, the editor restyles,
so the images resolve again. An image that iCloud has not downloaded shows the placeholder.

### Emoji

`:` and two or more letters, digits, `_`, `+` or `-` open the emoji list under the `:`. The `:`
comes at a line start, after a space, an opening bracket or a block marker such as `- `. `EmojiCatalog` finds the emoji by the Unicode names of the
OS, so there is no bundled table. It ranks a shortcode alias (`+1`, `tada`), a whole name, a whole
word, then an alias or a word that starts with the query. The list shows up to `NoteEmojiPicker.rowLimit` rows.
A flag, a skin tone or a family is a sequence of scalars and is not in the catalog.

`NoteTextView` owns the query and the selection. It reports each change through
`onEmojiPickerChange`, and `NoteEmojiPickerWindowController` shows the list in a child window that
never becomes key. The up and down arrows move the selection and wrap. Return, Tab or a click
replaces `:query` with the emoji in one undo step. Escape closes the list until the query changes. A
caret move off the query, marked text, a code block or code span, an undo or redo, and the loss of
focus close it. Focus coming back does not open it again; the next edit or caret move does. The
editor host updates the list after MDTextKit posts each text or selection change,
so the check never runs in the middle of an edit.

## The formatting bar

With Show Formatting Bar on, the band under the editor holds the character count at its leading edge
and `NoteFormattingBar` at its trailing edge: a frosted capsule in the title bar's recipe. It starts
collapsed to one round `paintbrush` button. ⌥⌘T or a click expands it, and the buttons slide out from
behind that button: a Heading menu, Bold, Italic, Highlight and Link, then Quote, then a List menu and
a More menu. Hover shows a button's name and shortcut. Each button is a 28-point square; a menu button
adds a chevron. The count hides when the row leaves it no room, and the band never widens the note.

`NoteBarMenu` lists the three menus and their rows:

| Menu | Rows |
| --- | --- |
| Heading (`textformat.size`) | Heading 1, Heading 2, Heading 3, Text |
| List (`list.bullet`) | Bullet List, Numbered List, Task List |
| More (`ellipsis`) | Underline, Strikethrough, Inline Code, Code Block |

A menu button lights while one of its rows applies, and that row shows a checkmark. A menu button opens
`NoteBarMenuView` in one borderless child window, `NoteBarMenuWindowController`, that never becomes
key, so it can extend past a short note window while the editor keeps its caret and chords.
`NotesCoordinator.presentedBarMenu` names the open menu. The menu closes on a choice, Escape, a mouse
down in the note window, an edit, the window's loss of key, the switcher, and a hide. A click on
another menu button opens that menu instead.

`NoteEditorView` reports `MDEditorController.formatting(in:)`, mapped onto `NoteFormatting`, on every
install, edit and selection change. `NotesCoordinator` publishes it only when it changed. The query
reads the annotations the toggles use, so a lit button always undoes. A click goes
`NotesCoordinator.format`, then `NotesWindowController.format`, then `NoteTextView.format`. The
buttons never take focus, so the caret and its revealed construct stay.

Expanded or collapsed is window state, not a preference. `AppCore` reads and writes it under
`notesFormattingBarExpanded` and hands it to `NotesCoordinator`. With Show Formatting Bar off there is
no round button, and the count returns to its own footer.

## Settings

The Editor settings below sync to iCloud while iCloud Sync is on. Keep on Top does not. See
[sync.md](sync.md#the-settings-mirror).

### Show formatting bar

Settings > Editor > Show formatting bar is `NotoSettings.showsFormattingBar` (key
`notesShowsFormattingBar`), on when absent.

### Keep on Top

Settings > General > Keep on top is `NotoSettings.keepsOnTop` (key `notesKeepsOnTop`), off when absent.

| State | Window level | Spaces |
| --- | --- | --- |
| Off | `.normal`; other windows can cover the note window | the window moves to the Space where you show it |
| On | `.floating`; the note window stays above other windows | the window shows on every Space |

Four controls change it: the checkbox in Settings, the Keep on Top item in the menu bar menu (a check
mark shows the state), ⌥⌘P in the note window, and the global shortcut. `NotesPanel.staysOnTop`
applies the level and the Space behaviour. `NotesWindowController.observeKeepsOnTop` copies the
setting to the open panel, so a change applies at once. The switcher and a bar menu take the value of
the note window when they open.

### Fonts

Settings > Editor sets five font values. `NotoSettings.fonts` holds them as one `NoteFontSettings`.

| Setting | Member | Key | When absent |
| --- | --- | --- | --- |
| Text Font | `textFamily` | `notesTextFont` | the system font |
| Heading Font | `headingFamily` | `notesHeadingFont` | the text family |
| CJK Font | `cjkFamily` | `notesCJKFont` | the fallback that macOS selects |
| Code Font | `codeFamily` | `notesCodeFont` | the system monospaced font |
| Text size | `size` | `notesFontSize` | the `title3` size |

- The text family draws body text. The heading family draws headings in its bold face; heading sizes
  do not change with the family. The code family draws inline code, code blocks and tables.
- The size is the body size, 10 to 32 points. Headings, list indents, bullets and checkboxes scale
  with it.
- A family that is not installed leaves the theme's own font in place. The setting keeps its value.
- MDTextKit uses a family's real faces only. A family without an italic face shows emphasis upright;
  one without a bold face shows strong text at its regular weight. `Monaco`, `PingFang SC` and
  `Songti SC` have no italic face.
- The code menu shows only fixed-pitch families. A fixed-pitch text family is permitted; inline code
  then differs from body text only by its background. In most monospaced families a Han character is
  not two Latin columns wide (1.66 in `Menlo`); use a family with a 2:1 design to align them.

The CJK family is a font cascade, not a second font attribute. `NoteEditorTheme.overrides` names it in
the `cjk` override of the text, heading and code fonts, and `SFThemeManager` adds it to each font's
cascade list. Core Text uses the cascade for each character the primary family lacks, so one `NSFont`
is enough for a mixed line. A bold font gets a bold cascade entry. The primary family draws each
character it has, so a Latin family draws the curly quotes and the ellipsis in CJK text. If the text
family has Han characters, the CJK family has no effect on body text. The CJK menu shows only families
with Han characters.

`NotesView` gives `notes.fonts` to `NoteEditorView`. `Coordinator.setFonts` rebuilds the overrides with
`NoteEditorTheme.overrides`, applies the theme and restyles the note. The change applies at once. It
does not touch the undo history and does not make the note dirty. The highlight and accent colours
follow the same path.

### Highlight colour

Settings > Editor > Highlight is `NotoSettings.highlightColor` (key `notesHighlightColor`): the
background of a `==highlight==` span. When nil, the span draws `Theme.Colors.highlight`, which follows
the appearance. A chosen colour is stored as `#RRGGBBAA` in sRGB and draws the same in Dark and Light.
Use Default clears it.

### Accent colour

Settings > Editor > Accent is `NotoSettings.accentColor` (key `notesAccentColor`): the colour of a
`~underline~`, a link and the selection. The selection draws the accent at
`NoteEditorTheme.selectionAlpha`. When nil, the editor uses `NSColor.controlAccentColor`, the accent
chosen in System Settings. A chosen colour is stored as `#RRGGBB` in sRGB, has no alpha, and draws the
same in Dark and Light. Use Default clears it.

## Autosave

An edit updates the main-actor draft at once and debounces the save for 300 ms. A draft that is the
text on disk again, after an edit and its undo, writes nothing. Only the active
source is kept. A successful save refreshes the metadata order. A switch waits for the same flush
before it loads another source. Termination awaits the flush and never vetoes the quit.

`NotesStore` keeps the base: the text of the active note as the store last read or wrote it. A save
gives the repository the draft and the base:

- The file holds the base. The save replaces it with the draft.
- The file holds other text, from another app or another device. The save first keeps that other
  text as the note `<title> (Conflict yyyy-MM-dd HH.mm)`, then writes the draft. The editor stays on
  the active note.
- The package is gone. The save creates it again with the draft.

The rules are in [sync.md](sync.md#conflicts). Each show re-lists the folder. With iCloud Sync on,
a change from another device also re-lists it; see [sync.md](sync.md#the-watcher). When the active note
is clean, the re-list also reloads it from disk. A show waits for a save in flight first. An edit or a
selection change during the read discards the read's result. Unchanged content keeps the editor
history; a changed source or identity resets it. When the active note's package or `text.md` is gone,
the load selects another note, or the empty state.

## Verification

`notes-test` and `notes-editor-test` cover this feature; the window chrome and the iCloud parts are
manual. See
[testing.md](../testing.md).
