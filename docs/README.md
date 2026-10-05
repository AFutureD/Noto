# Noto documentation

Start with [`AGENTS.md`](../AGENTS.md) at the repo root — it is the short version, and it links here for
anything that needs more than a line.

Each document below has one job and one trigger: the change that obliges you to edit it. A document that
contradicts the code is a defect, so fix it in the change that made it wrong.

| Document | Covers | Edit it when |
| --- | --- | --- |
| [architecture.md](architecture.md) | How the app is wired: the layers, who owns what, the windows, the Observation model, the folder tree | a layer boundary, an owner, or the tree changes |
| [standards.md](standards.md) | How code here is written: posture, naming, style, concurrency, comments | a convention changes, or a check is added |
| [testing.md](testing.md) | How to verify a change: the definition of done, the harnesses, the purity check, the editor budget, the manual sweep | a harness moves, a budget changes, or a user-visible behaviour is added |
| [development.md](development.md) | The local loop: requirements, build, Debug and Release, the project file, lint | the local toolchain or the project setup changes |
| [ui.md](ui.md) | The design system: tokens, the Notes panel, glass, the shared controls, the Settings window | a token or a presentation rule changes |

## Features

One document per feature, covering its invariants and internals. Every one of them must open with an
`## Invariants` section; read it before changing anything in that area.

[notes](features/notes.md) ·
[hotkeys](features/hotkeys.md)

Settings has no document of its own: `NotoSettings` is described in
[architecture.md](architecture.md#settings) and the window in [ui.md](ui.md#the-settings-window).
