import Foundation
@testable import Core
import Testing

@Test @MainActor func savesOnlyAfterHalfASecond() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let store = SheetStore(folder: folder)
    let sheet = try store.create(title: "Budget")
    let timer = FakeSaveTimer()
    let autosave = SheetAutosave(store: store, timer: timer, onError: { _ in })
    autosave.edit(sheet.id, text: "salary = 8000")
    timer.advance(milliseconds: 400)
    #expect(try store.list().sheets.first?.text == "")
    timer.advance(milliseconds: 100)
    #expect(try store.list().sheets.first?.text == "salary = 8000")
}

@Test @MainActor func laterEditRestartsSaveDelay() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let store = SheetStore(folder: folder)
    let sheet = try store.create(title: "Budget")
    let timer = FakeSaveTimer()
    let autosave = SheetAutosave(store: store, timer: timer, onError: { _ in })
    autosave.edit(sheet.id, text: "salary = 8000")
    timer.advance(milliseconds: 400)
    #expect(try store.list().sheets.first?.text == "")
    autosave.edit(sheet.id, text: "salary = 9000")
    timer.advance(milliseconds: 100)
    #expect(try store.list().sheets.first?.text == "")
    timer.advance(milliseconds: 399)
    #expect(try store.list().sheets.first?.text == "")
    timer.advance(milliseconds: 1)
    #expect(try store.list().sheets.first?.text == "salary = 9000")
}

@MainActor private final class FakeSaveTimer: SheetSaveTimer {
    private var now = 0
    private var deadline = 0
    private var action: (@MainActor () -> Void)?
    func schedule(afterMilliseconds delay: Int, _ action: @escaping @MainActor () -> Void) {
        deadline = now + delay
        self.action = action
    }

    func cancel() {
        action = nil
    }

    func advance(milliseconds: Int) {
        now += milliseconds
        if now >= deadline, let action {
            self.action = nil
            action()
        }
    }
}

@Test @MainActor func flushWritesImmediately() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let store = SheetStore(folder: folder)
    let sheet = try store.create(title: "Budget")
    let timer = FakeSaveTimer()
    let autosave = SheetAutosave(store: store, timer: timer, onError: { _ in })
    autosave.edit(sheet.id, text: "salary = 8000")
    autosave.flush()
    #expect(try SheetStore(folder: folder).list().sheets.first?.text == "salary = 8000")
}

@Test @MainActor func reportsFailureAndSavesWholeTextOnNextEdit() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let store = SheetStore(folder: folder)
    let sheet = try store.create(title: "Budget")
    let file = folder.appending(path: "\(sheet.id.uuidString).md")
    let backup = folder.appending(path: "backup")
    try FileManager.default.moveItem(at: file, to: backup)
    let timer = FakeSaveTimer()
    var errors = 0
    let autosave = SheetAutosave(store: store, timer: timer, onError: { _ in errors += 1 })
    autosave.edit(sheet.id, text: "salary")
    autosave.flush()
    #expect(errors == 1)
    try FileManager.default.moveItem(at: backup, to: file)
    autosave.edit(sheet.id, text: "salary = 8000")
    timer.advance(milliseconds: 500)
    #expect(try store.list().sheets.first?.text == "salary = 8000")
}
