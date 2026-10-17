# Version history

Each note has earlier versions. A version is the whole note: `text.md` and the `assets` folder. The
system version store (`NSFileVersion`) keeps the versions, and the system version browser shows them:
the Time Machine-like view of "Browse All Versions" that document apps such as iA Writer use. Noto
keeps no copy of its own and draws no history list.

The measurements behind this design are in [research/version-history.md](../research/version-history.md).

## Invariants

- A note is a `.noto` file package. Only a file or a package keeps versions in iCloud, so a note is
  never a plain folder. See [notes.md](notes.md#storage).
- A version is a version of the package, never of `text.md` alone. A restore brings back the text and
  the images together.
- Noto never removes a version. The system removes old versions by its own rules. The conflict code
  marks a conflict version resolved and keeps it.
- Before a change the user cannot undo, a version comes first: Noto adds one before it deletes
  images, and the system adds one before a restore. If Noto cannot add its version, it does not
  delete.
- A restore cannot lose the draft. The draft saves first. If it does not save, the browser does not
  open.
- Noto deletes only the images that the user's own edits dropped. An image that iCloud, Finder or
  another app put in `assets` stays until the user's text names it and then drops it.

## Where the versions come from

| Source | When | Kept |
| --- | --- | --- |
| iCloud server | iCloud makes one for each upload of a note in iCloud. Quick saves join, so it is at most about one each 10 seconds | on the iCloud server |
| Noto, this Mac | `NotesStore.write`, at the first save of an editing session and then at most each `NotesStore.snapshotInterval` (10 minutes), only for a note outside iCloud | on this Mac |
| Noto, this Mac | `NotesRepository.removeDroppedAssets`, before it deletes images | on this Mac |
| The system, this Mac | the version browser's Restore, before it replaces the note | on this Mac |

The first save of a session keeps the note as it was opened. A new, empty note gets no version.
Noto adds no version that the newest local version already holds: the same `text.md` and the same
files in `assets`, byte for byte (`NotesRepository.holdSameNote`). A failed version before a save is
logged; the save continues.

An edit that comes back to the text on disk writes nothing. In iCloud a write uploads the note, and
the server keeps each upload as a version, so a write of the same text would add a version with no
change.

The version store is per volume. A volume that keeps no versions, such as a network volume, makes
`addOfItem` fail; the failure is logged. The browser then shows no earlier versions.

The browser lists the server versions that this Mac has not downloaded too. It shows each one
with a Load Version button until it downloads.

## Image cleanup

The editor keeps an image file while the user edits, because ⌘Z can bring its Markdown back. The
cleanup runs when the editing session ends: a switch to another note, Create, a change of the notes
folder, and quit. A hide does not end the session, because the undo history stays.

`NotesStore` records the session:

- `sessionSources`: the text the session opened, and the text of each reload or restore of the same
  note.
- `sessionImports`: the file names that `importAssets` copied in during the session.

`NotesRepository.removeDroppedAssets` then runs as the one write in flight, after the draft is
saved. In one coordinated write on the package it reads `text.md` from disk. A file in `assets` goes
when a session text or the imports name it and the disk text does not. `NoteAssets.isReferenced`
decides "names it". It matches the path as written, percent-encoded and decoded, with no regard to
case or Unicode normalization. A path in a code block counts. If one file goes, a version of the
package comes first.

A package that iCloud has not downloaded is skipped.

## The version browser

Three controls open it: the clock button in the title-bar capsule, ⌥⌘Y in the note window or the
main menu, and Version History… in the menu bar item. Without a visible window, the command shows the
window first.

The browser belongs to `NSDocument`, and Noto is not document based. So `NoteVersionDocument`, an
`NSDocument` subclass, stands for the note while the browser is open:

1. `NotesCoordinator.browseHistory` saves the draft. For a note in iCloud,
   `NotesStore.downloadRecentServerVersions` then downloads the server versions of the last
   `serverVersionPeriod` (3 days), newest first, for at most `serverVersionWait` (10 s). The browser
   shows a downloaded version at once; an older one, or one the wait did not reach, shows the
   browser's Load Version button. A failed download is logged and skipped. A second press during
   this wait does nothing. Then it opens a `NoteVersionDocument` on the active package, with the
   frame of the note window.
2. The note window hides, the document window shows in its place, and `browseVersions(_:)` opens the
   browser.
3. The browser opens each earlier version as another `NoteVersionDocument` and shows its window.
   `NoteVersionPreview` renders the Markdown read-only, with the editor's theme and fonts
   (`NoteVersionDocument.style`), and resolves images against that version's own package.
4. Done closes the browser. Restore replaces the package with the version; the system first adds
   the note as it was as a version, so a restore can be undone with the browser too. The document
   reads the package again, and its window shows the restored note.
5. At `NSWindow.didExitVersionBrowserNotification`, `finishHistory` closes the document, reloads the
   store, and shows the note window again. The editor is clean, so the reload applies the restored
   text; the source, the base and the editor epoch change together, and the next save keeps no
   conflict copy.

While the browser is open, Show, Create, Search and the hide toggle do nothing.

Contracts of `NoteVersionDocument`:

- `Info.plist` declares it as the `NSDocumentClass` of `app.huanan.noto.note`, role Editor, rank
  None. Without that declaration the browser cannot open a version ("Unable to open version"). With
  rank None, Finder never picks Noto to open a `.noto`; an Open With shows the notes window.
- It never writes. Nothing edits it, so AppKit has no reason to save; `fileWrapper(ofType:)` hands
  back the package as it is on disk.
- Its windows are not restorable, and `applicationShouldOpenUntitledFile` returns false, so a version
  window never comes back at launch and AppKit never makes an untitled note.
- `displayName` drops `.noto`, so each window shows the note's title.

## Logging

`Logger.notes` records each version Noto adds, each image cleanup and each open of the browser.
`Logger.sync` records how many recent server versions downloaded, and each download that failed.
Titles are private.

## Verification

`notes-test` covers the snapshot of the whole package, a rename, the image cleanup, the reference
match and the store's version schedule. It works in a temporary folder, so it never asks iCloud. The
browser, the restore and the server versions are manual; see
[testing.md](../testing.md#version-history).
