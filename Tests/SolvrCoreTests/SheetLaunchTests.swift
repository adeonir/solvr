import Foundation
#if canImport(Core)
@testable import Core
#else
@testable import SolvrCore
#endif
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
