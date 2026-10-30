import Testing
import Foundation
@testable import NumeCore

// Complete-sheet tests for headings and comments (ADK-224). Headings and
// comments organize the sheet without evaluating their text; the evaluator
// keeps both distinguishable from expressions, per ADR-005's complete-sheet
// boundary. Locale, display precision, time zone, and clock are fixed per
// fixture through the EvaluationContext.

struct HeadingsCommentsTests {
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

    private static let headingLines = [
        "# Title",
        "## Title",
        "### Title",
        "#### Title",
        "##### Title",
        "###### Title",
    ]

    // MARK: Headings produce no numeric result

    @Test(arguments: HeadingsCommentsTests.headingLines)
    func headingProduceNoNumericResult(_ source: String) {
        let result = evaluate(sheetText: source, context: context())[0]
        #expect(result.kind == .heading)
        #expect(result.value == nil && result.display == nil)
        #expect(result.diagnostic == nil)
    }

    @Test(arguments: HeadingsCommentsTests.headingLines)
    func headingFollowedByExpressionPreservesItsResult(_ source: String) {
        let results = evaluate(sheetText: source + "\n2 + 2", context: context())
        #expect(results.count == 2)
        #expect(results[0].kind == .heading)
        #expect(results[0].value == nil && results[0].diagnostic == nil)
        #expect(results[1].kind == .expression)
        #expect(results[1].display == "4")
        #expect(results[1].diagnostic == nil)
    }

    @Test
    func headingTextIsNeverEvaluated() {
        // Expression-looking heading text and trailing marker runs do not
        // evaluate: the heading is the whole line.
        let result = evaluate(sheetText: "# 2 + 2", context: context())[0]
        #expect(result.kind == .heading)
        #expect(result.value == nil && result.display == nil && result.diagnostic == nil)
    }

    @Test
    func lineWithoutSpaceOrWithSevenMarkersIsNoHeading() {
        // Markdown headings need the space after the markers, and the
        // markers run to six: anything else follows the plain-line rule of
        // no number, operator, `=`, or known name — a text line.
        let results = evaluate(sheetText: "#Title\n####### Title", context: context())
        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.kind == .textLine })
        #expect(results.allSatisfy { $0.value == nil && $0.diagnostic == nil })
    }

    // MARK: Comments produce no result

    @Test(arguments: [
        "// purchases",
        "//",
        "// 2 + 2",
        "  // indented comment",
    ])
    func commentProduceNoResult(_ source: String) {
        let result = evaluate(sheetText: source, context: context())[0]
        #expect(result.kind == .comment)
        #expect(result.value == nil && result.display == nil)
        #expect(result.diagnostic == nil)
    }

    @Test
    func commentTextNeverEvaluatesOrErrors() {
        // Neither incomplete nor invalid comment text shows a message: the
        // comment is never evaluated.
        let results = evaluate(sheetText: "// 2 +\n// undefined_name * 2", context: context())
        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.kind == .comment })
        #expect(results.allSatisfy { $0.value == nil && $0.display == nil && $0.diagnostic == nil })
    }

    // MARK: Inline comments leave their text unevaluated

    @Test(arguments: [
        ("2 + 2 // example", "4"),
        ("2 + 2 // sqrt(-1) would-error text", "4"),
        ("price = 8 // dollars", "8"),
    ])
    func inlineCommentLeavesItsTextUnevaluated(_ source: String, _ expected: String) {
        let result = evaluate(sheetText: source, context: context())[0]
        #expect(result.kind == .expression)
        #expect(result.display == expected)
        #expect(result.diagnostic == nil)
    }

    // MARK: Headings, comments, and expressions stay distinguishable

    @Test
    func completeSheetDistinguishesHeadingsCommentsAndExpressions() {
        let results = evaluate(
            sheetText: """
            # Budget
            // weekly purchases
            2 + 2
            compras do mês
            5 * 5
            """,
            context: context(locale: "pt_BR")
        )
        #expect(results.count == 5)
        #expect(results[0].kind == .heading)
        #expect(results[1].kind == .comment)
        #expect(results[2].kind == .expression && results[2].display == "4")
        #expect(results[3].kind == .textLine)
        #expect(results[4].kind == .expression && results[4].display == "25")
        #expect(results.allSatisfy { $0.diagnostic == nil })
        #expect(results.allSatisfy { result in
            switch result.kind {
            case .heading, .comment, .textLine:
                return result.value == nil && result.display == nil
            case .expression, .incomplete:
                return true
            }
        })
    }

    @Test
    func headingsAndCommentsDoNotDisturbVariableEvaluation() {
        let results = evaluate(
            sheetText: """
            ## Banca
            price = 8
            // sempre três vezes
            price * 3
            """,
            context: context(locale: "pt_BR")
        )
        #expect(results.count == 4)
        #expect(results[0].kind == .heading)
        #expect(results[1].kind == .expression && results[1].display == "8")
        #expect(results[2].kind == .comment)
        #expect(results[3].kind == .expression && results[3].display == "24")
        #expect(results.allSatisfy { $0.diagnostic == nil })
    }
}
