# Noto documentation

[`AGENTS.md`](../AGENTS.md) at the repository root is the short version. It gives the rules and links
here for the detail.

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

Settings has no document of its own. [architecture.md](architecture.md#settings) describes
`NotoSettings`, and [ui.md](ui.md#the-settings-window) describes the window.
