import Foundation

public struct StoredSheet: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let title: String
    public let created: Date
    public let updated: Date
    public let text: String
}

public struct SkippedSheet: Sendable {
    public let url: URL
    public let reason: String
}

public struct SheetList: Sendable {
    public let sheets: [StoredSheet]
    public let skipped: [SkippedSheet]
}

public struct SheetStore: Sendable {
    public let folder: URL
    public init(folder: URL) { self.folder = folder }

    public func create(title: String, now: Date = Date()) throws -> StoredSheet {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let sheet = StoredSheet(id: UUID(), title: title, created: now, updated: now, text: "")
        let titleData = try JSONEncoder().encode(title)
        let encodedTitle = String(decoding: titleData, as: UTF8.self)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: now)
        let content = "---\ntitle: \(encodedTitle)\ncreated: \(timestamp)\nupdated: \(timestamp)\n---\n"
        try content.write(to: folder.appending(path: "\(sheet.id.uuidString).md"), atomically: true, encoding: .utf8)
        return sheet
    }

    public func list() throws -> SheetList {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        var sheets: [StoredSheet] = []
        var skipped: [SkippedSheet] = []
        for file in files where file.pathExtension == "md" {
            do { sheets.append(try read(file)) }
            catch { skipped.append(SkippedSheet(url: file, reason: String(describing: error))) }
        }
        sheets.sort { $0.updated == $1.updated ? $0.id.uuidString < $1.id.uuidString : $0.updated > $1.updated }
        return SheetList(sheets: sheets, skipped: skipped)
    }

    private func read(_ file: URL) throws -> StoredSheet {
        guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent) else { throw StoreError.invalidFilename }
        let content = try String(contentsOf: file, encoding: .utf8)
        let parts = content.components(separatedBy: "\n---\n")
        guard parts.count >= 2, parts[0].hasPrefix("---\n") else { throw StoreError.invalidFrontmatter }
        let lines = parts[0].dropFirst(4).components(separatedBy: "\n")
        guard lines.count == 3, lines[0].hasPrefix("title: "), lines[1].hasPrefix("created: "), lines[2].hasPrefix("updated: "),
              let title = try? JSONDecoder().decode(String.self, from: Data(lines[0].dropFirst(7).utf8)),
              let created = parseDate(String(lines[1].dropFirst(9))),
              let updated = parseDate(String(lines[2].dropFirst(9))) else { throw StoreError.invalidFrontmatter }
        return StoredSheet(id: id, title: title, created: created, updated: updated, text: parts.dropFirst().joined(separator: "\n---\n"))
    }

    private func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private enum StoreError: Error { case invalidFilename, invalidFrontmatter }
}
