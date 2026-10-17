# Noto documentation

[`AGENTS.md`](../AGENTS.md) at the repository root says how to work here. It links here for the rules
and the detail.

Read the documents in this order. Each one builds on the one before it.

| Step | Document | Covers | Edit it when |
| --- | --- | --- | --- |
| 1 | [development.md](development.md) | Requirements, build, run, Debug and Release, the project file, lint | the toolchain or the project setup changes |
| 2 | [architecture.md](architecture.md) | The layers, the owners, the windows, the settings, Observation, concurrency, the folder tree | a layer boundary, an owner, a window or the tree changes |
| 3 | [standards.md](standards.md) | How to write code here: posture, naming, style, concurrency rules, comments | a convention changes |
| 4 | [ui.md](ui.md) | The design system: tokens, the note window, glass, the shared controls, the Settings window | a token or a presentation rule changes |
| 5 | [features/](#features) | One document per feature: its invariants, then its internals | that feature changes |
| 6 | [testing.md](testing.md) | The definition of done, the harnesses, the checks, the performance budget, the manual sweep | a check, a harness or a user-visible behaviour changes |
| 7 | [release.md](release.md) | How a version ships: the two repositories, the version rule, the workflow, the secrets | the workflow, a secret or the version rule changes |

A document that contradicts the code is a defect. Fix it in the change that made it wrong.

## Features

Each feature document opens with an `## Invariants` section. Read it before you change that feature.

- [notes.md](features/notes.md): the collection, the window, the editor, the formatting bar, the
  editor settings
- [hotkeys.md](features/hotkeys.md): the four global shortcuts and the recorder
- [updates.md](features/updates.md): the Sparkle updater
- [sync.md](features/sync.md): iCloud sync of the notes and the settings, and conflict copies
- [history.md](features/history.md): the versions of a note, the system version browser, restore and the
  image cleanup

## Research

A research record keeps what was measured before a design decision, with the tests. It does not
change with the code; a feature document does.

- [research/version-history.md](research/version-history.md): why a note is a `.noto` package, and
  what iA Writer, `NSFileVersion` and iCloud do with versions

Settings has no document of its own. [architecture.md](architecture.md#settings) describes
`NotoSettings`, [ui.md](ui.md#the-settings-window) describes the window, and
[sync.md](features/sync.md#the-settings-mirror) describes which settings sync.

## Documentation language

Write all documentation in ASD-STE100 Simplified Technical English. This applies to `README.md`,
`NOTICE.md`, `CHANGELOG.md` and each file in `docs/`. `AGENTS.md` is in Chinese. Names of types, files, settings
and commands are technical names. Write them as the code writes them.

`README.zh-CN.md` is the Chinese translation of `README.md`. When you change one, change the other.

`CHANGELOG.md` follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). A change the user
can notice has a line under `Unreleased`.
