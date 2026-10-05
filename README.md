# Noto

Plain Markdown notes in one window for macOS.

Noto keeps an unlimited collection of `.md` files and edits them in a single always-on-top editor that
formats the Markdown as you write. It lives in the menu bar, needs no account, and has no database:
the files are the notes.

## Features

- One note window that remembers its size and position.
- Keep on Top is an option. When it is on, the note window stays above other windows and shows on
  every Space. It is off by default.
- Markdown rendered in place: headings, bold, italic, strikethrough, inline code, links, bullet,
  numbered and task lists, quotes, code blocks and rules. The line you are editing shows its raw
  Markdown; every other line stays formatted. What is saved, searched and copied is the text you typed.
- A formatting bar with a button for each shortcut, and a heading menu.
- A note switcher with fuzzy title search and full-text search, inline rename and Move to Trash.
- An untitled note shows its first line as its title until you name it.
- Four global shortcuts: Show Notes, Create Note, Search Notes and Keep on Top. Record them in
  Settings. A shortcut has no key until you record one.
- A menu bar item, and an optional Dock icon (Settings > General > Show in Dock).
- Autosave 300 ms after you stop typing.
- Render Markdown can be turned off for a plain-text editor.
- You can set the text font, the heading font, the CJK font, the code font and the size.

Images, tables and syntax highlighting are not rendered; they appear as text.

## Shortcuts

In the note window:

| Key | Does |
| --- | --- |
| ⌘N | Create a note |
| ⌘P | Open the switcher, or return to it |
| ⌘O | Show the note in Finder |
| ⌘F | Find in the note |
| ⌘W | Hide the window |
| esc | Close the find bar, the heading menu or the switcher, then hide the window |
| ⌘⌫ | Move the selected switcher row to the Trash |
| ⌥⌘T | Show or hide the formatting buttons |
| ⌥⌘P | Set Keep on Top on or off |
| ⌘, | Open Settings |
| ⌘Q | Quit Noto, after saving the open note |

While editing, with Render Markdown on:

| Key | Does |
| --- | --- |
| ⌘B, ⌘I | Bold, italic |
| ⇧⌘X | Strikethrough |
| ⌘E | Inline code |
| ⌘K | Link |
| ⌥⌘C | Code block |
| ⇧⌘B | Quote |
| ⇧⌘7, ⇧⌘8, ⇧⌘9 | Numbered, bullet, task list |
| ⌥⌘1, ⌥⌘2, ⌥⌘3 | Heading 1, 2, 3 |
| ⌥⌘0 | Back to a plain line |

Return continues a list and ends it on an empty item; Tab and Shift-Tab indent and outdent items.
Typing `[] ` at the start of a line starts a task, clicking a checkbox toggles it, and pasting a web
address over selected text makes a link.

## Build and run

Requires macOS 26 and Xcode 26 or later.

```sh
open Noto.xcodeproj    # then ⌘R
```

Or from the command line:

```sh
xcodebuild -project Noto.xcodeproj -scheme Noto -configuration Debug \
    -derivedDataPath build/DerivedData build
open "build/DerivedData/Build/Products/Debug/Noto Dev.app"
```

A Debug build is named `Noto Dev.app` but shares the bundle id `app.huanan.noto`, so it reads and
writes the same notes and settings as a Release build. See [docs/development.md](docs/development.md) for the rest, and
[docs/](docs/README.md) for the architecture, standards and per-feature documents.

## Where your notes live

```text
~/Library/Application Support/app.huanan.noto/Notes/
```

Each note is one `.md` file and its filename is its title. Settings > General > Notes folder points
Noto at any other folder instead; nothing is moved when you change it. Only files directly in the
folder count — subfolders, hidden files and links are ignored.

Saving overwrites the file on disk. Noto does not watch the folder, so an edit made in another app to
the note that is open in Noto is lost at the next autosave. Every other outside change is picked up
the next time the window is shown.

## Origin and license

Noto is derived from the Notes feature of [Tinycast](https://github.com/abue-ammar/tinycast). It does
not read or migrate Tinycast's data. See [NOTICE.md](NOTICE.md).

Licensed under [AGPL-3.0](LICENSE).
