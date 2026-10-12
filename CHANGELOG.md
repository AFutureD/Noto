# Changelog

All notable changes to Noto. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the versions follow the version rule in [release.md](docs/release.md#the-version-rule).

## [Unreleased]

### Added

- Text indented under a list item is part of the item: it sits at the item's text, keeps the list
  together and Return keeps its indentation.
- Numbered lists accept letters (`a.`, `B)`) and roman numerals (`i.`, `IV)`). Return and renumbering
  continue in the same style.

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

[Unreleased]: https://github.com/AFutureD/Noto/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/AFutureD/Noto/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/AFutureD/Noto/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/AFutureD/Noto/releases/tag/v0.1.0
