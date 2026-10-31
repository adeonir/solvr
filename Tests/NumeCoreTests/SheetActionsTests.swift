import Foundation
import Testing
@testable import NumeCore

private func edited(_ sheet: StoredSheet, text: String) -> StoredSheet {
    StoredSheet(id: sheet.id, title: sheet.title, created: sheet.created, updated: sheet.updated, text: text)
}

@Test func renamingPreservesPendingText() throws {
    let store = SheetStore(folder: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    let original = try store.create(title: "Budget")
    let sheets = try SheetActions(store: store).rename(original.id, title: "Budget 2027", sheets: [edited(original, text: "salary = 8000")])
    #expect(sheets.first?.id == original.id)
    #expect(sheets.first?.title == "Budget 2027")
    #expect(sheets.first?.text == "salary = 8000")
}

@Test func duplicatingPreservesPendingTextInOriginal() throws {
    let store = SheetStore(folder: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    let original = try store.create(title: "Budget")
    let result = try SheetActions(store: store).duplicate(original.id, sheets: [edited(original, text: "salary = 8000")], selectedID: original.id)
    #expect(result.copy.text == "salary = 8000")
    #expect(result.sheets.first { $0.id == original.id }?.text == "salary = 8000")
}

@Test func duplicatingUnselectedSheetUsesPendingText() throws {
    let store = SheetStore(folder: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    let original = try store.create(title: "Budget")
    let other = try store.create(title: "Other")
    let result = try SheetActions(store: store).duplicate(original.id, sheets: [edited(original, text: "salary = 9000"), other], selectedID: other.id)
    #expect(result.copy.text == "salary = 9000")
    #expect(result.sheets.first { $0.id == original.id }?.text == "salary = 9000")
}
