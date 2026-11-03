import Foundation
@testable import SolvrCore
import Testing

// Complete-sheet tests for regional number reading and representation
// conversion (ADK-222). Locale and display precision are fixed per fixture
// through the EvaluationContext, per ADR-005.

struct RegionalNumberTests {
    private func context(
        locale identifier: String = "pt_BR",
        precision: Int = 2
    ) -> EvaluationContext {
        EvaluationContext(
            localeIdentifier: identifier,
            timeZone: TimeZone(identifier: "America/Sao_Paulo")!,
            now: Date(timeIntervalSince1970: 1_791_926_400), // 2026-10-30 00:00 UTC
            displayPrecision: precision
        )
    }

    // MARK: Regional number reading

    @Test
    func brazilianFormattingReadsDotsForThousandsAndCommasForDecimals() throws {
        let results = evaluate(sheetText: "1.500\n1,500\n1.500 + 1,5", context: context())
        #expect(results[0].value == .decimal(Decimal(1500)))
        #expect(results[0].display == "1.500")
        #expect(try results[1].value == .decimal(Decimal(exact: "1.5")))
        #expect(results[1].display == "1,5")
        #expect(try results[2].value == .decimal(Decimal(exact: "1501.5")))
        #expect(results[2].display == "1.501,5")
    }

    @Test
    func americanFormattingFlipsTheSeparatorRoles() throws {
        let results = evaluate(sheetText: "1,500\n1.500", context: context(locale: "en_US"))
        #expect(results[0].value == .decimal(Decimal(1500)))
        #expect(results[0].display == "1,500")
        #expect(try results[1].value == .decimal(Decimal(exact: "1.5")))
    }

    @Test(arguments: [
        ("5 300", Decimal(5300)),
        ("1 500 000", Decimal(1_500_000))
    ])
    func blankSeparatedGroupsReadAsOneNumber(_ source: String, _ value: Decimal) {
        let result = evaluate(sheetText: source, context: context())[0]
        #expect(result.value == .decimal(value))
        #expect(result.diagnostic == nil)
    }

    @Test
    func blankGroupsComposeWithTheDecimalSeparator() throws {
        let result = evaluate(sheetText: "1 500,5", context: context())[0]
        #expect(try result.value == .decimal(Decimal(exact: "1500.5")))
        #expect(result.display == "1.500,5")
    }

    @Test(arguments: ["5 30", "5  300", "1 500 0"])
    func incompleteGroupsAreInvalidSyntax(_ source: String) {
        let result = evaluate(sheetText: source, context: context())[0]
        #expect(result.diagnostic?.message == "Invalid syntax")
        #expect(result.value == nil)
    }

    // MARK: Base literals

    @Test(arguments: [
        ("0b110111011", Decimal(443)),
        ("0o1435343", Decimal(408_291)),
        ("0x1bb", Decimal(443)),
    ])
    func baseLiteralsReadAsPlainNumbers(_ source: String, _ value: Decimal) {
        let result = evaluate(sheetText: source, context: context())[0]
        #expect(result.value == .decimal(value))
        #expect(result.diagnostic == nil)
    }

    // MARK: Representation conversions

    @Test(arguments: [
        ("0b110111011 in hex", "0x1bb", Decimal(443)),
        ("0o1435343 in hex", "0x63ae3", Decimal(408_291)),
        ("443 in bin", "0b110111011", Decimal(443)),
        ("443 in oct", "0o673", Decimal(443)),
        ("255 in hex", "0xff", Decimal(255)),
        ("255 in bin", "0b11111111", Decimal(255)),
        ("255 in oct", "0o377", Decimal(255)),
    ])
    func conversionsDisplayTheRequestedRepresentation(
        _ source: String, _ expected: String, _ value: Decimal
    ) {
        let result = evaluate(sheetText: source, context: context())[0]
        #expect(result.kind == .expression)
        #expect(result.diagnostic == nil)
        #expect(result.display == expected)
        #expect(result.value == .decimal(value))
    }

    // MARK: Scientific representation

    @Test(arguments: [
        ("5 300 in sci", "5,3E3"),
        ("150 000 in sci", "1,5E5"),
        ("0x10 in sci", "1,6E1"),
    ])
    func scientificConversionDisplaysTheMantissaWithLocaleSeparators(
        _ source: String, _ expected: String
    ) {
        let result = evaluate(sheetText: source, context: context())[0]
        #expect(result.display == expected)
        #expect(result.diagnostic == nil)
    }

    @Test
    func scientificConversionFollowsTheLocale() {
        let result = evaluate(sheetText: "5300 in sci", context: context(locale: "en_US"))[0]
        #expect(result.display == "5.3E3")
    }

    // MARK: Display precision changes only the representation

    @Test
    func displayPrecisionChangesTheRepresentationOnly() throws {
        let atTwo = evaluate(sheetText: "1 / 3", context: context(precision: 2))[0]
        let atTen = evaluate(sheetText: "1 / 3", context: context(precision: 10))[0]
        #expect(atTwo.display == "0,33")
        #expect(atTen.display == "0,3333333333")
        // The retained value stays the same at every precision.
        #expect(atTwo.value == atTen.value)
        let one = try Decimal(exact: "1")
        let three = try Decimal(exact: "3")
        #expect(atTwo.value == .decimal(Numeric.retain(one / three)))
        // At least 34 significant digits survive internally.
        let atForty = evaluate(sheetText: "1 / 3", context: context(precision: 40))[0]
        #expect(atForty.display == "0," + String(repeating: "3", count: 34))
        // The reused value does not shrink with the displayed places.
        #expect(
            evaluate(sheetText: "x = 1 / 3\nx * 3", context: context(precision: 2))[1].display == "1"
        )
    }

    // MARK: Representations keep the numeric value

    @Test
    func representationInsideArithmeticKeepsItsNumericValue() {
        let result = evaluate(sheetText: "0b110111011 in hex + 1", context: context())[0]
        #expect(result.display == "444")
        #expect(result.value == .decimal(Decimal(444)))
    }

    @Test
    func bindingsKeepTheValueOfAConversion() {
        let results = evaluate(sheetText: "x = 0xff\nx * 2", context: context())
        #expect(results[1].value == .decimal(Decimal(510)))
        #expect(results[1].display == "510")
    }

    // MARK: Regional labels behave like everywhere else

    @Test
    func labelIsIgnoredBeforeARegionalNumber() {
        let result = evaluate(sheetText: "compras 5 300 in sci", context: context())[0]
        #expect(result.display == "5,3E3")
        #expect(result.diagnostic == nil)
    }

    // MARK: Incomplete conversions show no message

    @Test
    func conversionCutShortShowsNoMessage() {
        let result = evaluate(sheetText: "5 in", context: context())[0]
        #expect(result.kind == .incomplete)
        #expect(result.value == nil && result.display == nil && result.diagnostic == nil)
    }

    // MARK: Unreadable input stays invalid syntax

    @Test(arguments: [
        "0b12",
        "5 in lines",
        "1,5 in hex",
    ])
    func unreadableRepresentationShowsInvalidSyntax(_ source: String) {
        let result = evaluate(sheetText: source, context: context())[0]
        #expect(result.kind == .expression)
        #expect(result.value == nil)
        #expect(result.diagnostic?.message == "Invalid syntax")
    }
}
