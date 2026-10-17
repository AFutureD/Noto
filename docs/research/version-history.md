# Research: version history

This record keeps what we measured on 2026-10-17 before we added version history. It tells why a
note is a file package and which system service keeps the versions. Each fact has its test. The
feature itself is in [history.md](../features/history.md).

Machine: macOS 27, APFS, one Mac signed in to iCloud. All tests used scratch items. iCloud tests used
a scratch folder at the root of the `iCloud.app.huanan.noto` container, not `Documents`, so Noto did
not show them. The `.noto` type came from a test app that declared it; the test removed that app
after each run.

## The questions

1. How does iA Writer give its documents a version history?
2. Can the system keep versions of a whole note: `text.md` and the `assets` folder together?
3. Does that work in iCloud, and on other devices?
4. How many versions does iCloud keep while the user types?
5. What must change in Noto for a package?
6. Can Noto use the system version browser?

## 1. iA Writer

iA Writer 8.0.9 uses the version service of `NSDocument`. It writes no version code of its own on the Mac.

| Fact | Evidence |
| --- | --- |
| The document class is `IALibraryDocument`, a subclass of `IADocument`, a subclass of `NSDocument` | `otool -oV` on the app and on `Kit.framework` |
| `+[IADocument autosavesInPlace]` returns `YES`. That turns on autosave in place and the versions browser | disassembly: `mov w0, #0x1; ret` |
| No binary calls `addVersionOfItemAtURL:` | `strings` on each binary |
| `IAFileVersionBrowser` in `FoundationAdditions.framework` reads local, iCloud and conflict versions. The Mac app does not link to it | `nm -u` finds no reference in the app or in `Kit` |
| A document is one plain text file. The app declares no package type and no TextBundle | `Info.plist`: the only editor type is `public.text` |
| Images are separate files. A version does not include them. iA Writer does not delete images | as above |
| The library is in the iA Writer iCloud container. `NSMetadataQuery` finds the files. `NSFilePresenter` reports outside changes | symbols `IAMetadataQueryLibraryObserver`, `-[IADocument presentedItemDidChange]` |

Result: iA Writer versions one text file. It has no answer for a note that is a folder with images.

Apple documents the behaviour in the *Document-Based App Programming Guide for Mac*, chapter
"Standard Behaviors": "Documents Are Automatically Saved" and "Users Can Browse Document Versions".

## 2. Versions of a whole note

`NSFileVersion.addOfItem(at:withContentsOf:options:)` (macOS only) adds a version to the version store
of the volume, `/.DocumentRevisions-V100`. `otherVersionsOfItem(at:)` lists them.
`replaceItem(at:options:)` restores one.

Test: make v1 (`text.md` = v1, `assets/a.png`). Add a version. Make v2 (v2, remove `a.png`, add
`b.png`). Add a version. Make v3 (v3, add `c.png`). Then rename the item and restore the oldest version.

| Check | One file | Plain folder | `.rtfd` | `.noto` |
| --- | --- | --- | --- | --- |
| Local folder: two versions, each complete | yes | yes | yes | yes |
| Local folder: the versions stay after a rename | yes | yes | yes | yes |
| Local folder: restore gives v1 with `a.png` only | yes | yes | yes | yes |
| iCloud: two versions | yes | yes, then 0 after the sync | yes | yes |
| iCloud: versions on the server | yes | no: `NSFileProviderErrorDomain` -1005 | yes, with images | yes, with images |
| iCloud: the versions stay after a rename | yes | no | yes | yes |
| iCloud: restore gives v1 with `a.png` only | yes | no version | yes | yes |

Storage: the first version of a folder copies it (a 500 MB file used 526 MB). A later version with
the same images used 0 to 1 MB.

Result: in iCloud, only a file or a file package keeps versions. A plain folder loses them.

## 3. Versions in iCloud

iCloud keeps a server version of each upload. `NSFileVersion.getNonlocalVersionsOfItem(at:)` lists
them. A coordinated read of a version's `url` downloads it. After that, `otherVersionsOfItem(at:)`
lists it, with the same `persistentIdentifier`.

Test: two items of each kind. Group A never called `addOfItem`. Group B called it before each edit.
Each edit waited for the upload, then 20 s.

| | A, one file | A, `.noto` | B, one file | B, `.noto` |
| --- | --- | --- | --- | --- |
| Local versions | 0 | 0 | 3 | 3 |
| Server versions | 3 | 3, each with its images | 3 | 3 |

Result: iCloud makes server versions by itself. `addOfItem` adds only local versions.

Not measured: a second device that reads these versions, and how long iCloud keeps them.

## 4. Version count while the user types

Noto saves 300 ms after the last edit (`NotesStore.scheduleSave`). We wrote for 3 minutes at four rates.

| Save interval | Saves | Server versions, `.noto` / one file |
| --- | --- | --- |
| 0.35 s | 515 | 18 / 17 |
| 1 s | 180 | 12 / 21 |
| 5 s | 36 | 28 / 32 |
| 30 s | 6 | 6 / 6 |

Result: iCloud joins saves that come quickly. At most it keeps about one version each 10 s, so a
history list must group the versions. The count did not change in the 3 minutes after the writes.
This was one run; the numbers change from run to run.

## 5. A package in Noto

| Question | Result | Evidence |
| --- | --- | --- |
| Is a declared type enough? | Yes. A `UTExportedTypeDeclarations` entry that conforms to `com.apple.package` makes the system and iCloud treat `.noto` as a package. A document type is not necessary | the tests above used only that entry |
| Does `NSMetadataQuery` find `text.md` in a package? | No. It returns the package as one item, with its download status and its conflict flag. An edit inside the package updates that item | a test app with the iCloud entitlement, predicate `NSMetadataItemFSNameKey` |
| Can a rename make an iCloud folder a package? | No. After `周报` becomes `周报.noto`, the Mac sees a package, but the server keeps a folder: no package versions | test U4 |
| Can a copy make one? | Yes. `copyItem`, a new folder with copied children, and a package that is built outside iCloud and moved in all work | test U4b |
| Does a renamed package keep its server versions? | Yes | test U4c |
| What does Noto 0.4.0 show for `周报.noto`? | It lists it with the title `周报.noto`. Its watcher does not see changes inside the package | `NotesRepository.list`, test U1 |
| What does a package that iCloud has not downloaded look like? | The package and its `text.md` exist, and the package reports `NotDownloaded`. A read inside it starts the download | eviction test |
| Does `isUbiquitousItem` always see an iCloud item? | No. A process that the container's entitlement does not cover sees the container's items as local. A migration there renamed two notes, and iCloud then kept a package flag on the folders after they were renamed back | a test copy without the iCloud entitlement |

Not measured: a real iCloud conflict on a package. That needs two devices.

## 6. The system version browser

The first design drew its own history list. The system browser (`NSDocument.browseVersions(_:)`)
replaced it, because it is the view that users know from other document apps.

| Question | Result | Evidence |
| --- | --- | --- |
| Can an app that is not document based use it? | Yes. An `NSDocument` subclass opened on the package for the browse only is enough. It works in an app with no Dock icon too | a prototype app |
| Must `Info.plist` name the document class? | Yes. Without a `CFBundleDocumentTypes` entry for the type, each earlier version shows "Unable to open version" | the prototype without the entry |
| Does the declaration have side effects? | AppKit restores open document windows at the next launch, and opens a file it gets as a launch argument. Noto turns window restoration off for these windows and makes no untitled document | the prototype |
| What does Restore do? | It adds the note as it is as a version, then replaces the whole package | the files on disk after a restore |
| What about server versions? | The browser lists them with a Load Version button until they download. A coordinated read of a version's URL downloads it | the user's test, and a test in a scratch iCloud folder |

## Decisions

1. A note is a `.noto` file package.
2. The versions come from `NSFileVersion`: iCloud server versions, and local versions that Noto adds
   only when the note changed.
3. The system version browser shows them, through `NoteVersionDocument`. Noto downloads the server
   versions of the last 3 days first, for at most 10 seconds.
4. The migration copies each old note folder in iCloud into a new package, because a rename does not
   work there. Any path under `~/Library/Mobile Documents` counts as iCloud.
5. The watcher queries packages, not `text.md`.
6. The conflict code works on the package, and it does not remove other versions, because they are
   the history.
