# UI and design system

The design system of Noto, as built. Every rule here maps to code in `Noto/`.
`Noto/DesignSystem/Theme.swift` is the only design-token source. Read this before you touch a view
body, a `Theme` value or the panel chrome.

## The look

The note window is a panel. Its surface is the OS glass under a 40% black scrim. There is no gray
chrome. Everything on that surface is white at a fixed alpha ramp. There are no hard-edged bars or
dividers: the title band and the bottom band are regions of the same surface. The floating controls
(the title-bar capsule, the formatting bar, the switcher, the bar menus, the recorder callout) are
Liquid Glass.

That describes Dark, which is the design. Light is the same design with the ink inverted: a white
scrim over the same glass, and a black-alpha ramp at matched stops. Geometry, type, motion and state
do not change between them.

The Settings window does not share this look. It is stock macOS.

## Invariants

These rules keep the look. Preserve them unless the task is to change them.

- Dark is the baseline. Every `Theme.Colors` token resolves per appearance. Retune a light branch
  freely. Change a dark one only when the task is to change Dark. Noto sets no appearance; every
  window follows macOS.
- A new colour goes through `Theme.Colors.ramp(dark:light:)` (an alpha that inverts) or
  `adaptive(dark:light:)` (two explicit `NSColor`s). Never a bare `Color.white.opacity(…)` in a view:
  it disappears in Light.
- No grays and no opaque fills on the surface. Use `Theme.Colors.*`, not `.gray` or
  `NSColor.windowBackgroundColor`. `Tooltip`'s tile is the one opaque fill, because a label must stay
  readable over anything.
- The `OverflowFade` gradient is mask luminance, not colour. It stays black in both appearances.
- A colour the editor draws with is a dynamic `NSColor`. `NoteEditorTheme` hands each `Theme` token
  to MDTextKit as an `NSColor`, and `NoteTextView` restyles on an appearance change, because an
  attachment caches its drawing.
- The panel corner is clipped once, at the root. `NotesView.body` ends with `.background(panelScrim)`,
  then `.background(GlassEffectView())`, then `.clipShape(RoundedRectangle(26, .continuous))`. Keep
  that order.
- Test over a light desktop. Transparency and corner bugs show only over bright wallpaper.
- The formatting bar's hover labels are Noto's `tooltip`, never `.help()`. The label carries the
  shortcut, aligns against a window edge and draws outside the capsule. The title-bar capsule and the
  switcher rows use `.help()`.
- Glass is for floating controls. The note window's surface is the scrim-over-glass recipe, never
  `.glassEffect` on the root.
- Notes asks its questions with system alerts, through `NotesDialogs`. No view builds one.

## Tokens

`Theme` is the single source. Never hardcode a spacing, radius, size or colour that has a token. Add a
token instead of a magic number.

`Noto/DesignSystem/InterfaceMetrics.swift` stores a scale and derives its values from `Theme`. Noto
has no interface-size setting, so the environment's `\.metrics` is always `.standard`, which is
`Theme` verbatim. `BarButton`, `KeyCapChip` and `Tooltip` read `@Environment(\.metrics)`. A new
shared control in `DesignSystem/` does the same for the tokens `InterfaceMetrics` carries: `spacing`
`xxs` to `md`, `radius` `barControl`, `keyCap` and `tooltip`, `size` `barButtonHeight` and the three
keycap sizes, and the three keycap fonts.

### Spacing

`xxs 2` · `xs 4` · `sm 6` · `md 8` · `lg 10` · `xl 12` · `xxl 20`

`xxs` is the gap between adjacent keycap chips and between bar buttons in one group.

### Radius

`panel 26` · `menuPanel 16` · `row 10` · `menuRow 10` · `barControl 8` · `tooltip 8` · `keyCap 6` ·
`menu 6` · `recorderKeyCap 4`

`panel` is the note window. `menuPanel` is the switcher, a bar menu and the recorder callout. `row`
is a switcher row's fill and `menuRow` a menu row's hover. `menu` is the small-control corner: the
recorder field and the ends of a code band.

Always `RoundedRectangle(cornerRadius:, style: .continuous)`, never `.circular`. Where two rounded
corners sit adjacent, the inner radius is the outer radius minus the gap: inside a menu, `menuPanel
16` − `sm 6` = `menuRow 10`.

The title-bar capsule and the formatting bar are `Capsule`s, and so are the hover fills of their
buttons. A capsule's radius is half its height, so the inner buttons land `xs` inside the wrapper
without a written radius.

### Size

- The note window: `noteWindow 440×180` (the opening size and the height floor),
  `noteWindowMaxHeight 860`, `noteTitlebar 52`, `noteTitleInset 120`, `noteTrafficLightInset 20`,
  `noteSideMargin 28`, `noteEditorTopInset 6`, `noteBandInset 16`, `noteFooterHeight 28`,
  `bottomBarHeight 52`, `noteGlyph 16`, `noteEmptyGlyph 28`.
- The switcher and the bar menus: `noteSwitcher 300×240`, `noteSearchHeight 34`,
  `noteSwitcherEmptyHeight 96`, `noteSwitcherDrop 56`, `rowIcon 24`, `noteBarMenu(rows:)` (220 wide,
  exactly its rows tall), `menuRowHeight` (`menuIcon 20` + `md` × 2), `menuRowSpacing 1`.
- Controls: `barButtonHeight 28`, `keyCap 18`, `compactKeyCap 15`, `heroKeyCap 22`, `hairline 1`.
- The recorder: `shortcutRecorder 120`, `recorderKeyCap 16`, `shortcutPopover 132×82` (summed from its
  bands), `shortcutPopoverLine 14`, `calloutCaretWidth 15`, `calloutCaretHeight 7`,
  `calloutCaretTip 2.5`.
- Settings: `settingsWidth 600`, `settingsLabelColumn 180`, `settingsSlider 180`, `settingsPicker 220`.

### Duration and motion

`enter 0.18` · `exit 0.12` · `tooltip 0.15` · `tooltipDelay 0.4` · `menuChevron 0.34`

`Theme.MenuMotion.chevronAnimation` is the one shared curve. The menu chevrons and the formatting
bar's expand and collapse use it. Those and the recorder callout skip their animation under Reduce
Motion.

### Typography

System text styles only; no fixed point sizes in views. `rowTitle` (`.body`), `rowTrailing`
(`.callout`), `bar` (`.callout` medium), `noteTitle` (`.headline`), `menuRow` (`.body`), `disclosure`
(`.caption` semibold), the keycap trio `keyCap` (`.caption`), `compactKeyCap` (`.caption2`) and
`heroKeyCap` (`.body`), `inlineCode` (`.body` monospaced) and `menuIcon` (`.body`). The one exception
is the SF Symbol treatment `menuSymbolSize 14` with `menuSymbolWeight .medium`.

The editor's fonts are not here. `NoteEditorTheme` maps the font settings onto MDTextKit's theme
overrides, and MDTextKit builds the `NSFont`s.

### Colours

| Token | Dark | Light | Use |
| --- | --- | --- | --- |
| `panelScrim` | black 0.40 | white 0.55 | the panel scrim over the glass |
| `selection` | white 0.10 | black 0.09 | a selected row, a lit bar button |
| `rowHover` | white 0.05 | black 0.045 | the mouse-hover fill, always fainter than selection |
| `menuHover` | white 0.10 | black 0.09 | a menu row's hover |
| `separator` | white 0.10 | black 0.12 | a Markdown rule |
| `controlSurface` | white 0.10 | black 0.08 | filled keycaps, checkboxes, the tooltip tile |
| `border` | white 0.20 | black 0.18 | outlined keycaps, quote bars, code band and table borders |
| `textSecondary` | white 0.60 | black 0.60 | secondary labels, quotes, list markers |
| `textTertiary` | white 0.40 | black 0.42 | placeholders, the count, revealed markers |
| `menuSymbol` | white 0.70 | black 0.70 | a menu row's checkmark |
| `noteText` | white 0.90 | black 0.85 | note body text and the caret |
| `cardFill` | white 0.05 | black 0.04 | code bands, inline code, table header and alternate rows, the recorder field |
| `cardStroke` | white 0.10 | black 0.10 | the recorder field's border |
| `tooltipShadow` | black 0.18 | black 0.18 | the tooltip tile's shadow |
| `highlight` | yellow 0.35 | yellow 0.60 | the default background of a `==highlight==` span |
| `tintBlue`, `tintGreen`, `tintPurple`, `tintYellow`, `tintRed` | opaque pairs | opaque pairs | the five callout kinds and the named highlighter colours |

`panelScrim` is the ramp's inverse, so it is an `adaptive` pair. `highlight` and each tint are
`adaptive` pairs too. `destructive` is `Color.red` and adapts on its own. The editor's selection, links
and underlines use the accent colour, not a token; see [notes.md](features/notes.md#accent-colour).

`.secondary` and `.tertiary` foreground styles are fine for SF Symbols. Selection beats hover when a
row or a button is both.

## The note window

Source: `Noto/Features/Notes/UI/`.

### The panel

`NotesPanel` is a titled, resizable, non-activating panel. Its level is `.floating` only with Keep on
Top on. AppKit draws the traffic lights and the resize, with a transparent background, and the panel
does not dismiss on resign-key. `NotesView`'s root applies `panelScrim`, then `GlassEffectView()`,
then one continuous `panel` corner clip. That clip is larger than the frame's own corner, so it is
what shows. `invalidateShadow()` on every show recuts the shadow.

`NotesWindowController` fits the height to the editor on each edit, and AppKit autosaves the frame
under `Notes Window`. `windowWillResize` clamps to `noteWindow`. Only a title-bar double-click computes
a top-right target. The window shows one content surface: the editor, or the "No Notes" empty state.
The character count is part of the editor surface, so it never shows without a note.

### The title bar

The title bar is a `noteTitlebar` (52-point) band that `NotesView` draws. `titleVisibility` is
`.hidden`, the real title bar is transparent with no separator, and the content ignores the safe
area so AppKit does not inset it again. The band is a drag region: an `NSView` that calls
`performDrag`, and on a double-click moves the window to the top-right. After it comes
`NoteTitlebarActions`: three `BarButton`s (Create, Browse, Open Folder) in a `frosted(in: Capsule())`,
inset `md` from the trailing edge. The title is an overlay centred on the window, padded
`noteTitleInset` on both sides, and not hit-testable, so a press on it reaches the drag region.
`NotesWindowController.seatTrafficLights` moves the three lights `noteTrafficLightInset` in and
centres them in the band, each time AppKit re-seats them.

### The editor

The editor is one MDTextKit surface, a TextKit 1 `NSTextView`. Its Markdown is the source, and
MDTextKit styles it in place. Note text sits one system text style above the rest of the app: body
text is the `title3` size in `noteText`, headings scale from it in the heading font's bold face, and
the line height is 1.3 times the font size.

- Inline code is monospaced on `cardFill`. A highlight draws `highlight` or the chosen colour.
- Links, underlines and the selection use the accent colour. A link has a link icon after its label.
- A checked task dims to `textSecondary`. Inline markers show in `textTertiary` while the caret is in
  their construct, and are hidden elsewhere.
- A code band fills `cardFill` with a `border` edge. A quote bar is `border`, one per depth. A callout
  is a box in its kind's tint. A rule is a `separator` line across the column.
- A bullet is a `textSecondary` dot, ring or diamond by depth. A number stays text in
  `textSecondary`. A checkbox is a rounded `controlSurface` box with a `noteText` check when done.
- A table is a grid with `border` lines. Its header and every second row are `cardFill`; the rows
  between are the page, as in Bear.
- A heading's `#` marks are an attachment that shows three bars and the level while the caret is on
  the line. The attachment hangs in the side margin, at its centre. The caret cannot go before it.
- The side margin is `noteSideMargin` on the left and on the right. The text view adds no horizontal
  inset. At a large text size, MDTextKit makes the margin wider so that the heading marker fits.

### The formatting bar

With Show Formatting Bar on, the bar takes a `bottomBarHeight` band under the editor, in place of the
`noteFooterHeight` count footer. It is one row: the count as plain text at the leading edge, the
buttons in glass at the trailing edge.

- The capsule is the title bar's recipe: `BarButton`s on a `frosted(in: Capsule())`, inset `md` from
  the trailing edge, `xxs` between buttons and `sm` between groups. Each button is a compact 28-point
  square around a `noteGlyph` frame. A menu button adds a `disclosure` chevron.
- Expand and collapse grow the buttons out of the round button on `MenuMotion.chevronAnimation`, in an
  explicit `withAnimation` in the coordinator, because the chord changes the state outside a view's
  transaction. Reduce Motion skips it.
- The band takes only the width it is offered, so the bar never widens the note. The count is in a
  `ViewThatFits` and gives way first.
- A lit button uses `BarButton.isSelected`. Hover shows a `Tooltip` with the name and shortcut. The
  glass is a `background`, never a wrapper, and nothing clips the row: either one swallows the
  tooltip. The round button aligns its tooltip trailing, the Heading button leading and the More
  button trailing, so none runs past the window edge.
- A bar menu (Heading, List or More) is a borderless child window, `noteBarMenu(rows:)` in size, hung
  off its button's reported frame and `xs` above it, on `menuPanel` glass. Each row is a checkmark
  slot, a title and outlined keycaps for its shortcut. A menu that would leave the window's trailing
  edge moves left to stay `xs` inside it.

### The switcher

The switcher is a glass panel hung `noteSwitcherDrop` below the title band, sized to its list up to a
240-point ceiling, and it never resizes the note window. Its plain search field and keyboard rows use
the shared selection and hover ramp. Rename and Trash are row actions. A row is `HStack(spacing: lg)`:
a `noteGlyph` symbol in a `rowIcon` slot, the title (`.body`, one line), then the two hover buttons.
Hover state lives on the row, so a mouse sweep repaints only the rows it enters and leaves.

The switcher exposes activation, Rename and Move to Trash as VoiceOver actions with the note title.
Its hover buttons are hidden from accessibility, so those actions are announced once.

## The overflow fade

Source: `Noto/DesignSystem/Scrolling/OverflowFade.swift`.

The edge treatment for a bounded list with nothing over it: the switcher. Attach `.overflowFade()` to
the `ScrollView`, or pass `includingTop: true` for a list whose top edge can hide content.

- Bottom by default. The switcher's search row is a sibling above the list, not a bar over it.
- The fade band is 24 points with a single-stop curve. `includingTop` uses a several-stop curve at
  both ends.
- No alpha floor. Each enabled edge eases with the hidden content and clears once the list rests
  against it.

## Liquid Glass

Source: `Theme.swift` (`frosted(in:)`) and `Noto/DesignSystem/GlassEffectView.swift`.

- `View.frosted(in:)` is `glassEffect(.regular.interactive(), in:)`. It follows the system Liquid
  Glass setting. The title-bar capsule, the formatting bar and the empty state's Create Note button
  use it. Retune it there, not per call site.
- The switcher, a bar menu and the recorder callout use plain `glassEffect(.regular)` on their root
  shape, with no hand-tuned shadow. Tahoe glass carries its own elevation.
- `GlassEffectView` wraps `NSGlassEffectView`. It is only a panel's backdrop, under `panelScrim`.
- A menu's size is fixed, never intrinsic, so it cannot jitter as its rows change. `noteBarMenu(rows:)`
  gives a bar menu's size; the switcher computes its height from its content and caps it.
- Menus are child windows, not `.contextMenu` or `NSMenu`, so they can extend past a short note window.

## Shared controls

`BarButton` (`Noto/DesignSystem/BarButton.swift`) is the bar control: a bare label at rest, a
`rowHover` fill on hover, `barButtonHeight 28`. `isSelected` fills it with `selection` instead, which
beats hover. `isCompact` gives `sm` padding instead of `md`: around a 16-point glyph frame that makes a
28-point square. `chrome` picks the hover shape, `.capsule` by default or `.rounded` (`barControl`).
Hover state lives inside it, so a sweep never re-renders its owner.

`KeyCapChip` (`Noto/DesignSystem/KeyCapChip.swift`) is one keycap: `.filled` on `controlSurface` or
`.outline` in `border`. `KeyCapChip.Scale` is `compact`, `standard` or `hero`. A bar menu uses outlined
standard caps. The recorder callout uses hero caps and a compact `esc`.

`Tooltip` (`Noto/DesignSystem/Tooltip.swift`) is `.tooltip(_:alignment:edge:)`: a label that appears
after `tooltipDelay`, fades in over `tooltip`, hangs above its control, never takes hits, and draws
outside its control's bounds. Pass `alignment: .leading` or `.trailing` for a control near a window
edge, and `nil` text to suppress it.

`SymbolImage` (`Noto/DesignSystem/SymbolImage.swift`) draws a system symbol at a point size, or a
bundled image of the same name when there is no such symbol.

### The shortcut recorder callout

`ShortcutRecorder` is a 120-point field that shows only the binding. `ShortcutRecorderPopover`
narrates a recording in a 132 × 82 callout above it: caps, one label line, an `esc` cap in the
top-left corner. Its fixed frame shows the prompt (`⌥ A` at half opacity, "Type a shortcut"), the held
modifiers ("Add a key"), or a conflict (the rejected caps and the owner, in orange).

- An ancestor draws it. The open recorder publishes its bounds through `ShortcutRecorderAnchorKey`,
  and `.shortcutRecorderPopoverHost()` sits on `SettingsView`'s `Form`. An overlay on the row would be
  clipped by the form's scroll view.
- `shortcutPopover.width` matters. The callout centres on the recorder only while it fits on either
  side; past that, the clamp skews the caret.
- One glass shape. `CalloutShape` draws body and caret as one path, so `glassEffect` lenses them
  together. The caret is two straight edges that meet at an arc.
- Placement is pure. `CalloutPlacement` picks above or below, clamps inside the container, and walks
  the caret so it still aims at the field.
- It enters over `enter` and leaves over `exit`, scaled from its caret edge. The layer keeps the last
  anchor while it animates away.
- `allowsHitTesting(false)`: clicks reach the capture session's mouse monitor. A click on the active
  recorder toggles it off; a click elsewhere closes it.

The behaviour is in [hotkeys.md](features/hotkeys.md#recorder).

## The Settings window

Source: `Noto/Features/Settings/`.

The Settings window follows the layout of the iA Writer settings window. It is a standard macOS
preferences window.

The window:

- A titled `NSWindow` that you can close and minimize, not resize.
- Its width is `settingsWidth`. Each pane sets the height.
- A toolbar in the `.preference` style shows one item per `SettingsPane`: General, Editor and
  Shortcuts, each with a symbol and a label. The window title is the selected pane's name.
- `SettingsView` reports the pane's height after each layout. `SettingsWindowController.fit` sets the
  window height with an animation. The top edge does not move. Do not read the height from the hosting
  view after a pane change: it returns the previous pane's height.
- The pane is aligned to the top of the window, so it does not move during the animation.
- Escape closes the window. It opens at the centre of the screen.

A pane:

- `SettingsRow` is one row. Its label is right-aligned in a `settingsLabelColumn` column and ends with
  a colon. The controls are to its right.
- A switch is a checkbox with its title to the right. Do not use the switch style.
- `SettingsCaption` is a secondary line below a control.
- A `Divider` separates groups of rows.
- A dependent control is disabled, not hidden. Reset Fonts is disabled while no font is set.

The panes:

| Pane | Rows |
| --- | --- |
| General | Window (Keep on top), Dock (Show in Dock), Updates (Check for updates automatically, Check Now, the version), Notes folder (Choose…, Use Default, the path) |
| Editor | Text size, Text font, Heading font, CJK font, Code font, Defaults (Reset Fonts), Highlight (a colour well, Use Default), Accent (a colour well, Use Default), Formatting bar (Show formatting bar) |
| Shortcuts | One row per `HotKeyCommand`, with a `ShortcutRecorder` and the command's subtitle |

- Text size is a slider with a step of 1 point. The value shows to the right of the slider.
- A font row is a `Picker` of family names from `FontCatalog`, `settingsPicker` wide. Its first item is
  the system choice. `FontCatalog` reads the families off the main thread, and the menus fill when it
  completes. The CJK menu shows only families with Han characters. The code menu shows only
  fixed-pitch families. A stored family that is not installed shows with "(Not Installed)".
- The Highlight row is a `ColorPicker` with opacity. The Accent row is one without. Each shows the
  default colour until the user picks one, and Use Default appears only while a colour is set.
- A `ShortcutRecorder` is not in a `LabeledContent`, because that container stops the click.

## Rules for UI work

- Restyle from rendered screenshots, not guessed values. Compare over a light desktop, in both
  appearances.
- Do not add behaviour that was not requested. A restyle changes appearance, not interaction.
- New tokens go in `Theme`. No magic numbers in views.
- Keep the shared grammar shared. If you change the bar button, the keycap or the selection and hover
  precedence, change it for every surface.
- Build with the real toolchain. A design change that does not compile in Swift 6 mode is not done.
