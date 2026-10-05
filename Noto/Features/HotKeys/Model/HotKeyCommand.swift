/// The commands a global shortcut can run. The raw value is the persisted key.
enum HotKeyCommand: String, CaseIterable, Sendable {
    case showNotes
    case createNote
    case searchNotes

    var title: String {
        switch self {
        case .showNotes: "Show Notes"
        case .createNote: "Create Note"
        case .searchNotes: "Search Notes"
        }
    }

    var subtitle: String {
        switch self {
        case .showNotes: "Shows the note window, or puts it away."
        case .createNote: "Starts a new Untitled note."
        case .searchNotes: "Opens the note switcher."
        }
    }
}
