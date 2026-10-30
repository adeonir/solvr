import Testing
import Foundation
@testable import NumeCore

// Complete-sheet tests for the CSS quantity conversions and the Settings
// references they consume (ADK-227): one shared pixel-base value serves
// `rem` and `em` alike, initially 16 pixels, and the pixel density of 96
// ppi translates points and physical lengths into pixels. The Settings
// values arrive through the injected EvaluationContext (ADR-005); an
// expression-local `at` override applies to its expression only and
// leaves the Settings values and every other expression unchanged.
// Locale, display precision, time zone, and clock are fixed per fixture.

struct CssSettingsTests {
    private func context(
        locale identifier: String = "pt_BR",
        precision: Int = 2,
        pixelBase: Decimal = 16,
        ppi ppiValue: Decimal = 96
    ) -> EvaluationContext {
        EvaluationContext(
            localeIdentifier: identifier,
            timeZone: TimeZone(identifier: "America/Sao_Paulo")!,
            now: Date(timeIntervalSince1970: 1_791_926_400), // 2026-10-30 00:00 UTC
            displayPrecision: precision,
            pixelBase: pixelBase,
            ppi: ppiValue
        )
    }

    // MARK: The shared Settings values define the defaults

    @Test
    func settingsCarryTheSharedPixelBaseInitiallySixteenPixels() {
        let injected = context()
        #expect(injected.pixelBase == 16)
        #expect(injected.ppi == 96)
    }

    @Test
    func defaultPixelBaseMapsSixteenPixelsToOneEmAndRem() {
        let results = evaluate(sheetText: "16px in em\n1 rem", context: context())
        #expect(results[0].kind == .expression)
        #expect(results[0].diagnostic == nil)
        #expect(results[0].value == .decimal(1))
        #expect(results[0].display == "1em")
        #expect(results[1].display == "16px")
    }

    @Test
    func defaultPixelDensityMakesTwelvePointsSixteenPixels() {
        let result = evaluate(sheetText: "12 pt in px", context: context())[0]
        #expect(result.diagnostic == nil)
        #expect(result.display == "16px")
    }

    // MARK: The shared pixel base applies to both `rem` and `em`

    @Test(arguments: [
        ("1 rem in px", "20px"),
        ("16px in em", "0,8em"),
        ("16px in rem", "0,8rem"),
        ("1 em in rem", "1rem"),
        ("1 rem", "20px"),
        ("1 em", "20px"),
    ])
    func withPixelBaseTwentyPixelsTheSharedValueApplies(
        _ source: String, _ expected: String
    ) {
        let result = evaluate(sheetText: source, context: context(pixelBase: 20))[0]
        #expect(result.diagnostic == nil)
        #expect(result.display == expected)
    }

    // MARK: The expression-local `at 20px` base

    @Test
    func localPixelBaseAppliesToItsExpressionOnly() {
        let injected = context()
        let results = evaluate(
            sheetText: "16px in em at 20px\n16px in em\n1 rem", context: injected
        )
        #expect(results[0].display == "0,8em")
        // Other expressions keep the shared Settings base.
        #expect(results[1].display == "1em")
        #expect(results[2].display == "16px")
        // The shared Settings value stays at sixteen pixels.
        #expect(injected.pixelBase == 16)
    }

    @Test
    func theLocalPixelBaseServesRemConversionsAlike() {
        let results = evaluate(sheetText: "2 rem in px at 24px", context: context())
        #expect(results[0].display == "48px")
    }

    @Test
    func theLocalPixelBaseFollowsInsideArithmetic() {
        let results = evaluate(sheetText: "(1 rem + 1 rem) in px at 20px", context: context())
        #expect(results[0].display == "40px")
    }

    // MARK: The expression-local `at 72 ppi` density

    @Test
    func localPpiAppliesToItsExpressionOnly() {
        let injected = context()
        let results = evaluate(
            sheetText: "2 inches in px at 72 ppi\n2 inches in px\n12 pt in px", context: injected
        )
        #expect(results[0].display == "144px")
        // Other expressions keep the shared Settings density.
        #expect(results[1].display == "192px")
        #expect(results[2].display == "16px")
        // The shared Settings density stays at ninety-six ppi.
        #expect(injected.ppi == 96)
    }

    @Test
    func settingsPixelDensityAppliesToPointsAndLengths() {
        let results = evaluate(sheetText: "2 inches in px\n12 pt in px", context: context(ppi: 72))
        #expect(results[0].display == "144px")
        #expect(results[1].display == "12px")
    }

    // MARK: Abbreviation and full-name aliases convert alike

    @Test
    func pixelAndPointAliasesConvertAlike() {
        let results = evaluate(
            sheetText: "18px in pt\n18 pixels in pt\n18 px in point\n18 px in points",
            context: context(precision: 10)
        )
        for result in results {
            #expect(result.diagnostic == nil)
            #expect(result.display == "13,5 pt")
        }
    }

    // MARK: Quantities alone display at the shared references

    @Test
    func bareQuantitiesDisplayTheirValueWithTheirUnit() {
        let results = evaluate(sheetText: "1 px\n2 rem\n12 pt", context: context())
        #expect(results[0].display == "1px")
        #expect(results[1].display == "32px")
        #expect(results[2].display == "12 pt")
    }
}
