import Foundation
#if canImport(Core)
@testable import Core
#else
@testable import SolvrCore
#endif
import Testing

// Locale, display precision, time zone, and clock are fixed per fixture
// through the EvaluationContext.

struct FunctionsOperatorsTests {
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

    /// Whether the value differs from the independently computed reference
    /// by at most the tolerance in absolute Decimal units.
    private func approximately(
        _ expressionValue: ExpressionValue?, _ reference: Decimal, tolerance: Decimal
    ) -> Bool {
        guard case let .decimal(value) = expressionValue else { return false }
        let difference = value < reference ? reference - value : value - reference
        if difference.isNaN {
            return false
        }
        return difference <= tolerance
    }

    // MARK: Operators: arithmetic words, `&`, and `|`/`or`

    @Test(arguments: [
        ("6 and 3", "9"),
        ("6 & 3", "2"),
        ("6 | 3", "7"),
        ("6 or 3", "7"),
        ("1 + 2 & 2", "2"),
        ("1 | 2 & 0", "1"),
        ("2 * 3 and 3", "9"),
        ("(1 and 1) * 2", "4"),
    ])
    func operatorForms(_ source: String, _ expected: String) {
        let result = evaluate(sheetText: source, context: context())[0]
        #expect(result.kind == .expression)
        #expect(result.diagnostic == nil)
        #expect(result.display == expected)
    }

    /// Bitwise operands must be whole numbers, in either sign, and the
    /// two's-complement result carries the sign over.
    @Test(arguments: [
        ("255 & 15", "15"),
        ("1000 | 7", "1,007"),
        ("1000 & 7", "0"),
        ("-1 & 6", "6"),
        ("-1 | 6", "-1"),
        ("-8 & -4", "-8"),
        ("-8 | -4", "-4"),
    ])
    func bitwiseResultsAreWholeAndSigned(_ source: String, _ expected: String) {
        let result = evaluate(sheetText: source, context: context())[0]
        #expect(result.diagnostic == nil)
        #expect(result.display == expected)
    }

    // MARK: Function call forms and exact results

    @Test(arguments: [
        ("min(3; 7)", "3"),
        ("max(3; 7)", "7"),
        ("sqrt 16", "4"),
        ("sqrt(16)", "4"),
        ("fact 5", "120"),
        ("log 100", "2"),
        ("log(100)", "2"),
        ("log 2 (8)", "3"),
        ("round(2.5)", "3"),
        ("round(-2.5)", "-3"),
    ])
    func functionForms(_ source: String, _ expected: String) {
        let result = evaluate(sheetText: source, context: context())[0]
        #expect(result.diagnostic == nil)
        #expect(result.display == expected)
    }

    // MARK: Brazilian formatting, argument separators, two displayed places

    @Test(arguments: [
        ("min(1,5; 2,5)", "1,5"),
        ("sin 45°", "0,71"),
        ("log 2 (10)", "3,32"),
        ("round(2,5)", "3"),
        ("round(-2,5)", "-3"),
        ("fact 80", "7,16E118"),
    ])
    func brazilianFormatting(_ source: String, _ expected: String) {
        let result = evaluate(
            sheetText: source, context: context(locale: "pt_BR", precision: 2)
        )[0]
        #expect(result.diagnostic == nil)
        #expect(result.display == expected)
    }

    /// The base-10 logarithm divides the constant by itself, so the whole
    /// powers of ten come out exact regardless of the displayed places.
    @Test(arguments: [
        ("log 100", "2"),
        ("log(100)", "2"),
        ("log 1000", "3"),
        ("log 2 (8)", "3"),
    ])
    func wholeLogarithmsStayExact(_ source: String, _ expected: String) {
        let result = evaluate(sheetText: source, context: context(precision: 40))[0]
        #expect(result.diagnostic == nil)
        #expect(result.display == expected)
    }

    // MARK: 34-significant-digit retention

    /// `sqrt` keeps half a unit in the 34th significant digit.
    @Test
    func sqrtOfTwoRetains34SignificantDigits() throws {
        let reference = try Decimal(exact: "1.4142135623730950488016887242096980785696")
        let result = evaluate(sheetText: "sqrt 2", context: context(precision: 40))[0]
        #expect(result.diagnostic == nil)
        #expect(try approximately(result.value, reference, tolerance: Decimal(exact: "0.5e-33")))
    }

    /// `sin` and `log` keep one unit in the 34th significant digit.
    @Test
    func sinOf45DegreesRetains34SignificantDigits() throws {
        let reference = try Decimal(exact: "0.7071067811865475244008443621048490392848")
        let result = evaluate(sheetText: "sin 45°", context: context(precision: 40))[0]
        #expect(result.diagnostic == nil)
        #expect(try approximately(result.value, reference, tolerance: Decimal(exact: "1e-34")))
    }

    @Test
    func baseTwoLogarithmOfTenRetains34SignificantDigits() throws {
        let reference = try Decimal(exact: "3.3219280948873623478703194294893901758648")
        let result = evaluate(sheetText: "log 2 (10)", context: context(precision: 40))[0]
        #expect(result.diagnostic == nil)
        #expect(try approximately(result.value, reference, tolerance: Decimal(exact: "1e-33")))
    }

    @Test
    func precisionChangeLeavesTheRetainedValueAlone() {
        let tight = evaluate(sheetText: "x = sqrt 2\nx", context: context(precision: 40))
        let loose = evaluate(sheetText: "x = sqrt 2\nx", context: context(precision: 2))
        #expect(tight[0].value == loose[0].value)
        #expect(tight[1].value == loose[1].value)
    }

    // MARK: Error messages, exact text, staying local

    @Test(arguments: [
        ("sqrt()", "sqrt takes 1 argument"),
        ("sqrt(1; 2)", "sqrt takes 1 argument"),
        ("min(3)", "min takes at least 2 arguments"),
        ("log()", "log takes 1 or 2 arguments"),
    ])
    func argumentCountErrorsNameTheirFunction(_ source: String, _ message: String) {
        let results = evaluate(sheetText: source + "\n2 * 2", context: context())
        #expect(results[0].kind == .expression)
        #expect(results[0].value == nil)
        #expect(results[0].diagnostic?.message == message)
        // Independent expressions keep evaluating.
        #expect(results[1].display == "4")
        #expect(results[1].diagnostic == nil)
    }

    @Test
    func negativeSquareRootIsNoRealNumber() {
        let results = evaluate(sheetText: "sqrt(-1)\n3 * 3", context: context())
        #expect(results[0].kind == .expression)
        #expect(results[0].value == nil)
        #expect(results[0].diagnostic?.message == "Not a real number")
        #expect(results[1].display == "9")
    }

    @Test
    func factorialBeyondTheNumericRangeIsOutOfRange() {
        let results = evaluate(
            sheetText: "fact 80\nfact 85\nfact 84", context: context(precision: 40)
        )
        #expect(results[0].diagnostic == nil)
        #expect(results[1].value == nil)
        #expect(results[1].diagnostic?.message == "Out of range")
        #expect(results[2].diagnostic == nil)
    }

    // MARK: Incomplete call forms show no message

    @Test(arguments: ["sqrt", "sqrt(", "min(1", "log 2 ("])
    func incompleteCallsShowNoMessage(_ source: String) {
        let result = evaluate(sheetText: source, context: context())[0]
        #expect(result.kind == .incomplete)
        #expect(result.value == nil && result.display == nil && result.diagnostic == nil)
    }

    // MARK: The complete sheet

    @Test
    func completeSheetVerifiesFunctionsOperatorsAndErrors() {
        let source = [
            "# Functions and operators",
            "min(3; 7)",
            "max(3; 7)",
            "6 & 3",
            "6 or 3",
            "total = fact 6",
            "total",
            "sqrt(-1)",
            "4 * 4"
        ].joined(separator: "\n")
        let results = evaluate(sheetText: source, context: context())
        #expect(results.count == 9)
        #expect(results[0].kind == .heading)
        #expect(results[1].display == "3")
        #expect(results[2].display == "7")
        #expect(results[3].display == "2")
        #expect(results[4].display == "7")
        #expect(results[5].display == "720")
        #expect(results[6].display == "720")
        #expect(results[7].diagnostic?.message == "Not a real number")
        #expect(results[7].value == nil)
        #expect(results[8].display == "16")
        #expect(results[8].diagnostic == nil)
    }
}
