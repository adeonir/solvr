import Foundation
#if canImport(Core)
@testable import Core
#else
#endif
import Testing

// The total follows the sheet text and the precision settings, is absent
// when no total is available, and never removes the line results or their
// diagnostics.

struct SheetTotalDisplayTests {
    private let now = Date(timeIntervalSince1970: 0)

    private func refresher(_ sheetText: String, displayPrecision: Int = 2, cryptoPrecision: Int = 10) -> SheetRefresher {
        var context = EvaluationContext(
            localeIdentifier: "en_US",
            timeZone: TimeZone(secondsFromGMT: 0)!,
            now: now,
            displayPrecision: displayPrecision
        )
        context.cryptoPrecision = cryptoPrecision
        return SheetRefresher(sheetText: sheetText, context: context)
    }

    @Test func totalIsShownForSummableResults() {
        #expect(refresher("$10\n$5").total == "$ 15")
    }

    @Test func noTotalWithoutEligibleResults() {
        #expect(refresher("").total == nil)
        #expect(refresher("hello there").total == nil)
    }

    @Test func dateAmongResultsHidesTotalAndKeepsLineResults() {
        let sheet = refresher("$10\n31 Mar 2027")
        #expect(sheet.total == nil)
        #expect(sheet.results.map(\.display) == ["$ 10", "31 March 2027"])
    }

    @Test func diagnosticLineIsLeftOutAndTotalStaysAvailable() {
        let sheet = refresher("$10\n$10 / 0\n$5")
        #expect(sheet.total == "$ 15")
        #expect(sheet.results[1].diagnostic == .divisionByZero)
        #expect(sheet.results[1].display == nil)
    }

    @Test func incompleteLineIsLeftOutAndTotalStaysAvailable() {
        let sheet = refresher("$10\n1 +\n$5")
        #expect(sheet.total == "$ 15")
        #expect(sheet.results[1].kind == .incomplete)
    }

    @Test func editingTheSheetUpdatesTheTotalWithoutChangingText() {
        var sheet = refresher("$10")
        #expect(sheet.total == "$ 10")

        sheet.update(sheetText: "$10\n$5", now: now)
        #expect(sheet.total == "$ 15")
        #expect(sheet.sheetText == "$10\n$5")

        sheet.update(sheetText: "$10\n31 Mar 2027", now: now)
        #expect(sheet.total == nil)
    }

    @Test func generalPrecisionChangeRedisplaysTheTotalWithoutChangingText() {
        var sheet = refresher("$0.004\n$0.004\n$0.004")
        #expect(sheet.total == "$ 0.01")

        sheet.update(displayPrecision: 3, cryptoPrecision: 10, now: now)
        #expect(sheet.total == "$ 0.012")
        #expect(sheet.sheetText == "$0.004\n$0.004\n$0.004")
    }

    @Test func cryptoPrecisionChangeRedisplaysTheCryptoTotal() {
        var sheet = refresher("1 BTC / 3\n1 BTC / 3")

        sheet.update(displayPrecision: 2, cryptoPrecision: 5, now: now)
        #expect(sheet.total == "BTC 0.66667")

        sheet.update(displayPrecision: 2, cryptoPrecision: 15, now: now)
        #expect(sheet.total == "BTC 0.666666666666667")
    }

    @Test func zeroDecimalFiatTotalIgnoresGeneralPrecision() {
        var sheet = refresher("1000 JPY / 3\n1000 JPY / 3")
        #expect(sheet.total == "¥ 667")

        sheet.update(displayPrecision: 10, cryptoPrecision: 10, now: now)
        #expect(sheet.total == "¥ 667")
    }
}
