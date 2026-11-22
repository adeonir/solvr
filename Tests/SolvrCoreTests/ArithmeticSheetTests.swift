import Foundation
#if canImport(Core)
@testable import Core
#else
@testable import SolvrCore
#endif
import Testing

// Locale, display precision, time zone, and clock are fixed per fixture
// through the EvaluationContext.

struct ArithmeticSheetTests {
    private func context(
        locale identifier: String = "en_US",
        precision: Int = 10
    ) -> EvaluationContext {
        EvaluationContext(
            localeIdentifier: identifier,
            timeZone: TimeZone(identifier: "America/Sao_Paulo")!,
            now: Date(timeIntervalSince1970: 1_791_926_400), // 2026-10-30 00:00 UTC
            displayPrecision: precision
        )
    }

    // MARK: Basic arithmetic

    @Test(arguments: [
        ("2 + 2", "4"),
        ("2 - 5", "-3"),
        ("3 - 2", "1"),
        ("2 * 3", "6"),
        ("8 times 9", "72"),
        ("2 (3)", "6"),
        ("10 / 4", "2.5"),
    ])
    func individualExpressions(_ source: String, _ expected: String) {
        let results = evaluate(sheetText: source, context: context())
        #expect(results.count == 1)
        #expect(results[0].kind == .expression)
        #expect(results[0].diagnostic == nil)
        #expect(results[0].display == expected)
    }

    @Test
    func precedence() {
        let results = evaluate(sheetText: "2 + 3 * 4\n(2 + 3) * 4", context: context())
        #expect(results[0].display == "14" && results[1].display == "20")
    }

    @Test(arguments: [
        ("2^3^2", "512"),
        ("-2^2", "-4"),
        ("2^-2", "0.25"),
        ("10^20", "100,000,000,000,000,000,000"),
    ])
    func power(_ source: String, _ expected: String) {
        let result = evaluate(sheetText: source, context: context())[0]
        #expect(result.display == expected)
    }

    // MARK: Exact decimal values independent of display

    @Test
    func exactDecimalArithmetic() {
        let result = evaluate(sheetText: "0.1 + 0.2\nx = 0.1 + 0.2\nx", context: context())[1]
        #expect(result.value == .decimal(0.3))
        #expect(result.display == "0.3")
    }

    @Test
    func approximateValueRetainsSignificantDigits() {
        // 1 / 3 retains at least 34 significant decimal digits internally.
        let digits34 = String(repeating: "3", count: 34)
        let result = evaluate(
            sheetText: "1 / 3",
            context: context(precision: 40)
        )[0]
        #expect(result.display == "0." + digits34)
    }

    @Test
    func displayPrecisionChangesOnlyTheRepresentation() {
        let precise = context(precision: 2)
        let loose = context(precision: 40)
        #expect(evaluate(sheetText: "x = 1 / 3\nx * 3", context: precise)[0].display == "0.33")
        #expect(evaluate(sheetText: "x = 1 / 3\nx * 3", context: precise)[1].display == "1")
        // The retained value must not depend on the display precision.
        #expect(evaluate(sheetText: "x = 1 / 3\nx * 3", context: loose)[1].display == "0.9999999999999999999999999999999999")
    }

    // MARK: Numeric range

    @Test
    func supportedMagnitudeEndpointsAreAccepted() {
        let results = evaluate(sheetText: "10^127\n10^-127\n0", context: context(precision: 40))
        #expect(results.allSatisfy { $0.diagnostic == nil })
        #expect(results[0].display?.uppercased() == "1E127")
        #expect(results[1].value == .decimal(Numeric.minimumMagnitude))
        #expect(results[2].display == "0")
    }

    @Test(arguments: [
        "10^100 * 10^100",
        "10^-127 / 10",
        "10^120 * 10^120",
    ])
    func magnitudeBeyondRangeProducesNumericRangeError(_ source: String) {
        let result = evaluate(sheetText: source, context: context())[0]
        #expect(result.value == nil)
        #expect(result.diagnostic?.message == "Out of range")
    }

    // MARK: Rounding ties

    @Test
    func displayedExactTiesRoundAwayFromZero() {
        let brazillian = context(locale: "pt_BR", precision: 2)
        #expect(evaluate(sheetText: "0,125", context: brazillian)[0].display == "0,13")
        #expect(evaluate(sheetText: "-0,125", context: brazillian)[0].display == "-0,13")
    }

    @Test
    func retainedTieAt34SignificantDigitsRoundsAwayFromZero() {
        // 1.0000000000000000000000000000000005 rounded to 34 significant
        // digits is 1.000000000000000000000000000000001 (tenth of a mantissa
        // unit up), never the even neighbor.
        let tie = "1.0000000000000000000000000000000005"
        let up = "1.000000000000000000000000000000001"
        let result = evaluate(sheetText: tie, context: context(precision: 36))[0]
        #expect(result.display == up)
        #expect(evaluate(sheetText: "-" + tie, context: context(precision: 36))[0].display == "-" + up)
    }

    // MARK: Errors stay local to one expression

    @Test
    func divisionByZero_leavesIndependentExpressionsEvaluating() {
        let results = evaluate(sheetText: "1 / 0\n5 * 5", context: context())
        #expect(results[0].kind == .expression)
        #expect(results[0].value == nil)
        #expect(results[0].diagnostic?.message == "Division by zero")
        #expect(results[1].display == "25")
        #expect(results[1].diagnostic == nil)
    }

    @Test
    func syntaxErrorChecksExactText() {
        let results = evaluate(sheetText: "2 + * 3\n2 * 2", context: context())
        #expect(results[0].diagnostic == .syntax)
        #expect(results[0].diagnostic?.message == "Invalid syntax")
        #expect(results[1].display == "4")
    }

    // MARK: Incomplete expressions show no message and no stale result

    @Test(arguments: ["2 +", "min(3", "price ="])
    func incompleteExpressionsShowNoMessage(_ source: String) {
        let result = evaluate(sheetText: source, context: context())[0]
        #expect(result.value == nil)
        #expect(result.display == nil)
        #expect(result.diagnostic == nil)
    }

    @Test
    func editingValidExpressionIntoIncompleteRemovesStaleResult() {
        let before = evaluate(sheetText: "2 + 2\n3 + 3", context: context())
        #expect(before[0].display == "4")
        #expect(before[1].display == "6")
        // The same sheet edited on line 1 reevaluates from scratch: the one
        // invalid line leaves no result; nothing else changes.
        let after = evaluate(sheetText: "2 +\n3 + 3", context: context())
        #expect(after[0].kind == .incomplete)
        #expect(after[0].value == nil && after[0].diagnostic == nil)
        #expect(after[1].display == "6")
        let validAgain = evaluate(sheetText: "20 + 20\n3 + 3", context: context())
        #expect(validAgain[0].display == "40")
        #expect(validAgain[1].display == "6")
    }

    // MARK: Text lines and labels

    @Test
    func textLineShowsNoResultAndNoMessage() {
        let result = evaluate(sheetText: "compras do mês", context: context(locale: "pt_BR"))[0]
        #expect(result.kind == .textLine)
        #expect(result.value == nil && result.display == nil && result.diagnostic == nil)
    }

    @Test
    func labelIsIgnoredWhenTheRestIsValidExpression() {
        let result = evaluate(sheetText: "compras 2 + 3", context: context())[0]
        #expect(result.display == "5")
        #expect(result.diagnostic == nil)
    }

    // MARK: Headings and comments are distinguished from expressions

    @Test
    func headingAndCommentProduceNoResult() {
        let results = evaluate(sheetText: "# Section\n// purchases\ntext", context: context())
        #expect(results.count == 3)
        #expect(results[0].kind == .heading)
        #expect(results[1].kind == .comment)
        #expect(results[0].diagnostic == nil && results[1].diagnostic == nil)
        #expect(results[2].kind == .textLine)
    }

    @Test
    func inlineCommentLeavesCommentTextUnevaluated() {
        let result = evaluate(sheetText: "2 + 2 // example", context: context())[0]
        #expect(result.display == "4")
    }
}
