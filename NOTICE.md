# Notice

Noto
Copyright (C) 2026 Huanan

Noto contains code from [Tinycast](https://github.com/abue-ammar/tinycast), Copyright (C) 2026 Abue
Ammar. Tinycast is licensed under the GNU Affero General Public License, version 3 or later. Noto is a
modified version of that code, and Noto is distributed under the same licence. See [LICENSE](LICENSE).

## What came from Tinycast

Noto started from Tinycast at commit
[`46beb10a`](https://github.com/abue-ammar/tinycast/commit/46beb10a) on 2026-10-05. Noto then took
later changes to the Tinycast Notes feature by hand, up to commit
[`59c0794f`](https://github.com/abue-ammar/tinycast/commit/59c0794f) of 2026-10-10. On 2026-10-13,
Noto stopped taking Tinycast changes.

These parts came from Tinycast:

- The Notes feature: the notes repository and store, the note search and fuzzy match, the note window,
  the switcher, the heading menu, the formatting bar and the editor host.
- The parts of the design system that those views use: the `Theme` tokens, `InterfaceMetrics`,
  `BarButton`, `KeyCapChip`, `Tooltip`, `SymbolImage`, `GlassEffectView` and the overflow fade.
- The global hotkey engine and its Settings recorder: `KeyShortcut`, `HotKeyCenter`, the capture
  session, the recorder field and its callout.
- Platform helpers: storage paths, the activation policy, signposts, the notification token and the
  titled-window controller.
- The Notes test harnesses and the scripts that run and lint them.

## What changed

Noto modified this code from October 2026:

- Noto removed the Tinycast launcher, the palette and all other Tinycast features.
- Noto added an app shell, a settings model, a Settings window, a menu bar item and a Dock mode.
- MDTextKit replaced the Tinycast Markdown parser, styler and TextKit 2 editor.

## Other components

- [MDTextKit](https://github.com/AFutureD/MDTextKit) is the Markdown editor engine. It is a separate
  package with its own licence, the MIT licence.
- [Sparkle](https://sparkle-project.org) installs updates. It is distributed under the MIT licence;
  see its [LICENSE](https://github.com/sparkle-project/Sparkle/blob/2.x/LICENSE).
