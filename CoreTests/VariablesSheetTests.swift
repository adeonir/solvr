@testable import Core
import Foundation
import Testing

struct VariablesSheetTests {
    private func context(
        locale identifier: String = "pt_BR",
        precision: Int = 10
    ) -> EvaluationContext {
        EvaluationContext(
            localeIdentifier: identifier,
            timeZone: TimeZone(identifier: "America/Sao_Paulo")!,
            now: Date(timeIntervalSince1970: 1_791_926_400),
            displayPrecision: precision
        )
    }

    @Test
    func assignmentProducesItsValueAndDependentExpressionUsesIt() {
        let results = evaluate(sheetText: "price = 8\nprice * 3", context: context())
        #expect(results.count == 2)
        #expect(results[0].value == .decimal(Decimal(8)))
        #expect(results[0].display == "8")
        #expect(results[1].value == .decimal(Decimal(24)))
        #expect(results[1].display == "24")
        #expect(results.allSatisfy { $0.kind == .expression && $0.diagnostic == nil })
    }

    @Test
    func editingTheAssignmentUpdatesTheDependentResult() {
        let before = evaluate(sheetText: "price = 8\nprice * 3", context: context())
        #expect(before[0].display == "8" && before[1].display == "24")
        let after = evaluate(sheetText: "price = 10\nprice * 3", context: context())
        #expect(after[0].display == "10" && after[1].display == "30")
    }

    @Test
    func editingAnAssignmentUpdatesEveryDependentBelowIt() {
        #expect(
            evaluate(
                sheetText: "price = 8\nprice * 3\ntotal = price * 2", context: context()
            )[2].display == "16"
        )
        let results = evaluate(
            sheetText: "price = 10\nprice * 3\ntotal = price * 2", context: context()
        )
        #expect(results[1].display == "30")
        #expect(results[2].display == "20")
    }

    @Test
    func referenceBeforeItsDefinitionStaysUndefinedEvenWhenDefinedLater() {
        let results = evaluate(sheetText: "total * 2\ntotal = 10\n2 + 2", context: context())
        #expect(results.count == 3)
        #expect(results[0].kind == .expression)
        #expect(results[0].value == nil && results[0].display == nil)
        #expect(results[0].diagnostic == Diagnostic.undefinedVariable(name: "total"))
        #expect(results[0].diagnostic?.message == "Undefined variable: total")
        #expect(results[1].display == "10")
        #expect(results[2].display == "4")
    }

    @Test
    func reassignmentBindsOnlyTheLaterExpressions() {
        let results = evaluate(
            sheetText: "x = 2\nx * 3\nx = 4\nx * 3", context: context()
        )
        #expect(results.count == 4)
        #expect(results[1].value == .decimal(Decimal(6)) && results[1].display == "6")
        #expect(results[3].value == .decimal(Decimal(12)) && results[3].display == "12")
        #expect(results.allSatisfy { $0.diagnostic == nil })
    }

    @Test(arguments: [
        ("salário = 5\nsalário * 2", "10"),
        ("despesa_mensal = 4\ndespesa_mensal * 2", "8"),
        ("item2 = 3\nitem2 * 2", "6"),
    ])
    func namesAcceptAccentsUnderscoresAndDigits(_ source: String, _ expected: String) {
        let results = evaluate(sheetText: source, context: context())
        #expect(results.allSatisfy { $0.diagnostic == nil })
        #expect(results[1].display == expected)
    }

    @Test
    func accentedNamesDifferByCase() {
        let results = evaluate(
            sheetText: "Preço = 1\npreço = 2\nPreço * 2\npreço * 2", context: context()
        )
        #expect(results.count == 4)
        #expect(results[2].display == "2")
        #expect(results[3].display == "4")
        #expect(results.allSatisfy { $0.diagnostic == nil })
    }

    @Test
    func referenceUsesTheLongestCompleteDefinedName() {
        let results = evaluate(
            sheetText: "despesa = 10\ndespesa mensal = 100\ndespesa mensal * 2", context: context()
        )
        #expect(results[0].display == "10")
        #expect(results[1].display == "100")
        #expect(results[2].display == "200")
        #expect(results[2].value == .decimal(Decimal(200)))
        #expect(results.allSatisfy { $0.diagnostic == nil })
    }

    @Test(arguments: ["  ", "\t", "\u{00A0}"])
    func runsOfSpacesTabsAndNonBreakingSpacesCountAsOneSpace(_ gap: String) {
        let results = evaluate(
            sheetText: "despesa mensal = 100\ndespesa\(gap)mensal * 2", context: context()
        )
        #expect(results.count == 2)
        #expect(results[1].diagnostic == nil)
        #expect(results[1].display == "200")
    }

    @Test
    func whitespaceAtLineStartOrEndIsNotPartOfTheName() {
        let results = evaluate(
            sheetText: "despesa mensal = 100\n  despesa mensal * 2  \t", context: context()
        )
        #expect(results[1].display == "200")
        #expect(results[1].diagnostic == nil)
    }

    @Test
    func brazilianDecimalExactValueSurvivesReuse() {
        let results = evaluate(sheetText: "x = 0,1 + 0,2\nx * 3", context: context())
        #expect(results[0].value == .decimal(0.3))
        #expect(results[0].display == "0,3")
        #expect(results[1].value == .decimal(0.9))
        #expect(results[1].display == "0,9")
        #expect(results.allSatisfy { $0.diagnostic == nil })
    }

    @Test
    func displayPrecisionDoesNotChangeTheReusedValue() {
        let results = evaluate(
            sheetText: "x = 1 / 3\nx * 3", context: context(precision: 2)
        )
        #expect(results[0].display == "0,33")
        #expect(results[1].display == "1")
        #expect(results[1].value != .decimal(Decimal(1)))
        #expect(results.allSatisfy { $0.diagnostic == nil })
    }

    @Test(arguments: [
        ("min = 3", "Reserved name: min"),
        ("pi = 4", "Reserved name: pi"),
        ("and = 3", "Reserved name: and"),
        ("or = 3", "Reserved name: or"),
    ])
    func assigningAReservedNameProducesTheExactMessage(_ source: String, _ message: String) {
        let result = evaluate(sheetText: source, context: context())[0]
        #expect(result.kind == .expression)
        #expect(result.value == nil && result.display == nil)
        #expect(result.diagnostic?.message == message)
    }

    @Test
    func aReservedNameErrorBelowKeepsIndependentExpressionsEvaluating() {
        let results = evaluate(sheetText: "min = 3\n5 + 5", context: context())
        #expect(results[0].diagnostic?.message == "Reserved name: min")
        #expect(results[1].display == "10" && results[1].diagnostic == nil)
    }

    @Test
    func anErroredAssignmentBlocksItsDependentsAndLeavesOthersEvaluating() {
        let results = evaluate(
            sheetText: "sales = 1 / 0\nsales * 2\n2 + 3", context: context()
        )
        #expect(results.count == 3)
        #expect(results[0].kind == .expression)
        #expect(results[0].value == nil && results[0].display == nil)
        #expect(results[0].diagnostic?.message == "Division by zero")
        #expect(results[1].value == nil && results[1].display == nil)
        #expect(results[1].diagnostic?.message == "Depends on an error")
        #expect(results[2].display == "5" && results[2].diagnostic == nil)
    }

    @Test
    func anIncompleteAssignmentLeavesItsDependentsWithoutValidResults() {
        let results = evaluate(sheetText: "price =\nprice * 2", context: context())
        #expect(results.count == 2)
        #expect(results[0].kind == .incomplete)
        #expect(results[0].value == nil && results[0].display == nil && results[0].diagnostic == nil)
        #expect(results[1].value == nil && results[1].display == nil)
        #expect(results[1].diagnostic?.message == "Depends on an error")
    }

    @Test
    func anInvalidAssignmentLeavesItsDependentsWithoutValidResults() {
        let results = evaluate(sheetText: "price = 2 +\nprice * 4", context: context())
        #expect(results[0].kind == .incomplete)
        #expect(results[0].diagnostic == nil)
        #expect(results[1].diagnostic?.message == "Depends on an error")
    }

    @Test
    func aDefinedVariableErredThroughItsOwnExpression() {
        let results = evaluate(
            sheetText: "x = 2\nx = 1 / 0\nx * 3", context: context()
        )
        #expect(results[0].display == "2")
        #expect(results[1].diagnostic?.message == "Division by zero")
        #expect(results[2].diagnostic?.message == "Depends on an error")
    }

    @Test
    func completeSheetCoversBindingsNamesReassignmentAndPropagation() {
        let results = evaluate(
            sheetText: """
            # Compras
            salário = 100
            despesa mensal = 30
            saldo = salário - despesa mensal
            saldo * 2
            sobra = saldo / 0
            sobra + 1
            2 * 2
            total = saldo
            """,
            context: context()
        )
        #expect(results.count == 9)
        #expect(results[0].kind == .heading)
        #expect(results[1].display == "100")
        #expect(results[2].display == "30")
        #expect(results[3].display == "70")
        #expect(results[4].display == "140")
        #expect(results[5].diagnostic?.message == "Division by zero")
        #expect(results[6].diagnostic?.message == "Depends on an error")
        #expect(results[7].display == "4")
        #expect(results[8].display == "70")
    }

    @Test
    func editingAnInputUpdatesEveryDependentResultInTheSheet() {
        let before = evaluate(
            sheetText: """
            salad = 8
            salad * 3
            """,
            context: context()
        )
        #expect(before[1].display == "24")

        let after = evaluate(
            sheetText: """
            salad = 10
            salad * 3
            """,
            context: context()
        )
        #expect(after[1].display == "30")
    }
}
