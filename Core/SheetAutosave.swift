import Foundation

@MainActor public protocol SheetSaveTimer: AnyObject {
    func schedule(afterMilliseconds delay: Int, _ action: @escaping @MainActor () -> Void)
    func cancel()
}

@MainActor public final class SheetAutosave {
    private let store: SheetStore
    private let timer: any SheetSaveTimer
    private let onError: (Error) -> Void
    private var pending: [UUID: String] = [:]

    public init(store: SheetStore, timer: any SheetSaveTimer, onError: @escaping (Error) -> Void) {
        self.store = store
        self.timer = timer
        self.onError = onError
    }

    public func edit(_ id: UUID, text: String) {
        pending[id] = text
        timer.schedule(afterMilliseconds: 500) { [weak self] in self?.flush() }
    }

    public func flush() {
        timer.cancel()
        let edits = pending
        pending.removeAll()
        for (id, text) in edits {
            do { try store.write(id, text: text) }
            catch { onError(error) }
        }
    }
}
