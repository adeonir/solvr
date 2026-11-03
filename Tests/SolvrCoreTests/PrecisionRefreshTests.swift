import Foundation
@testable import SolvrCore
import Testing

// A precision change reaches the visible results and the total of an open
// sheet at once, with the sheet text left as it is (ADK-255). Display only:
// retained values never change (ADK-252).

struct PrecisionRefreshTests {
    private let now = Date(timeIntervalSince1970: 0)

    private func refresher(_ sheetText: String) -> SheetRefresher {
        SheetRefresher(
            sheetText: sheetText,
            context: EvaluationContext(
                localeIdentifier: "en_US",
                timeZone: TimeZone(secondsFromGMT: 0)!,
                now: now,
                displayPrecision: 2
            )
        )
    }

    @Test func generalPrecisionChangeRedisplaysResultsWithoutChangingText() {
        var sheet = refresher("1 / 3")
        #expect(sheet.results.map(\.display) == ["0.33"])

        let outcome = sheet.update(displayPrecision: 5, cryptoPrecision: 10, now: now)
        #expect(sheet.results.map(\.display) == ["0.33333"])
        #expect(outcome.changedIndexes == [0])
        #expect(sheet.sheetText == "1 / 3")

        sheet.update(displayPrecision: 1, cryptoPrecision: 10, now: now)
        #expect(sheet.results.map(\.display) == ["0.3"])
    }

    @Test func cryptoPrecisionChangeRedisplaysCryptoResultsOnly() {
        var sheet = refresher("1 BTC / 3\n1 USD / 3")

        sheet.update(displayPrecision: 2, cryptoPrecision: 5, now: now)
        #expect(sheet.results.map(\.display) == ["BTC 0.33333", "$ 0.33"])

        sheet.update(displayPrecision: 2, cryptoPrecision: 15, now: now)
        #expect(sheet.results.map(\.display) == ["BTC 0.333333333333333", "$ 0.33"])
    }

    @Test func zeroDecimalFiatIgnoresGeneralPrecision() {
        var sheet = refresher("1000 JPY / 3")
        sheet.update(displayPrecision: 1, cryptoPrecision: 10, now: now)
        #expect(sheet.results.map(\.display) == ["¥ 333"])
        sheet.update(displayPrecision: 10, cryptoPrecision: 10, now: now)
        #expect(sheet.results.map(\.display) == ["¥ 333"])
    }

    @Test func integerValuesOmitDecimalPlacesAtAnyPrecision() {
        var sheet = refresher("10 / 5\n$10 / 5\n1 BTC * 2")
        sheet.update(displayPrecision: 10, cryptoPrecision: 15, now: now)
        #expect(sheet.results.map(\.display) == ["2", "$ 2", "BTC 2"])
    }

    @Test func totalFollowsTheNewGeneralPrecisionWithoutRounding() {
        var sheet = refresher("$0.004\n$0.004\n$0.004")
        #expect(sheetTotal(of: sheet.results, context: sheet.context)?.display == "$ 0.01")

        sheet.update(displayPrecision: 3, cryptoPrecision: 10, now: now)
        #expect(sheetTotal(of: sheet.results, context: sheet.context)?.display == "$ 0.012")
        #expect(sheet.sheetText == "$0.004\n$0.004\n$0.004")
    }
}
