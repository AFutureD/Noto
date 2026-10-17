import Foundation
import UniformTypeIdentifiers

/// The files a note shows inline. They live in the `assets` folder of the note's own folder, and the
/// Markdown names them by a path relative to that folder, so a rename or a move keeps them working.
enum NoteAssets {
    static let folderName = "assets"

    /// The file a relative image path names, or nil when the path leaves the note folder.
    /// A remote or absolute path is nil too: the editor only shows the note's own files.
    static func resolve(_ path: String, in noteFolder: URL) -> URL? {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("~"), !path.contains("\0"),
            URL(string: path)?.scheme == nil
        else { return nil }
        let folder = noteFolder.standardizedFileURL.resolvingSymlinksInPath()
        let file = folder.appendingPathComponent(path).standardizedFileURL
        // A symbolic link inside the note folder must not lead out of it either.
        guard file.path.hasPrefix(folder.path + "/"),
            file.resolvingSymlinksInPath().path.hasPrefix(folder.path + "/")
        else { return nil }
        return file
    }

    /// Only an image file imports: the Markdown it gets shows an image, and a folder or a video
    /// would only fill the note's folder and iCloud.
    static func isImage(_ file: URL) -> Bool {
        guard let values = try? file.resourceValues(forKeys: [.isDirectoryKey, .contentTypeKey]),
            values.isDirectory != true, let type = values.contentType ?? UTType(filenameExtension: file.pathExtension)
        else { return false }
        return type.conforms(to: .image)
    }

    /// MDTextKit writes pasted image data to `<temporary directory>/<UUID>/image.png` before it hands
    /// the file over; a file the user dropped lives anywhere else.
    static func isPasted(_ file: URL) -> Bool {
        let folder = file.deletingLastPathComponent()
        let temporary = FileManager.default.temporaryDirectory.standardizedFileURL.resolvingSymlinksInPath()
        return UUID(uuidString: folder.lastPathComponent) != nil
            && folder.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().path == temporary.path
    }

    /// A pasted image arrives as a temporary `image.png`. It gets a dated name, so two Macs that
    /// paste into the same note offline do not write the same file and make iCloud pick one.
    static func pastedName(for fileName: String, at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let ext = URL(fileURLWithPath: fileName).pathExtension
        let stem = "Pasted \(formatter.string(from: date))"
        return ext.isEmpty ? stem : "\(stem).\(ext)"
    }

    /// The first free `<name>.<ext>`, `<name> 2.<ext>`, … in `taken`, compared case-insensitively.
    static func uniqueName(for fileName: String, taken: Set<String>) -> String {
        let folded = Set(taken.map { $0.lowercased() })
        let url = URL(fileURLWithPath: fileName)
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var suffix = 1
        while true {
            let stem = suffix == 1 ? base : "\(base) \(suffix)"
            let candidate = ext.isEmpty ? stem : "\(stem).\(ext)"
            if !folded.contains(candidate.lowercased()) { return candidate }
            suffix += 1
        }
    }

    /// Images stand as their own paragraphs, as in Bear: a line break goes before them when the
    /// text before is not a line start, and after them when text follows on the same line. Inline,
    /// a second image would wrap next to the first instead of at the margin.
    static func paragraph(_ markdown: String, after previous: Character?, before next: Character?) -> String {
        let lead = previous.map { $0.isNewline ? "" : "\n" } ?? ""
        let trail = next.map { $0.isNewline ? "" : "\n" } ?? ""
        return lead + markdown + trail
    }

    /// True when `source` can name the file `assets/<name>`: as written, percent-encoded as
    /// `markdown(for:)` writes it, or decoded. Case and Unicode normalization do not count. A doubt
    /// counts as a reference, so a code block that names the file keeps it.
    static func isReferenced(_ name: String, in source: String) -> Bool {
        func normalized(_ text: String) -> String { text.precomposedStringWithCanonicalMapping.lowercased() }
        let path = normalized("\(folderName)/\(name)")
        let text = normalized(source)
        if text.contains(path) { return true }
        if let encoded = path.addingPercentEncoding(withAllowedCharacters: pathAllowed), text.contains(normalized(encoded)) {
            return true
        }
        return normalized(source.removingPercentEncoding ?? source).contains(path)
    }

    private static var pathAllowed: CharacterSet {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "()")
        return allowed
    }

    /// The Markdown that shows `relativePath` as an image. The path is percent-encoded so a space
    /// or a parenthesis cannot end the link early.
    static func markdown(for relativePath: String) -> String {
        let encoded = relativePath.addingPercentEncoding(withAllowedCharacters: pathAllowed) ?? relativePath
        return "![](\(encoded))"
    }
}
