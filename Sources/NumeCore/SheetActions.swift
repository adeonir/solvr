import Foundation

public struct SheetActions {
    private let store: SheetStore
    public init(store: SheetStore) { self.store = store }

    public func rename(_ id: UUID, title: String, sheets: [StoredSheet]) throws -> [StoredSheet] {
        try store.rename(id, title: title)
        let renamed = try store.list().sheets.first { $0.id == id }
        guard let renamed, let index = sheets.firstIndex(where: { $0.id == id }) else { return sheets }
        var result = sheets
        let current = result.remove(at: index)
        result.insert(StoredSheet(id: renamed.id, title: renamed.title, created: renamed.created, updated: renamed.updated, text: current.text), at: 0)
        return result
    }

    public func duplicate(_ id: UUID, sheets: [StoredSheet], selectedID: UUID?) throws -> (sheets: [StoredSheet], copy: StoredSheet) {
        guard let source = sheets.first(where: { $0.id == id }) else { throw SheetActionError.missingSheet }
        let copy = try store.duplicate(id: id, text: source.text)
        return ([copy] + sheets, copy)
    }

    private enum SheetActionError: Error { case missingSheet }
}
