/// The editor's font choices. A nil member means the system's own choice for that role.
struct NoteFontSettings: Equatable, Sendable {
    /// The family of Latin text and headings.
    var textFamily: String?
    /// The family that draws the characters the text and code families do not have.
    var cjkFamily: String?
    /// The family of inline code, code blocks and tables.
    var codeFamily: String?
    /// The body size in points; headings and markers scale with it.
    var size: Double?

    static let standard = NoteFontSettings()
    static let sizeRange = 10.0...32.0
}
