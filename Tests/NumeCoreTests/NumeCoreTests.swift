import Testing
@testable import NumeCore

// This placeholder suite verifies the Swift Testing setup runs before any
// core behavior exists. It does not assert calculator or sheet behavior;
// those tests arrive with the behavior itself.
struct NumeCoreTests {
    @Test
    func testTargetRuns() {
        #expect(true)
    }
}
