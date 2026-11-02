import Foundation
@testable import NumeCore
import Testing

struct MonetaryArithmeticTests {
    private func decimal(_ text: String) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) ?? .nan
    }

    /// EUR-to-USD at 2 and USD-to-BRL at 5, with a cryptocurrency.
    private func context(_ locale: String = "en_US", cryptoPrecision: Int = 10) -> EvaluationContext {
        var context = EvaluationContext(localeIdentifier: locale, timeZone: TimeZone(secondsFromGMT: 0)!, now: Date(timeIntervalSince1970: 0), displayPrecision: 2)
        context.cryptoPrecision = cryptoPrecision
        context.exchangeRates = ExchangeRateSnapshot(
            base: "USD",
            rates: ["BRL": 5, "EUR": 0.5, "BTC": Decimal(string: "0.00002")!],
            fetchedAt: Date(timeIntervalSince1970: 0)
        )
        return context
    }

    @Test func additionTakesTheCurrencyOfTheSecondValue() {
        let result = evaluate(sheetText: "$10 + 5 EUR", context: context())[0]
        #expect(result.value == .monetary(MonetaryValue(amount: 10, currency: "EUR")))
        #expect(result.display == "€ 10")
        #expect(evaluate(sheetText: "5 EUR + $10", context: context())[0].value == .monetary(MonetaryValue(amount: 20, currency: "USD")))
    }

    @Test func subtractionTakesTheCurrencyOfTheFirstValue() {
        let result = evaluate(sheetText: "$30 - 5 EUR", context: context())[0]
        #expect(result.value == .monetary(MonetaryValue(amount: 20, currency: "USD")))
        #expect(result.display == "$ 20")
    }

    @Test func inConvertsTheWholeSum() {
        let result = evaluate(sheetText: "$10 + 5 EUR in BRL", context: context())[0]
        #expect(result.value == .monetary(MonetaryValue(amount: 100, currency: "BRL")))
        #expect(result.display == "R$ 100")
    }

    @Test func divisionOfMonetaryValuesGivesANumber() {
        let results = evaluate(sheetText: "$10 / $5\n$10 / 5 EUR\n5 EUR / $10", context: context())
        #expect(results[0].value == .decimal(2))
        #expect(results[0].display == "2")
        #expect(results[1].value == .decimal(1))
        #expect(results[1].display == "1")
        #expect(results[2].value == .decimal(1))
    }

    @Test func multiplicationAndDivisionByANumberKeepTheCurrency() {
        let results = evaluate(sheetText: "$10 * 3\n3 * $10\n$10 / 4\n$10 * 5 EUR", context: context())
        #expect(results[0].value == .monetary(MonetaryValue(amount: 30, currency: "USD")))
        #expect(results[1].value == .monetary(MonetaryValue(amount: 30, currency: "USD")))
        #expect(results[2].value == .monetary(MonetaryValue(amount: 2.5, currency: "USD")))
        #expect(results[3].value == .monetary(MonetaryValue(amount: 50, currency: "EUR")))
        #expect(results[3].display == "€ 50")
    }

    @Test func invalidMonetaryCombinationsFailOnTheirLineOnly() {
        let results = evaluate(sheetText: "$10 + 5\n5 / $10\n$10 ^ 2\n$1 / 0\n$10 / 0 EUR\n2 + 2", context: context())
        #expect(results[0].diagnostic == .syntax)
        #expect(results[1].diagnostic == .syntax)
        #expect(results[2].diagnostic == .syntax)
        #expect(results[3].diagnostic == .divisionByZero)
        #expect(results[4].diagnostic == .divisionByZero)
        #expect(results[5].display == "4")
    }

    @Test func missingRateNamesTheCauseInArithmetic() {
        let results = evaluate(sheetText: "$10 + 5 AUD\n$1 + $2", context: context())
        #expect(results[0].diagnostic?.message == "Exchange rate unavailable: AUD")
        #expect(results[1].display == "$ 3")
    }

    @Test func assignedMonetaryValuesConvertAndCombine() {
        let results = evaluate(sheetText: "price = $10\nprice in BRL\nprice + 5 EUR\nratio = $10 / $5\nratio * 3\nprice * 2\ncost = price + 5 EUR\ncost in USD", context: context())
        #expect(results[0].value == .monetary(MonetaryValue(amount: 10, currency: "USD")))
        #expect(results[1].value == .monetary(MonetaryValue(amount: 50, currency: "BRL")))
        #expect(results[2].value == .monetary(MonetaryValue(amount: 10, currency: "EUR")))
        #expect(results[3].value == .decimal(2))
        #expect(results[4].value == .decimal(6))
        #expect(results[5].value == .monetary(MonetaryValue(amount: 20, currency: "USD")))
        #expect(results[7].value == .monetary(MonetaryValue(amount: 20, currency: "USD")))
    }

    @Test func calculationsKeepFullPrecisionUntilDisplay() throws {
        let results = evaluate(sheetText: "$1.005 + $1.005\n$1 / 3 * 3\n1.005 EUR * 2", context: context())
        #expect(try results[0].value == .monetary(MonetaryValue(amount: #require(Decimal(string: "2.01")), currency: "USD")))
        #expect(results[0].display == "$ 2.01")
        #expect(results[1].display == "$ 1")
        #expect(try results[2].value == .monetary(MonetaryValue(amount: #require(Decimal(string: "2.01")), currency: "EUR")))
        let precise = evaluate(sheetText: "$0.001 + $0.001\n$0.001 * 1000", context: context())
        #expect(precise[0].display == "$ 0")
        #expect(precise[1].value == .monetary(MonetaryValue(amount: 1, currency: "USD")))
    }

    @Test func totalIsInTheCurrencyOfTheLastMonetaryResult() {
        let ctx = context()
        let results = evaluate(sheetText: "$10\n5 EUR", context: ctx)
        let total = sheetTotal(of: results, context: ctx)
        #expect(total?.value == .monetary(MonetaryValue(amount: 10, currency: "EUR")))
        #expect(total?.display == "€ 10")
        let reversed = sheetTotal(of: evaluate(sheetText: "5 EUR\n$10", context: ctx), context: ctx)
        #expect(reversed?.value == .monetary(MonetaryValue(amount: 20, currency: "USD")))
    }

    @Test func totalIncludesPlainNumbersInTheSelectedCurrency() {
        let ctx = context()
        let text = "groceries\n$10\n# Heading\n// note\n2 + 2\n$10 / $5\n5 EUR"
        let total = sheetTotal(of: evaluate(sheetText: text, context: ctx), context: ctx)
        #expect(total?.value == .monetary(MonetaryValue(amount: 16, currency: "EUR")))
        #expect(sheetTotal(of: [], context: ctx) == nil)
        #expect(sheetTotal(of: evaluate(sheetText: "groceries\n// note", context: ctx), context: ctx) == nil)
    }

    @Test func compatibleTotalSkipsAnIncompatibleTemperature() {
        let ctx = context()
        let total = sheetTotal(of: evaluate(sheetText: "10 USD\n100 C\n20 USD", context: ctx), context: ctx)
        #expect(total?.value == .monetary(MonetaryValue(amount: 30, currency: "USD")))
    }

    @Test func lengthTotalUsesTheLastExplicitUnit() {
        let ctx = context()
        let forward = sheetTotal(of: evaluate(sheetText: "1 km\n500 m\n20 cm", context: ctx), context: ctx)
        #expect(forward?.value == .decimal(150_020))
        #expect(forward?.unit?.symbol == "cm")
        #expect(forward?.display == "150,020 cm")
        let reversed = sheetTotal(of: evaluate(sheetText: "20 cm\n500 m\n1 km", context: ctx), context: ctx)
        #expect(reversed?.value == .decimal(decimal("1.5002")))
        #expect(reversed?.unit?.symbol == "km")
    }

    @Test func plainNumbersJoinTheSelectedUnitOrCurrency() {
        let ctx = context()
        let length = sheetTotal(of: evaluate(sheetText: "5 km\n20\n10", context: ctx), context: ctx)
        #expect(length?.value == .decimal(35))
        #expect(length?.unit?.symbol == "km")
        let money = sheetTotal(of: evaluate(sheetText: "5 USD\n10", context: ctx), context: ctx)
        #expect(money?.value == .monetary(MonetaryValue(amount: 15, currency: "USD")))
        let plain = sheetTotal(of: evaluate(sheetText: "2\n3", context: ctx), context: ctx)
        #expect(plain?.value == .decimal(5))
        #expect(plain?.unit == nil)
    }

    @Test func eachResultCountsOnceIncludingReferences() {
        let ctx = context()
        let total = sheetTotal(of: evaluate(sheetText: "x = 10\nx * 2", context: ctx), context: ctx)
        #expect(total?.value == .decimal(30))
    }

    @Test func singleAndZeroResultsStillTotal() {
        let ctx = context()
        #expect(sheetTotal(of: evaluate(sheetText: "10", context: ctx), context: ctx)?.value == .decimal(10))
        #expect(sheetTotal(of: evaluate(sheetText: "0", context: ctx), context: ctx)?.value == .decimal(0))
        #expect(sheetTotal(of: evaluate(sheetText: "10\n-10", context: ctx), context: ctx)?.display == "0")
    }

    @Test func calendarDifferencesParticipateAsDays() {
        let ctx = context()
        let total = sheetTotal(of: evaluate(sheetText: "days until 31 Mar\n1", context: ctx), context: ctx)
        #expect(total?.value == .decimal(90))
    }

    @Test func timeOfDayAmongTheResultsSuppressesTheTotal() {
        let ctx = context()
        #expect(sheetTotal(of: evaluate(sheetText: "$10\n9am", context: ctx), context: ctx) == nil)
    }

    @Test func invalidAndIncompleteResultsAreLeftOut() {
        let ctx = context()
        let total = sheetTotal(of: evaluate(sheetText: "$10\n5 +\nfoo bar", context: ctx), context: ctx)
        #expect(total?.value == .monetary(MonetaryValue(amount: 10, currency: "USD")))
    }

    @Test func precisionAffectsDisplayOnly() {
        let ctx = context()
        let total = sheetTotal(of: evaluate(sheetText: "0.004\n0.004\n0.004", context: ctx), context: ctx)
        #expect(total?.value == .decimal(decimal("0.012")))
        #expect(total?.display == "0.01")
    }

    @Test func roundingTiesAwayFromZero() {
        let ctx = context()
        #expect(sheetTotal(of: evaluate(sheetText: "0.005", context: ctx), context: ctx)?.display == "0.01")
        #expect(sheetTotal(of: evaluate(sheetText: "-0.005", context: ctx), context: ctx)?.display == "-0.01")
    }

    @Test func zeroDecimalCurrencyIgnoresGeneralPrecision() {
        let ctx = context()
        let total = sheetTotal(of: evaluate(sheetText: "1000.4 JPY\n1", context: ctx), context: ctx)
        #expect(total?.display?.contains(".") == false)
    }

    @Test func sumOutOfRangeShowsNoTotal() {
        let ctx = context()
        let large = decimal("9e126")
        let results = [
            ExpressionResult(kind: .expression, value: .decimal(large)),
            ExpressionResult(kind: .expression, value: .decimal(large))
        ]
        #expect(sheetTotal(of: results, context: ctx) == nil)
    }

    @Test func totalInACryptocurrencyUsesTheCryptoPrecision() {
        for (precision, expected) in [(5, "BTC 1.50000"), (10, "BTC 1.5000000000"), (15, "BTC 1.500000000000000")] {
            let ctx = context(cryptoPrecision: precision)
            let total = sheetTotal(of: evaluate(sheetText: "1 BTC\n0.5 BTC", context: ctx), context: ctx)
            #expect(total?.display == expected)
        }
        let ctx = context(cryptoPrecision: 5)
        let converted = sheetTotal(of: evaluate(sheetText: "$1\n1 BTC", context: ctx), context: ctx)
        #expect(converted?.display == "BTC 1.00002")
    }

    @Test func totalWithoutARateShowsNoTotal() {
        var ctx = context()
        let results = evaluate(sheetText: "$10\n5 EUR", context: ctx)
        ctx.exchangeRates = ExchangeRateSnapshot(base: "USD", rates: [:], fetchedAt: Date(timeIntervalSince1970: 0))
        #expect(sheetTotal(of: results, context: ctx) == nil)
    }

    @Test func totalIsNotShownWithADateAmongTheResults() {
        let ctx = context()
        #expect(sheetTotal(of: evaluate(sheetText: "$10\n31 Mar 2027", context: ctx), context: ctx) == nil)
    }

    @Test func durationsTotalInTheirTimeUnit() {
        let ctx = context()
        let total = sheetTotal(of: evaluate(sheetText: "2 hours\n3 hours", context: ctx), context: ctx)
        #expect(total?.value == .decimal(5))
        #expect(total?.display == "5 hours")
    }

    @Test func lastExplicitTimeUnitDeterminesTheTimeTotal() {
        let ctx = context()
        let total = sheetTotal(of: evaluate(sheetText: "1 day\n2 hours", context: ctx), context: ctx)
        #expect(total?.value == .decimal(26))
        #expect(total?.display == "26 hours")
        let reversed = sheetTotal(of: evaluate(sheetText: "2 hours\n1 day", context: ctx), context: ctx)
        #expect(reversed?.display == "1.08 days")
    }

    @Test func cssRelativeTotalsSumThroughTheSharedPixelBase() {
        let ctx = context()
        let total = sheetTotal(of: evaluate(sheetText: "1 em\n1 rem", context: ctx), context: ctx)
        #expect(total?.value == .decimal(2))
        #expect(total?.display == "2rem")
        let mixed = sheetTotal(of: evaluate(sheetText: "16px\n1 rem", context: ctx), context: ctx)
        #expect(mixed?.value == .decimal(2))
        #expect(mixed?.display == "2rem")
        let pixels = sheetTotal(of: evaluate(sheetText: "1 rem\n16px", context: ctx), context: ctx)
        #expect(pixels?.value == .decimal(32))
        #expect(pixels?.display == "32px")
    }

    @Test func cssRelativeValuesCountTheirOwnUnit() {
        let ctx = context()
        #expect(evaluate(sheetText: "1 rem", context: ctx)[0].value == .decimal(1))
        #expect(evaluate(sheetText: "1 rem", context: ctx)[0].measure == .unit(.rem))
        #expect(evaluate(sheetText: "16px in em", context: ctx)[0].value == .decimal(1))
        #expect(evaluate(sheetText: "16px in em", context: ctx)[0].measure == .unit(.em))
    }

    @Test func assignedQuantitiesTotalThroughTheirReferences() {
        let ctx = context()
        let total = sheetTotal(of: evaluate(sheetText: "x = 10 km\nx * 2", context: ctx), context: ctx)
        #expect(total?.value == .decimal(30))
        #expect(total?.display == "30 km")
    }

    @Test func timeQuantitiesSkipIncompatibleMoney() {
        let ctx = context()
        let total = sheetTotal(of: evaluate(sheetText: "5 USD\n2 hours\n3 hours", context: ctx), context: ctx)
        #expect(total?.value == .decimal(5))
        #expect(total?.display == "5 hours")
    }
}
