# Notice

Noto is a derivative work of [Tinycast](https://github.com/abue-ammar/tinycast), Copyright (C) 2026
Abue Ammar, and is distributed under the same licence: the GNU Affero General Public License v3. See
[LICENSE](LICENSE).

## What was taken from Tinycast

The code was taken from Tinycast at commit
[`46beb10a`](https://github.com/abue-ammar/tinycast/commit/46beb10a) on 2026-10-05. Later Tinycast
changes to the Notes feature are ported manually. [development.md](docs/development.md#upstream)
records the last ported commit.

- The Notes feature: the Markdown model, parser and edit planning, the notes repository and store, the
  TextKit 2 editor, the note window, switcher, heading menu and formatting bar.
- The parts of the design system those views use: the `Theme` tokens, `InterfaceMetrics`, `BarButton`,
  `KeyCapChip`, `Tooltip`, `SymbolImage`, `GlassEffectView` and the overflow fade.
- The global hotkey engine and its Settings recorder: `KeyShortcut`, `HotKeyCenter`, the capture
  session, the recorder field and its callout.
- Platform helpers: storage paths, the activation policy, signposts, the notification token and the
  titled-window controller.
- The Notes test harnesses and the script that runs them.

## What changed

The code was modified on extraction, starting in October 2026: Tinycast's launcher, palette and
every other feature were removed, and an app shell, settings model, Settings window, menu bar item
and Dock mode were written around what remained. Beyond the above, Noto bundles one third-party
framework: [Sparkle](https://sparkle-project.org), which installs updates. Sparkle is distributed
under the MIT licence; see its
[LICENSE](https://github.com/sparkle-project/Sparkle/blob/2.x/LICENSE).
