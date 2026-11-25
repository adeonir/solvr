import Foundation
import Testing

private final class TestBundleToken {}

struct BuildIdentityTests {
    @Test func coreTestsReportTheirBundleIdentifier() {
        #expect(Bundle(for: TestBundleToken.self).bundleIdentifier == "dev.adeonir.labs.CoreTests")
    }
}
