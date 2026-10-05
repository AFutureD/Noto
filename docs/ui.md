# UI & Design System

The design system for Noto's UI, written so an agent restyling or extending it stays consistent
with what's already there. This documents Noto as built — every rule here maps to code in
`Noto/`. `Noto/DesignSystem/Theme.swift` is the single design-token source.

Read this before touching any view body, `Theme` value, or the panel chrome.

## The look, in one paragraph

The note window is a panel whose surface is the OS glass under a 40% black scrim — there is
no gray chrome. Everything on that surface is white at a fixed alpha ramp. There are no hard-edged
bars, strips or dividers: the title band and the bottom band are just regions of the same surface.
Floating controls (the title-bar capsule, the formatting bar, the switcher, the heading menu, the
recorder callout) are Liquid Glass.

That paragraph describes Dark, which is the design. Light is the same design with the ink
inverted: a white scrim over the same glass, and a black-alpha ramp at matched stops. Nothing about
geometry, type, motion or state changes between them.

The Settings window is the one surface that does not share this look; it is stock macOS.

## Invariants

These are the things that quietly break the look if changed. Preserve them unless the task is
explicitly to change them.

- Dark is the baseline. Every `Theme.Colors` token resolves per appearance. Retune a light branch
  freely; touch a dark one only when the task is to change Dark. Noto assigns no appearance; every
  window follows macOS.
- New colors go through `Theme.Colors.ramp(dark:light:)` (an alpha that inverts) or
  `adaptive(dark:light:)` (two explicit `NSColor`s, for anything that isn't a plain inversion —
  `panelScrim`). Never a bare `Color.white.opacity(…)` in a view: it disappears in Light.
- No grays, no opaque fills on the surface. Reach for `Theme.Colors.*` instead of `.gray` or
  `NSColor.windowBackgroundColor`. `Tooltip`'s tile is the one deliberate opaque fill, because a label
  has to stay readable over whatever it hangs across.
- The `OverflowFade` gradient is mask luminance, not color. It stays black in both appearances;
  inverting it breaks the fade.
- A colour TextKit draws with is pinned first. A layout fragment cannot resolve a dynamic colour, so
  `NoteMarkdownStyler` resolves each token under the text view's drawing appearance, and
  `NoteMarkdownRenderer.reset()` drops them when the appearance changes.
- The panel corner is clipped once, at the root. `NotesView.body` ends with
  `.background(panelScrim)` → `.background(GlassEffectView())` →
  `.clipShape(RoundedRectangle(26, .continuous))`. Keep that order; the scrim goes over the glass, and
  the clip is last.
- Test over a light desktop. Transparency and corner masking bugs only show over bright wallpaper.
- The formatting bar's hover labels are Noto's `tooltip`, never `.help()`: the label carries the
  shortcut, aligns against a window edge and draws outside the capsule. The title-bar capsule and the
  switcher's row buttons use `.help()`.
- Glass is for floating controls. The note window's main surface is the scrim-over-glass recipe, never
  `.glassEffect` on the root.
- Notes asks its questions with system alerts, through `NotesDialogs`. No view builds one.

## Tokens

Source: `Noto/DesignSystem/Theme.swift`.

`Theme` is the single source of truth. Never hardcode a spacing, radius, size or color that has a
token. Add a token rather than a magic number when introducing a new value.

### `InterfaceMetrics`

`Noto/DesignSystem/InterfaceMetrics.swift` stores only a scale and derives every value from the
`Theme` literal. Noto has no interface-size setting, so the environment's `\.metrics` is always
`.standard`, which is `Theme` verbatim. `BarButton`, `KeyCapChip` and `Tooltip` read
`@Environment(\.metrics)` rather than `Theme` directly; a new shared control in `DesignSystem/` does
the same for the tokens `InterfaceMetrics` carries (`spacing.xxs`–`md`, `radius.barControl`/`keyCap`/
`tooltip`, `size.barButtonHeight` and the three keycap sizes, and the three keycap fonts).

### Spacing (`Theme.Spacing`)

`xxs 2` · `xs 4` · `sm 6` · `md 8` · `lg 10` · `xl 12`

`xxs` is the tight gap between adjacent keycap chips and between bar buttons in one group.

### Radius (`Theme.Radius`)

`panel 26` · `menuPanel 16` · `row 10` · `menuRow 10` · `barControl 8` · `tooltip 8` · `keyCap 6` ·
`menu 6` · `recorderKeyCap 4`

`panel` is the note window. `menuPanel` is the switcher, the heading menu and the recorder callout.
`row` is a switcher row's fill and `menuRow` a heading-menu row's hover. `menu` is the small-control
corner: the recorder field and the ends of a code band.

Always `RoundedRectangle(cornerRadius:, style: .continuous)` — continuous corners everywhere, never
`.circular`. Where two rounded corners sit adjacent, the inner radius is the outer radius minus the gap
between them: inside a menu, `menuPanel 16` − `Spacing.sm 6` = `menuRow 10`.

The title-bar capsule and the formatting bar are `Capsule`s, and so are the hover fills of the
buttons inside them. A capsule's radius is half its height, so the inner buttons land exactly
`Spacing.xs` inside the wrapper without either radius being written down.

### Size (`Theme.Size`)

The note window: `noteWindow 440×180` (the opening size and the resize floor), `noteTitlebar 52`,
`noteTitleInset 120`, `noteTrafficLightInset 20`, `noteEditorInset 16`, `noteEditorTopInset 6`,
`noteFooterHeight 28`, `bottomBarHeight 52`, `noteGlyph 16`, `noteEmptyGlyph 28`.

The switcher and the heading menu: `noteSwitcher 300×240`, `noteSearchHeight 34`,
`noteSwitcherEmptyHeight 96`, `noteSwitcherDrop 56`, `rowIcon 24`, `noteHeadingMenu` (220 wide, exactly
four rows tall), `menuRowHeight` (`menuIcon 20` + `md` × 2), `menuRowSpacing 1`.

Controls: `barButtonHeight 28`, `keyCap 18`, `compactKeyCap 15`, `heroKeyCap 22`.

The recorder: `shortcutRecorder 120`, `recorderKeyCap 16`, `shortcutPopover 132×82` (summed from its
bands), `shortcutPopoverLine 14`, `calloutCaretWidth 15`, `calloutCaretHeight 7`, `calloutCaretTip 2.5`.

Markdown drawing: `markdownListMarker 20`, `markdownQuoteBar 2`, `hairline 1`.

`settingsWidth 600`, `settingsLabelColumn 180`, `settingsSlider 180`, `settingsPicker 220`.

### Duration and motion

`Theme.Duration`: `enter 0.18` · `exit 0.12` · `tooltip 0.15` · `tooltipDelay 0.4` · `menuChevron 0.34`.
`Theme.MenuMotion.chevronAnimation` is the one shared curve; the heading chevron and the formatting
bar's expand and collapse use it. Those two and the recorder callout skip their animation under Reduce
Motion.

### Typography (`Theme.Typography`)

System text styles only — no fixed point sizes in views. `rowTitle` (`.body`), `rowTrailing`
(`.callout`), `bar` (`.callout` medium), `noteTitle` (`.headline`), `menuRow` (`.body`), `disclosure`
(`.caption` semibold), and the keycap trio `keyCap` (`.caption`), `compactKeyCap` (`.caption2`),
`heroKeyCap` (`.body`), plus `inlineCode` (`.body` monospaced) and `menuIcon` (`.body`). The named
exception is the optical SF Symbol treatment `menuSymbolSize 14` / `menuSymbolWeight .medium`.

The editor's fonts are not here: `NoteMarkdownTypography` owns them as `NSFont`s, because TextKit
takes those.

### Colors (`Theme.Colors`) — the alpha ramp

| Token | Dark | Light | Use |
| --- | --- | --- | --- |
| `panelScrim` | black 0.40 | white 0.55 | the panel scrim over the glass |
| `selection` | white 0.10 | black 0.09 | selected row, lit bar button, text selection |
| `rowHover` | white 0.05 | black 0.045 | mouse-hover fill (always fainter than selection) |
| `menuHover` | white 0.10 | black 0.09 | heading-menu row hover |
| `separator` | white 0.10 | black 0.12 | a Markdown rule |
| `controlSurface` | white 0.10 | black 0.08 | filled keycaps, inline code, the tooltip tile |
| `border` | white 0.20 | black 0.18 | outlined keycap borders, quote bars |
| `textSecondary` | white 0.60 | black 0.60 | secondary labels, quotes, list markers |
| `textTertiary` | white 0.40 | black 0.42 | placeholders, the count, revealed markers |
| `menuSymbol` | white 0.70 | black 0.70 | the heading menu's checkmark |
| `noteText` | white 0.90 | black 0.85 | note body text and caret |
| `cardFill` | white 0.05 | black 0.04 | code bands, the recorder field |
| `cardStroke` | white 0.10 | black 0.10 | the recorder field's border |
| `tooltipShadow` | black 0.18 | black 0.18 | the tooltip tile's shadow |

`panelScrim` is the ramp's inverse — it darkens the dark surface and lightens the light one — so it
is an `adaptive` pair, not a `ramp`. `destructive` is `Color.red` and adapts on its own.

Beyond these, `.secondary`/`.tertiary` foreground styles are fine for SF Symbols. Selection always
beats hover when a row or a button is both.

## Notes panel

Source: `Noto/Features/Notes/UI/`.

`NotesPanel` is a titled, resizable, non-activating panel. Its level is `.floating` only when Keep on
Top is on. AppKit draws the traffic
lights and the resize — with a transparent background, and it deliberately does not dismiss on
resign-key. `NotesView`'s root applies `panelScrim` → `GlassEffectView()` → one continuous `panel`
corner clip. The clip is larger than the theme frame's own corner, so it is what shows;
`invalidateShadow()` on every show recuts the shadow to match.

The title bar is a `noteTitlebar` (52-point) band that `NotesView` draws itself; `titleVisibility` is
`.hidden`, the real title bar is transparent with no separator, and the content ignores the safe area
so AppKit does not inset it a second time. The band is a drag region — an `NSView` that calls
`performDrag`, and on a double-click moves the window to the top-right — followed by
`NoteTitlebarActions`: three `BarButton`s (Create, Browse, Open Folder) in a `frosted(in: Capsule())`,
inset `md` from the trailing edge. The title is an overlay centred on the window, padded
`noteTitleInset` on both sides so it clears the lights and the capsule, and not hit-testable, so a
press on it reaches the drag region. `NotesWindowController.seatTrafficLights` moves the three lights
`noteTrafficLightInset` in and centres them in the drawn band, re-running whenever AppKit re-seats
them. The capsule's buttons carry `.help()` tooltips.

`NotesWindowController` preserves the user-owned size and AppKit autosaves the frame under
`"Notes Window"`; `windowWillResize` clamps to `noteWindow`, and only a title-bar double-click computes
a top-right target. The window shows exactly one content surface — the editor or the "No Notes" empty
state — and the character count is part of the editor surface, so it never appears without a note.

The editor is one native TextKit 2 surface. Its string is the canonical Markdown source, and Render
Markdown styles it in place. Notes type sits one system text style above the rest
of the app, because a note is for reading: body text is the title3 size in `noteText`, and headings 1
to 3 use the largeTitle, title1 and title2 sizes (bold, bold, semibold). Inline code is monospaced on
`controlSurface`, and links use the system link colour. Quotes and
checked tasks dim to `textSecondary`, and a checked task is struck through. Most markers show in
`textTertiary` on the caret's line and are hidden elsewhere. Bullets keep their rendered dot even under
the caret; revealed list markers stay `textSecondary`. Revealed non-bullet list and quote markers hang
left of their text, so the text does not move when the caret arrives, unless the marker is wider than
the slot. Empty list items keep body-sized invisible markers so their rows match filled items' height.

A layout fragment draws the block chrome. A code band fills `cardFill` with `menu` corners at its ends
and a `textTertiary` language label, inset by `lg`. A quote bar is `markdownQuoteBar` wide in `border`,
stepping `markdownQuoteBar + lg` per depth. A rule is a `hairline` of `separator`. List markers sit in
a slot per level, `markdownListMarker` grown in proportion to the body size. Bullets, numbers and
checkboxes are `textSecondary`; a done box is filled with the check cut out. Headings 1 and 2 get `xl`
space above, the rest `md`, and `xs` below; every list item gets `md` below. A table stays literal
source in the code-block font, and a wrapped row hangs `lg` under its first line. AppKit owns editing,
undo, selection, Find, and marked text.

Under the editor, the formatting bar takes a `bottomBarHeight` band while Render Markdown and Show
Formatting Bar are on, in place of the `noteFooterHeight` count footer. It is one row: the count is
plain text at the leading edge and the buttons sit in glass at the trailing edge. The capsule is the
title bar's recipe (`BarButton`s on a `frosted(in: Capsule())`), inset `md` from the trailing edge as
the title capsule is, with `xxs` between buttons and `sm` between groups. Each button is a compact
28-point square around a `noteGlyph` frame. Collapsing and expanding grows the buttons out of the round
button on `MenuMotion.chevronAnimation`, wrapped in an explicit `withAnimation` in the coordinator
because the chord changes that state outside any view's transaction, and skips the animation under
Reduce Motion. The band takes only the width it is offered, so the bar can never widen the note; the
count is in a `ViewThatFits` and gives way first. Lit buttons
use `BarButton.isSelected`; hovering shows a `Tooltip` with the name and shortcut. The glass is a
`background`, never a wrapper, and nothing clips the row, because either one swallows that tooltip. The
round button aligns its tooltip trailing and the heading button leading, so neither runs past the
window edge. The heading menu is a borderless child window like the switcher, `noteHeadingMenu` in
size, hung off the heading button's own reported frame and `xs` above it, on `menuPanel` glass; each
row is a checkmark slot, a title and outlined keycaps for its shortcut.

The switcher is its own glass panel hung `noteSwitcherDrop` below the title band, sized to its list up
to a 240-point ceiling and never resizing the note window. Its plain search field and
keyboard-navigable rows use the shared selection/hover ramp; rename and Trash remain row actions rather
than adding another toolbar or window. A row is `HStack(spacing: lg)`: a `noteGlyph` symbol in a
`rowIcon` slot, the title (`.body`, one line), then the two hover buttons. Hover state lives on the
row, not the list, so a mouse sweep repaints only the rows entering and leaving.

The switcher exposes activation, Rename, and Move to Trash as VoiceOver actions with the actual note
title. Its hover buttons are hidden from accessibility so those actions are announced once. See
[features/notes.md](features/notes.md).

## The overflow fade

Source: `Noto/DesignSystem/Scrolling/OverflowFade.swift`.

The edge treatment for a bounded list with nothing floating over it — the switcher. Attach with
`.overflowFade()` on the `ScrollView`, or pass `includingTop: true` for a list whose top edge can also
hide content.

- Bottom by default. The switcher's search row is a sibling above the list, not a bar over it.
- Fade band: 24 points with a single-stop curve by default; `includingTop` uses a progressive
  several-stop curve at both ends.
- No alpha floor. Each enabled edge eases with how much content is hidden there and clears
  completely once the list rests against it.

## Liquid Glass

Source: `Theme.swift` (`frosted(in:)`), `Noto/DesignSystem/GlassEffectView.swift`.

- `View.frosted(in:)` is `glassEffect(.regular.interactive(), in:)` — regular, interactive glass, so
  it follows the system Liquid Glass (clear ↔ tinted) setting. Used on the title-bar capsule, the
  formatting bar and the empty state's Create Note button. Retune it there, not per call site.
- The switcher, the heading menu and the recorder callout use plain `glassEffect(.regular)` on their
  root shape with no hand-tuned shadow — Tahoe glass carries its own elevation; adding a drop shadow
  reads heavy and non-native.
- `GlassEffectView` wraps `NSGlassEffectView` and is only ever a panel's backdrop, under `panelScrim`.
- A menu's size is fixed, never intrinsic, so it cannot jitter as its rows change: `noteHeadingMenu`
  is a token, and the switcher's height is computed from its content and capped.
- Menus are child windows, not `.contextMenu` or `NSMenu`, so they can extend past a short note
  window.

## Shared controls

`BarButton` (`Noto/DesignSystem/BarButton.swift`) is the bar control: a bare label at rest, a
`rowHover` fill on hover, `barButtonHeight 28`. Set `isSelected` and it fills with `selection` instead,
which beats hover; the formatting bar lights its buttons this way. Set `isCompact` for `sm` padding
instead of `md`: around a 16-point glyph frame that makes a 28-point square. `chrome` picks the hover
shape, `.capsule` by default or `.rounded` (`barControl`). Hover state lives inside it, so sweeping one
never re-renders its owner.

`KeyCapChip` (`Noto/DesignSystem/KeyCapChip.swift`) is one keycap: `.filled` on `controlSurface` or
`.outline` in `border`. `KeyCapChip.Scale` is `compact` / `standard` / `hero` — three tokenised sizes,
no stray frames. The heading menu uses outlined standard caps; the recorder callout uses hero caps and
a compact `esc`.

`Tooltip` (`Noto/DesignSystem/Tooltip.swift`) is `.tooltip(_:alignment:edge:)`: a label that appears
after `tooltipDelay`, fades in over `tooltip`, hangs above its control by default, never takes hits,
and draws outside its control's bounds. Pass `alignment: .leading` or `.trailing` for a control near a
window edge, and `nil` text to suppress it.

`SymbolImage` (`Noto/DesignSystem/SymbolImage.swift`) draws a system symbol at a point size, or a
bundled image of the same name when there is no such symbol.

### The shortcut recorder callout

`ShortcutRecorder` is a 120-point field showing only the binding. Recording is narrated by
`ShortcutRecorderPopover`, a small 132 × 82 callout above it: caps, one label line, an `esc` cap in the
top-left corner. Its fixed frame shows the prompt (`⌥ A` at half opacity, "Type a shortcut"), the live
held modifiers ("Add a key"), or a conflict (rejected caps + owner, orange).

- An ancestor draws it. The open recorder publishes its bounds via `ShortcutRecorderAnchorKey`;
  `.shortcutRecorderPopoverHost()` sits on `SettingsView`'s `Form`. An overlay on the row would be
  clipped by the form's scroll view.
- `shortcutPopover.width` is load-bearing. The callout centres on the recorder only while it fits
  either side of it; wider than that and the clamp kicks in and skews the caret.
- One glass shape. `CalloutShape` draws body and caret as a single path so `glassEffect` lenses them
  together. The caret is two straight edges meeting at an arc — a rounded-tip triangle, not a dome.
- Placement is pure. `CalloutPlacement` picks above-vs-below, clamps inside the container, and walks
  the caret so it still aims at the field.
- It enters over `enter` and leaves over `exit`, scaling from its caret edge; the layer keeps the last
  anchor while it animates away.
- `allowsHitTesting(false)`: clicks reach the capture session's mouse monitor; a click on the active
  recorder toggles it off, and a click elsewhere closes it.

Behaviour is in [features/hotkeys.md](features/hotkeys.md#recorder).

## The Settings window

Source: `Noto/Features/Settings/SettingsView.swift`,
`Noto/Features/Settings/SettingsWindowController.swift`, `Noto/Features/Settings/SettingsPane.swift`.

The Settings window follows the layout of the iA Writer settings window. It is a standard macOS
preferences window, and it does not use the look of the note window.

The window:

- It is a titled `NSWindow` that you can close and minimize. You cannot resize it.
- Its width is `settingsWidth`. Each pane sets the height.
- A toolbar in the `.preference` style shows one item for each `SettingsPane`: General, Editor and
  Shortcuts. Each item has a symbol and a label.
- The window title is the name of the selected pane.
- `SettingsView` reports the height of the pane after each layout. `SettingsWindowController.fit`
  then sets the window height with an animation. The top edge of the window does not move.
- Do not read the height from the hosting view after a pane change. It returns the height of the
  pane before the change.
- The pane is aligned to the top of the window, thus it does not move during the animation.
- Escape closes the window. The window opens at the centre of the screen.

A pane:

- `SettingsRow` is one row. Its label is right-aligned in a column of `settingsLabelColumn` width,
  and it ends with a colon. The controls are to the right of the label.
- A switch is a checkbox with its title to the right. Do not use the switch style.
- `SettingsCaption` is a secondary line below a control.
- A `Divider` separates groups of rows.
- A dependent control is disabled, not hidden. Show formatting bar is disabled while Render Markdown
  is off.

The panes:

| Pane | Rows |
| --- | --- |
| General | Window (Keep on top), Dock (Show in Dock), Notes folder (Choose…, Use Default, the path) |
| Editor | Text size, Text font, Heading font, CJK font, Code font, Defaults (Reset Fonts), Markdown (Render Markdown, Show formatting bar) |
| Shortcuts | One row for each `HotKeyCommand`, with a `ShortcutRecorder` and the subtitle of the command |

- Text size is a slider with a step of 1 point. The value shows to the right of the slider.
- A font row is a `Picker` of family names from `FontCatalog`. Its first item is the system choice.
  `FontCatalog` reads the families off the main thread, and the menus fill when it completes.
  The CJK menu shows only families with Han characters. The code menu shows only fixed-pitch families.
- If a stored family is not installed, its menu shows the name with "(Not Installed)".
- Each font menu has the width `settingsPicker`.
- A `ShortcutRecorder` is not in a `LabeledContent`, because that container stops the click.

## Rules for agents working on the UI

- Restyle from rendered screenshots, not guessed values. Compare over a light desktop, in both
  appearances.
- Don't add behavior that wasn't requested. A restyle changes appearance, not interaction — keep
  selection, scroll, dismiss and focus flows exactly as they are unless the task is about them.
- New tokens go in `Theme`, referenced everywhere. No magic numbers in views.
- Keep the shared grammar shared. If you change the bar button, the keycap or the selection/hover
  precedence, change it for every surface — divergence is the bug, not the feature.
- Build and verify with the real toolchain (see [development.md](development.md)); a design change that
  doesn't compile under Swift 6 mode isn't done.
