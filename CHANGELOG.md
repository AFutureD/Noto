# Changelog

All notable changes to Noto. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the versions follow the version rule in [release.md](docs/release.md#the-version-rule).

## [Unreleased]

### Changed

- The copyright line in Get Info names the Noto author and the Tinycast author.

## [0.3.0] - 2026-10-13

### Added

- Callouts (`> [!NOTE]`, `[!TIP]`, `[!IMPORTANT]`, `[!WARNING]`, `[!CAUTION]`) render as boxes.
- A pipe table renders as a grid. Click a cell to edit it in place; the `⋮` menu adds and removes
  rows and columns.
- An image (`![alt](path)`) renders in the note.
- `~underline~` renders underlined.
- ⌘-click a heading's marker to fold its section; click the pill to unfold it.
- ⌘K in a link removes the link and keeps its label.
- Pasting rich text from another app pastes it as Markdown.
- Dragging a list item, heading, table, rule or quote moves it as a whole line.
- The Editor pane has an accent colour setting. Underlines, links and the selection use it; the
  default is the macOS accent colour.
- ⌘U toggles `~underline~`.

### Changed

- A note is a folder named for its title, with the Markdown in `text.md` inside it. A loose `.md`
  file in the notes folder is no longer a note; nothing is migrated.
- Open Notes Folder selects the note's folder in Finder.
- The editor is MDTextKit. Block markers (headings, bullets, checkboxes, quotes, rules) draw as
  attachments, and the caret reveals the markers of its construct rather than its whole line.
- The Formatting Bar setting no longer depends on another setting.
- The formatting bar groups the three list buttons under one List menu and moves Underline,
  Strikethrough, Inline Code and Code Block into a More menu at its trailing end.
- Return on an empty list item removes the marker and keeps the line.

### Removed

- The Render Markdown setting. The editor always renders.
- Letter (`a.`) and roman numeral (`iv)`) list labels. They render as text.

## [0.2.1] - 2026-10-12

### Added

- Text indented under a list item is part of the item: it sits at the item's text, keeps the list
  together and Return keeps its indentation.
- Numbered lists accept letters (`a.`, `B)`) and roman numerals (`i.`, `IV)`). Return and renumbering
  continue in the same style.

### Fixed

- With a wide text family, a numbered item no longer moves its text when the caret reveals the number.
  A nested item keeps its text in place too, and so do a task and a number too wide to hang: they
  keep their drawn marker under the caret. A tab-indented item sits where a space-indented one does.

### Changed

- Nested list content sits 4pt under its item and its siblings; top-level items keep 8pt.
- A `-` bullet draws a short bar; `*` and `+` bullets keep the dot.
- A task checkbox is a filled block with round corners. A done task shows a dark check on its box.

## [0.2.0] - 2026-10-12

### Added

- `==highlight==` spans render with a highlight colour, and the Editor pane has a highlight colour
  setting.

### Changed

- The note window's height fits the note. It grows and shrinks with the text between 180pt and 860pt,
  or the screen's visible height. A dragged height lasts until the next edit.

### Fixed

- A note edited in another app reloads when the window shows again, when the note has no unsaved
  draft.
- Open Notes Folder brings Finder to the front when the Settings window is open or Show in Dock is on.
- Typing in a list no longer shrinks the window by one row on each keystroke.
- A list item whose first word is wider than the window keeps its bullet, number or checkbox on the
  first line of text.

## [0.1.1] - 2026-10-12

### Added

- The app icon, made with Icon Composer.

## [0.1.0] - 2026-10-12

The first release. Noto is the Notes feature of [Tinycast](https://github.com/abue-ammar/tinycast)
as an app of its own; see [NOTICE.md](NOTICE.md).

### Added

- A menu bar app that edits a folder of Markdown files in one window and renders the Markdown in
  place.
- Four global shortcuts: Show Notes, Create Note, Search Notes and Keep on Top.
- Keep on Top holds the window above other apps and on every Space. It is off by default.
- A Settings window with General, Editor and Shortcuts panes.
- Custom editor fonts and a heading font.
- Show in Dock, off by default.
- Updates through Sparkle.

[Unreleased]: https://github.com/AFutureD/Noto/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/AFutureD/Noto/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/AFutureD/Noto/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/AFutureD/Noto/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/AFutureD/Noto/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/AFutureD/Noto/releases/tag/v0.1.0
