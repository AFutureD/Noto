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

Noto edits a folder of `.md` files in one window. It lives in the menu bar, needs no account and has
no database. The files are the notes.

## Features

- Markdown renders in place. The construct you edit shows its markers; the rest stays formatted.
  Tables are grids, callouts are boxes, and headings fold.
- One window, one note at a time. A switcher (⌘P) searches titles and bodies.
- Four global shortcuts: Show Notes, Create Note, Search Notes and Keep on Top.
- Keep on Top holds the window above other apps and on every Space.
- Your fonts, your folder. Noto updates itself.

## Install

Download `Noto-<version>.dmg` from the
[latest release](https://github.com/AFutureD/noto-releases/releases/latest) and drag Noto to
Applications. Noto needs macOS 26 on Apple Silicon.

Notes live in `~/Library/Application Support/app.huanan.noto/Notes/`. Settings can point Noto at any
other folder.

## Build from source

Requires macOS 26 and Xcode 27.

```sh
open Noto.xcodeproj    # then ⌘R
```

See [docs/](docs/README.md) for the architecture, the standards and each feature.

## License

Noto is derived from the Notes feature of [Tinycast](https://github.com/abue-ammar/tinycast); see
[NOTICE.md](NOTICE.md). Licensed under [AGPL-3.0](LICENSE).
