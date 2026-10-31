import Foundation
import Testing
@testable import NumeCore

@Test func createsAndListsSheets() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let store = SheetStore(folder: folder)
    let first = try store.create(title: "Budget", now: Date(timeIntervalSince1970: 1))
    let second = try store.create(title: "Budget", now: Date(timeIntervalSince1970: 2))
    let special = try store.create(title: "Rent: \"June\"", now: Date(timeIntervalSince1970: 3))
    let listed = try SheetStore(folder: folder).list()
    #expect(listed.sheets.map(\.title) == [special.title, second.title, first.title])
    #expect(Set(listed.sheets.map(\.id)).count == 3)
    #expect(special.text == "")
}

@Test func skipsInvalidFrontmatterWithoutChangingFile() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let file = folder.appending(path: "\(UUID().uuidString).md")
    try "not frontmatter".write(to: file, atomically: true, encoding: .utf8)
    let result = try SheetStore(folder: folder).list()
    #expect(result.sheets.isEmpty)
    #expect(result.skipped.count == 1)
    #expect(try String(contentsOf: file, encoding: .utf8) == "not frontmatter")
}
