import Foundation

public enum SheetLaunch {
    public static func selection(in sheetIDs: [UUID], lastOpened: UUID?) -> UUID? {
        if let lastOpened, sheetIDs.contains(lastOpened) { return lastOpened }
        return sheetIDs.first
    }
}
