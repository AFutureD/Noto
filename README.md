<p align="right">English · <a href="README.zh-CN.md">简体中文</a></p>

<p align="center">
  <img src="Resource/Brand/Noto-icon-512.png" width="128" alt="Noto app icon">
</p>

<h1 align="center">Noto</h1>

<p align="center">Plain Markdown notes in one window for macOS.</p>

<p align="center">
  <a href="https://github.com/AFutureD/noto-releases/releases/latest">Download</a> ·
  <a href="#build-from-source">Build</a> ·
  <a href="docs/README.md">Docs</a>
</p>

<p align="center">
  <img src="Resource/Screenshots/note-window.png" width="600" alt="The Noto note window with a rendered note.">
</p>

Noto edits a folder of notes in one window. Each note is a folder named for its title, with the
Markdown in `text.md`. Noto lives in the menu bar, needs no account and has no database.

## Features

- Markdown renders in place. The construct you edit shows its markers; the rest stays formatted.
  Tables are grids, callouts are boxes, and headings fold.
- One window, one note at a time. A switcher (⌘P) searches titles and bodies.
- Four global shortcuts: Show Notes, Create Note, Search Notes and Keep on Top.
- Keep on Top holds the window above other apps and on every Space.
- Your fonts, your folder. Noto updates itself.
- Paste or drop an image, and it shows in the note. The file goes in the note's own folder.
- Type `:` and a word, such as `:smile`, to pick an emoji.
- Optional iCloud sync for your notes and your Editor and Shortcuts settings.

## Install

Download `Noto-<version>.dmg` from the
[latest release](https://github.com/AFutureD/noto-releases/releases/latest) and drag Noto to
Applications. Noto needs macOS 26 on Apple Silicon.

Notes live in `~/Library/Application Support/app.huanan.noto/Notes/`, one folder per note. Settings
can point Noto at any other folder, or at iCloud Drive › Noto with iCloud Sync.

## Build from source

Requires macOS 26 and Xcode 27.

```sh
open Noto.xcodeproj    # then ⌘R
```

See [docs/](docs/README.md) for the architecture, the standards and each feature.

## License

Noto is licensed under [AGPL-3.0](LICENSE). Noto started as the Notes feature of
[Tinycast](https://github.com/abue-ammar/tinycast) and still contains its code. [NOTICE.md](NOTICE.md)
lists the parts that came from Tinycast and the licences of the other components.
