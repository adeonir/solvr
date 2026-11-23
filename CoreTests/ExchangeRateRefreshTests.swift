import Foundation
@testable import Core
import Testing

struct ExchangeRateRefreshTests {
    @Test func replacementRatesRefreshTwoSheetsWithoutEditingTheirText() throws {
        let instant = Date(timeIntervalSince1970: 100)
        var context = try EvaluationContext(localeIdentifier: "en_US", timeZone: #require(TimeZone(secondsFromGMT: 0)), now: instant, displayPrecision: 2)
        context.exchangeRates = ExchangeRateSnapshot(base: "USD", rates: ["BRL": 5], fetchedAt: instant)
        let text = "10 USD in BRL\n2 + 2"
        var first = SheetRefresher(sheetText: text, context: context)
        var second = SheetRefresher(sheetText: "20 USD in BRL", context: context)
        #expect(first.results[0].display == "R$ 50")
        #expect(second.results[0].display == "R$ 100")
        let replacement = ExchangeRateSnapshot(base: "USD", rates: ["BRL": 6], fetchedAt: instant.addingTimeInterval(1800))
        let changed = first.update(exchangeRates: replacement, now: instant.addingTimeInterval(1800))
        second.update(exchangeRates: replacement, now: instant.addingTimeInterval(1800))
        #expect(changed.changedIndexes == [0])
        #expect(changed.results.map(\.display) == ["R$ 60", "4"])
        #expect(second.results[0].display == "R$ 120")
        #expect(first.sheetText == text)
        #expect(second.sheetText == "20 USD in BRL")
    }
}
