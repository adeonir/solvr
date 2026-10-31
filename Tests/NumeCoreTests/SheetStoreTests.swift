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

@Test func duplicatesSheetWithIndependentFile() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let store = SheetStore(folder: folder)
    let original = try store.create(title: "Budget", now: Date(timeIntervalSince1970: 1))
    let originalURL = folder.appending(path: "\(original.id.uuidString).md")
    let originalFile = try String(contentsOf: originalURL, encoding: .utf8) + "Rent: 100\n"
    try originalFile.write(to: originalURL, atomically: true, encoding: .utf8)
    let time = Date(timeIntervalSince1970: 20)
    let copy = try store.duplicate(id: original.id, now: time)
    #expect(copy.id != original.id)
    #expect(copy.title == "Budget")
    #expect(copy.text == "Rent: 100\n")
    #expect(copy.created == time)
    #expect(copy.updated == time)
    let listed = try store.list().sheets
    #expect(listed.map(\.id) == [copy.id, original.id])
    #expect(listed.first == copy)
    let copyURL = folder.appending(path: "\(copy.id.uuidString).md")
    let copyFile = try String(contentsOf: copyURL, encoding: .utf8)
    try (copyFile + "Food: 50\n").write(to: copyURL, atomically: true, encoding: .utf8)
    #expect(try String(contentsOf: originalURL, encoding: .utf8) == originalFile)
}
