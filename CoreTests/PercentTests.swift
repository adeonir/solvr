@testable import Core
import Foundation
import Testing

// Percentages take numeric amounts; currency parsing stays out of scope.
// Locale, display precision, time zone, and clock are fixed per fixture
// through the EvaluationContext.

struct PercentTests {
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

    // MARK: Acceptance examples

    @Test(arguments: [
        ("52% of 900", "468"),
        ("20% off 80", "64"),
        ("10 - 40%", "6"),
        ("20% of 10", "2"),
    ])
    func individualExpressions(_ source: String, _ expected: String) {
        let results = evaluate(sheetText: source, context: context())
        #expect(results.count == 1)
        #expect(results[0].kind == .expression)
        #expect(results[0].diagnostic == nil)
        #expect(results[0].display == expected)
    }

    // MARK: The percent representation through the display contract

    @Test
    func ratioAsAPercentShowsThePercentRepresentation() {
        let result = evaluate(sheetText: "50 as a % of 100", context: context())[0]
        #expect(result.kind == .expression)
        #expect(result.diagnostic == nil)
        // The value stays numeric; only the representation shown beside the
        // expression carries the percent form.
        #expect(result.value == .decimal(0.5))
        #expect(result.display == "50%")
    }

    @Test
    func sheetShowsTheResultBesideEachExpression() {
        let sheet = """
        # Split
        52% of 900
        20% off 80
        10 - 40%
        20% of 10
        50 as a % of 100
        """
        let results = evaluate(sheetText: sheet, context: context())
        #expect(results.count == 6)
        #expect(results[0].kind == .heading)
        let evaluated = Array(results.dropFirst())
        #expect(evaluated.allSatisfy { $0.kind == .expression && $0.diagnostic == nil })
        #expect(evaluated.map(\.display) == ["468", "64", "6", "2", "50%"])
    }

    // MARK: Values stay reusable after the percent representation

    @Test
    func percentRepresentationKeepsTheNumericValueReusable() {
        let results = evaluate(
            sheetText: "x = 50 as a % of 100\nx * 100",
            context: context()
        )
        #expect(results[1].display == "50")
        #expect(results[1].diagnostic == nil)
    }

    // MARK: Regional numbers inside percent expressions

    @Test(arguments: [
        ("12,5% of 80", "10"),
        ("7,5% of 200", "15"),
    ])
    func decimalPercentsReadWithTheLocale(_ source: String, _ expected: String) {
        let result = evaluate(sheetText: source, context: context())[0]
        #expect(result.display == expected)
    }

    @Test
    func percentRoundsWithTheDisplayedDecimalPlaces() {
        let result = evaluate(sheetText: "1 as a % of 3", context: context())[0]
        #expect(result.display == "33,33%")
    }

    // MARK: Percent expressions in the full sheet structure

    @Test
    func labelKeepsThePercentExpressionValid() {
        let result = evaluate(sheetText: "desconto 20% off 80", context: context())[0]
        #expect(result.display == "64")
        #expect(result.diagnostic == nil)
    }

    @Test
    func inlineCommentLeavesThePercentExpressionUntouched() {
        let result = evaluate(sheetText: "52% of 900 // share", context: context())[0]
        #expect(result.display == "468")
    }

    @Test
    func percentErrorsStayLocalToTheirLine() {
        let results = evaluate(
            sheetText: "10 as a % of 0\n20% of 10",
            context: context()
        )
        #expect(results[0].diagnostic?.message == "Division by zero")
        #expect(results[0].value == nil)
        #expect(results[1].display == "2")
        #expect(results[1].diagnostic == nil)
    }
}
