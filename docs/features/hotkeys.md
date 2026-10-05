# Hotkeys

Four global shortcuts, in-house, zero dependencies. `Noto/Features/HotKeys/` holds:

- `HotKeyCommand` (`Model/`) — the four commands a shortcut can run: `showNotes`, `createNote`,
  `searchNotes` and `toggleKeepOnTop`, each with the title and subtitle its Settings row shows.
- `KeyShortcut` (`Service/`) — a Sendable value, Carbon key code plus modifiers, with layout-aware
  glyphs through `ASCIIKeyboardLayout` (`UCKeyTranslate`).
- `HotKeyCenter` (`Service/`) — the Carbon `RegisterEventHotKey` layer, pausable.
- `HotKeyManager` (`Service/`) — which shortcuts exist and what they run: it reads and writes
  `NotoSettings.shortcuts`, looks up conflicts, registers with the center, and owns the recording state.
- `ShortcutCaptureSession` (`Service/`) — the local event monitors of the one active recording.
- `ShortcutRecorder`, `ShortcutRecorderPopover`, `CalloutShape`, `CalloutPlacement` (`UI/`) — the
  Settings field and the callout that narrates a recording.

`AppCore.start()` calls `HotKeyManager.start`, handing it `AppCore.run(_:)`; a fired shortcut lands
there, the same funnel the menu bar item uses.

## Invariants

- There are exactly four bindable commands, and none has a default. A command absent from
  `NotoSettings.shortcuts` is unbound and registers nothing.
- `HotKeyCommand`'s raw value is the persisted key and the `HotKeyCenter` registration id, so the two
  cannot drift. Renaming a case orphans its stored shortcut.
- Only key combos are bindable: one key plus at least one of ⌘, ⌥, ⌃ or 🌐, or a bare function key
  (F1 to F20). ⇧ alone does not qualify. There are no modifier-only shortcuts, no double-taps and no
  Hyper key, so there is no event tap and Noto needs no Accessibility permission.
- Conflicts are checked among Noto's own four commands only. A combo another app or the system
  already holds still records; Carbon refuses the registration, `HotKeyCenter` logs it, and the
  binding stays visible but does not fire.
- `KeyShortcut`'s hand-written `init(from:)` is a correctness seam, not a format one: it routes every
  decode through the initializer that masks device modifier bits off, so equality cannot be thrown.
- While a recorder is listening every hotkey is soft-unregistered (`HotKeyCenter.isPaused`), so the
  combo being typed is captured instead of fired.
- Carbon is the engine because nothing modern registers a system-wide chord. The dispatcher enters
  through an explicit `@MainActor` callback, and the raw event is decoded to a plain `EventHotKeyID`
  before it reaches the center. Registrations carry the FourCC signature `NOTO`.
- `KeyShortcut` lives in `Service/`, not `Model/`: it imports AppKit for `NSEvent.ModifierFlags`.

## Dispatch

| Command | Runs |
| --- | --- |
| `showNotes` | `NotesCoordinator.toggle()` — shows the note window, or hides a visible one |
| `createNote` | `NotesCoordinator.createNote()` |
| `searchNotes` | `NotesCoordinator.searchNotes()` |
| `toggleKeepOnTop` | `NotesCoordinator.toggleKeepOnTop()`. It changes `NotoSettings.keepsOnTop`. |

`HotKeyManager.setShortcut(_:for:)` writes the setting and re-registers that one command; passing nil
unbinds it. `HotKeyCenter.register` drops any previous registration under the same id first, so no
combo leaks.

## Persistence

`NotoSettings.shortcuts` is a `[HotKeyCommand: KeyShortcut]`, stored as one JSON object (encoded
`Data`) under the UserDefaults key `hotKeys`. Show Notes bound to ⌥⌘N reads:

```json
{ "showNotes": { "carbonKeyCode": 45, "carbonModifiers": 2304 } }
```

The object is keyed by `HotKeyCommand` raw value and holds only the bound commands. It is written when
the dictionary changes; on load, an entry whose key names no current command is dropped. `KeyShortcut`
keeps a hand-written `init(from:)` so every decode runs through the masking initializer; encoding is
the synthesised one. Like every preference the value is keyed by bundle id, which Debug and Release share.

## Recorder

`ShortcutRecorder` (`Noto/Features/HotKeys/UI/ShortcutRecorder.swift`) is deliberately not a focusable
control: the active recorder is `HotKeyManager.recordingCommand` state, and keys are captured by local
`NSEvent` monitors while the center is paused. Recording needs no event tap and no permission.

Setting `recordingCommand` is what starts and stops the capture, so there is exactly one
`ShortcutCaptureSession` for the app rather than one per row — which is what lets the callout above the
field render the live state from outside the row that opened it. The field itself only ever shows the
binding, or "Record Hotkey" / "Listening…" when there is none; the prompt, the held modifiers and the
conflict message all live in the callout. See [ui.md](../ui.md#the-shortcut-recorder-callout).

What a recording does with each event:

- A bindable combo is saved and ends the recording.
- A combo another Noto command holds is rejected: the callout shows the caps and the owner's title in
  orange for 1.5 seconds, and the recording continues.
- Anything that is not bindable, such as a bare letter, is swallowed and the recording continues.
- Bare Escape cancels. Bare Delete or Forward Delete clears the existing shortcut and ends the
  recording.
- A click on the active field toggles it off; a click anywhere else ends the recording and travels on,
  so one click can move to another row.
- The window resigning key cancels, because local monitors go quiet there and the hotkeys must unpause.
- Globe is tracked from the physical `kVK_Function` key code, not the fn flag, because F-keys also
  carry that flag.

A bound field shows its keycaps in canonical 🌐⌃⌥⇧⌘ order with the key glyph last, and a clear button
on hover.

## Verification

No harness covers this folder. The Hotkeys section of the manual sweep in
[testing.md](../testing.md#hotkeys) is the check.
