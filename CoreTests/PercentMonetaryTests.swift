import Foundation
@testable import Core
import Testing

// A percentage written beside a value reads that value as its base: a
// money share keeps the currency, an addition takes the base from the
// other side, and a monetary ratio converts through the exchange rate.
// Locale and display precision stay fixed per fixture through the
// EvaluationContext.

struct PercentMonetaryTests {
    private func decimal(_ text: String) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) ?? .nan
    }

    private func context(
        locale: String = "pt_BR",
        precision: Int = 2,
        rates: [String: Decimal] = [:]
    ) -> EvaluationContext {
        var context = EvaluationContext(
            localeIdentifier: locale,
            timeZone: TimeZone(secondsFromGMT: 0)!,
            now: Date(timeIntervalSince1970: 0),
            displayPrecision: precision
        )
        context.exchangeRates = ExchangeRateSnapshot(
            base: "USD", rates: rates, fetchedAt: Date(timeIntervalSince1970: 0)
        )
        return context
    }

    // MARK: Shares and portions over monetary values

    @Test(arguments: [
        ("$100 + 10%", "$ 110"),
        ("10% + $100", "$ 110"),
        ("20% of $50", "$ 10"),
        ("20% off $80", "$ 64"),
    ])
    func moneySharesAndPortions(_ source: String, _ expected: String) {
        let result = evaluate(sheetText: source, context: context())[0]
        #expect(result.kind == .expression)
        #expect(result.diagnostic == nil)
        #expect(result.display == expected)
    }

    @Test
    func portionTakesTheShareOffTheRunningMonetaryResult() {
        let results = evaluate(
            sheetText: "price = $8 times 3\nprice - 10%", context: context()
        )
        #expect(results[0].value == .monetary(MonetaryValue(amount: 24, currency: "USD")))
        #expect(results[1].value == .monetary(
            MonetaryValue(amount: decimal("21.6"), currency: "USD")
        ))
        #expect(results[1].display == "$ 21.60")
        #expect(results[1].diagnostic == nil)
    }

    // MARK: Addition reads a percentage's base from the other side

    @Test(arguments: [
        ("10 + 40%", "14"),
        ("10% + 40", "44"),
    ])
    func additionReadsThePortionBaseFromTheOtherSide(
        _ source: String, _ expected: String
    ) {
        let result = evaluate(sheetText: source, context: context())[0]
        #expect(result.diagnostic == nil)
        #expect(result.display == expected)
    }

    @Test
    func chainSharesTakeTheRunningResultAsBase() {
        let context = context(locale: "en_US", precision: 10)
        let result = evaluate(
            sheetText: "398.99 + 7.5% - 15%", context: context
        )[0]
        #expect(result.diagnostic == nil)
        #expect(result.display == "364.5771125")
    }

    // MARK: Monetary ratios in the percent representation

    @Test(arguments: [
        ("$50 as a % of $200", "25%"),
        ("R$ 50 as a % of 200", "25%"),
    ])
    func monetaryRatiosShowAsAPercent(_ source: String, _ expected: String) {
        let results = evaluate(sheetText: source, context: context())
        #expect(results[0].value == .decimal(decimal("0.25")))
        #expect(results[0].diagnostic == nil)
        #expect(results[0].display == expected)
    }

    @Test
    func distinctCurrenciesConvertThroughTheExchangeRate() {
        // The EUR rate builds the EUR→BRL cross so the ratio comes out at
        // exactly 32,5562535498% (and the EUR→USD one at exactly 22,3405%).
        let rateEUR = decimal("0.325562535498") * decimal("5.4393") / 2
        let reais = evaluate(
            sheetText: "R$ 1.000 as a % of €500",
            context: context(precision: 10, rates: ["BRL": decimal("5.4393"), "EUR": rateEUR])
        )[0]
        #expect(reais.diagnostic == nil)
        #expect(reais.display == "32,5562535498%")
        let dollars = evaluate(
            sheetText: "$50 as a % of €200",
            context: context(precision: 10, rates: ["EUR": decimal("0.89362")])
        )[0]
        #expect(dollars.diagnostic == nil)
        #expect(dollars.display == "22,3405%")
    }

    @Test
    func missingRateNamesTheCause() {
        let result = evaluate(
            sheetText: "R$ 50 as a % of €200",
            context: context(rates: ["BRL": decimal("5.4393")])
        )[0]
        #expect(result.value == nil)
        #expect(result.diagnostic?.message == "Exchange rate unavailable: EUR")
    }

    // MARK: Quantities and durations

    @Test(arguments: [
        ("15% of 200 min", "30 min", 1800),
        ("15% of 200 km", "30 km", 30),
    ])
    func sharesKeepTheBaseQuantity(_ source: String, _ expected: String, _ value: Decimal) {
        let result = evaluate(sheetText: source, context: context())[0]
        #expect(result.diagnostic == nil)
        #expect(result.value == .decimal(value))
        #expect(result.display == expected)
    }

    @Test
    func sameFamilyDurationsConvertBeforeTheRatio() {
        let result = evaluate(
            sheetText: "30 min as a % of 2 h", context: context()
        )[0]
        #expect(result.diagnostic == nil)
        #expect(result.value == .decimal(decimal("0.25")))
        #expect(result.display == "25%")
    }

    // MARK: A percentage of a percentage

    @Test
    func shareOfAShareShowsAsAPercent() {
        let result = evaluate(sheetText: "10% of 50%", context: context())[0]
        #expect(result.diagnostic == nil)
        #expect(result.value == .decimal(decimal("0.05")))
        #expect(result.display == "5%")
    }

    // MARK: Cryptocurrency

    @Test
    func cryptoJoinsThroughTheMonetaryValueConcept() {
        let result = evaluate(sheetText: "20% of 5 BTC", context: context())[0]
        #expect(result.diagnostic == nil)
        #expect(result.value == .monetary(MonetaryValue(amount: 1, currency: "BTC")))
        #expect(result.display == "BTC 1")
    }

    // MARK: Incompatible forms and the ratio of zero

    @Test(arguments: [
        ("20% of 31 Mar", "Invalid syntax"),
        ("31 Mar as a % of 200 min", "Invalid syntax"),
        ("$50 as a % of $0", "Division by zero"),
    ])
    func incompatibleFormsAndZeroBase(_ source: String, _ message: String) {
        let result = evaluate(sheetText: source, context: context())[0]
        #expect(result.value == nil)
        #expect(result.diagnostic?.message == message)
    }

    // MARK: The sheet shows each result beside its expression

    @Test
    func sheetShowsTheResultsBesideEachExpression() {
        let sheet = """
        # Prices
        price = $8 times 3
        price - 10%
        $100 + 10%
        20% of $50
        20% off $80
        $50 as a % of $200
        52% of 900
        20% off 80
        10 - 40%
        20% of 10
        50 as a % of 100
        10% of 50%
        20% of 5 BTC
        15% of 200 min
        """
        let results = evaluate(sheetText: sheet, context: context())
        #expect(results.count == 15)
        #expect(results[0].kind == .heading)
        let evaluated = Array(results.dropFirst())
        #expect(evaluated.allSatisfy { $0.kind == .expression && $0.diagnostic == nil })
        #expect(evaluated.map(\.display) == [
            "$ 24",
            "$ 21.60",
            "$ 110",
            "$ 10",
            "$ 64",
            "25%",
            "468",
            "64",
            "6",
            "2",
            "50%",
            "5%",
            "BTC 1",
            "30 min",
        ])
    }
}
