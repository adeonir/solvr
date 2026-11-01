import Foundation
@testable import NumeCore
import Testing

@Test func launchSelectsLastOpenedSheet() {
    let first = UUID()
    let last = UUID()
    #expect(SheetLaunch.selection(in: [first, last], lastOpened: last) == last)
}

@Test func launchFallsBackToFirstSheet() {
    let first = UUID()
    #expect(SheetLaunch.selection(in: [first, UUID()], lastOpened: UUID()) == first)
}

@Test func launchWithNoSheetsHasNoSelection() {
    #expect(SheetLaunch.selection(in: [], lastOpened: UUID()) == nil)
}
