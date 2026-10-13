/// The panes of the Settings window, in toolbar order. The raw value is the toolbar item identifier.
enum SettingsPane: String, CaseIterable, Sendable {
    case general
    case editor
    case shortcuts
    case sync

    var title: String {
        switch self {
        case .general: "General"
        case .editor: "Editor"
        case .shortcuts: "Shortcuts"
        case .sync: "Sync"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .editor: "textformat"
        case .shortcuts: "keyboard"
        case .sync: "arrow.triangle.2.circlepath.icloud"
        }
    }
}
