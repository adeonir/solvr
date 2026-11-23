import Foundation
#if canImport(Core)
@testable import Core
#else
#endif
import Testing

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

@Test func renamesSheetWithoutChangingTextOrFileName() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let store = SheetStore(folder: folder)
    let budget = try store.create(title: "Budget", now: Date(timeIntervalSince1970: 1))
    let other = try store.create(title: "Other", now: Date(timeIntervalSince1970: 2))
    let file = folder.appending(path: "\(budget.id.uuidString).md")
    let contents = try String(contentsOf: file, encoding: .utf8)
    try (contents + "rent = 500").write(to: file, atomically: true, encoding: .utf8)
    try store.rename(budget.id, title: "Budget 2027", now: Date(timeIntervalSince1970: 3))
    let listed = try SheetStore(folder: folder).list().sheets
    #expect(listed.map(\.id) == [budget.id, other.id])
    #expect(listed[0].title == "Budget 2027")
    #expect(listed[0].text == "rent = 500")
    #expect(listed[0].created == Date(timeIntervalSince1970: 1))
    #expect(listed[0].updated == Date(timeIntervalSince1970: 3))
    #expect(FileManager.default.fileExists(atPath: file.path))
    try store.rename(other.id, title: "Budget 2027", now: Date(timeIntervalSince1970: 4))
    #expect(try store.list().sheets.map(\.title) == ["Budget 2027", "Budget 2027"])
}

@Test func rejectsBlankSheetTitles() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let store = SheetStore(folder: folder)
    let sheet = try store.create(title: "Budget", now: Date(timeIntervalSince1970: 1))
    for title in ["", "   "] {
        #expect(throws: (any Error).self) { try store.rename(sheet.id, title: title) }
        #expect(try store.list().sheets.first?.title == "Budget")
    }
}

@Test func preservesSpecialCharactersInRenamedTitleAfterRestart() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let store = SheetStore(folder: folder)
    let sheet = try store.create(title: "Budget", now: Date(timeIntervalSince1970: 1))
    try store.rename(sheet.id, title: "  Rent: \"June\"", now: Date(timeIntervalSince1970: 2))
    let reopened = try SheetStore(folder: folder).list().sheets
    #expect(reopened.count == 1)
    #expect(reopened.first?.id == sheet.id)
    #expect(reopened.first?.title == "  Rent: \"June\"")
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

@Test func deletesSheetFileWithoutRemovingOtherSheets() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let store = SheetStore(folder: folder)
    let deleted = try store.create(title: "Budget")
    let retained = try store.create(title: "Other")
    let file = folder.appending(path: "\(deleted.id.uuidString).md")
    try store.delete(deleted.id)
    #expect(!FileManager.default.fileExists(atPath: file.path))
    #expect(try store.list().sheets.map(\.id) == [retained.id])
}
