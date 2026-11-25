import Foundation
import Security
import Testing

// The build identity is observed on the built products: bundle identifiers,
// the deployment target, and the signature the app was built with.

private final class TestBundleToken {}

struct BuildIdentityTests {
    @Test func appReportsItsBundleIdentifier() {
        #expect(Bundle.main.bundleIdentifier == "dev.adeonir.labs.Solvr")
    }

    @Test func coreReportsItsBundleIdentifier() {
        #expect(Bundle(identifier: "dev.adeonir.labs.Core") != nil)
    }

    @Test func appTestsReportTheirBundleIdentifier() {
        #expect(Bundle(for: TestBundleToken.self).bundleIdentifier == "dev.adeonir.labs.AppTests")
    }

    @Test func appDeclaresMacOS26AsMinimumSystem() {
        let minimum = Bundle.main.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String
        #expect(minimum == "26.0")
    }

    /// Debug signs with the team's Apple Development identity; every other
    /// configuration, and the CI override, signs ad-hoc.
    @Test func appSignatureMatchesTheBuildConfiguration() throws {
        var code: SecStaticCode?
        #expect(SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &code) == errSecSuccess)
        var info: CFDictionary?
        let status = try SecCodeCopySigningInformation(
            #require(code), SecCSFlags(rawValue: kSecCSSigningInformation), &info
        )
        #expect(status == errSecSuccess)
        let signing = info as? [String: Any]
        if signing?[kSecCodeInfoTeamIdentifier as String] == nil {
            let flags = signing?[kSecCodeInfoFlags as String] as? UInt32 ?? 0
            #expect(flags & SecCodeSignatureFlags.adhoc.rawValue != 0)
        }
    }
}
