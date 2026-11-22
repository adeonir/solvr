import Foundation
#if canImport(Core)
@testable import Core
#else
@testable import SolvrCore
#endif
import Testing

private enum MonetaryValueFixture {
    static let half = Decimal(string: "10.5", locale: Locale(identifier: "en_US_POSIX"))!
}

struct FiatCatalogCoverageTests {
    private func context() -> EvaluationContext {
        EvaluationContext(localeIdentifier: "en_US", timeZone: TimeZone(secondsFromGMT: 0)!, now: Date(timeIntervalSince1970: 0), displayPrecision: 2)
    }

    /// Currencies the source marks without decimal places, captured 2026-10-31.
    private static let withoutDecimals: Set<String> = ["BIF", "CLP", "DJF", "GNF", "HUF", "ISK", "JPY", "KMF", "KRW", "PYG", "RWF", "UGX", "VND", "VUV", "XAF", "XOF", "XPF"]

    @Test func catalogHoldsExactly151CurrenciesWithTheirDecimalMetadata() {
        #expect(FiatCurrencies.entries.count == 151)
        #expect(Set(FiatCurrencies.entries.map(\.code)).count == 151)
        let flagged = Set(FiatCurrencies.entries.filter { !$0.hasDecimalPlaces }.map(\.code))
        #expect(flagged == Self.withoutDecimals)
    }

    @Test func everyCurrencyShowsDecimalsOnlyWhenItsMetadataAllowsThem() {
        let half = MonetaryValueFixture.half
        for entry in FiatCurrencies.entries {
            // Each currency reads at least one of the two separators as its decimal mark.
            let results = ["10.5", "10,5"].map { evaluate(sheetText: "\($0) \(entry.code)", context: context())[0] }
            let parsed = results.filter { $0.value == .monetary(MonetaryValue(amount: half, currency: entry.code)) }
            #expect(!parsed.isEmpty, "\(entry.code)")
            let display = parsed.first?.display ?? ""
            if entry.hasDecimalPlaces {
                #expect(display.hasSuffix("10.50") || display.hasSuffix("10,50"), "\(entry.code): \(display)")
            } else {
                #expect(display.hasSuffix(" 11"), "\(entry.code): \(display)")
            }
            #expect(evaluate(sheetText: "10 \(entry.code)", context: context())[0].display?.hasSuffix(" 10") == true, "\(entry.code)")
        }
    }

    @Test func everyCurrencyAcceptsItsFullName() {
        for entry in FiatCurrencies.entries {
            #expect(FiatCurrencies.names[entry.name] == entry.code, "\(entry.name)")
            let single = evaluate(sheetText: "1 \(entry.name)", context: context())[0]
            #expect(single.value == .monetary(MonetaryValue(amount: 1, currency: entry.code)), "\(entry.name)")
        }
    }

    @Test func namedSingularAndPluralFormsResolve() throws {
        let cases = [
            ("1 euro", "EUR"), ("2 euros", "EUR"), ("1 real", "BRL"), ("2 reais", "BRL"),
            ("1 danish krone", "DKK"), ("2 danish kroner", "DKK"), ("1 japanese yen", "JPY"), ("2 japanese yen", "JPY"),
            ("1 swiss franc", "CHF"), ("2 swiss francs", "CHF"), ("1 canadian dollar", "CAD"), ("2 canadian dollars", "CAD"),
            ("1 egyptian pound", "EGP"), ("2 egyptian pounds", "EGP"), ("1 south african rand", "ZAR"), ("2 SOUTH AFRICAN RAND", "ZAR")
        ]
        for (text, code) in cases {
            let first = try #require(text.first)
            let amount = try #require(Decimal(string: String(first)))
            #expect(evaluate(sheetText: text, context: context())[0].value == .monetary(MonetaryValue(amount: amount, currency: code)), "\(text)")
        }
    }

    @Test func ambiguousNamesMeanTheMostUsedCurrencyAndOthersNeedTheFullName() {
        let results = evaluate(sheetText: "1 dollar\n2 dollars\n1 pound\n2 pounds\n1 australian dollar\n1 lebanese pound", context: context())
        #expect(results.map(\.display) == ["$ 1", "$ 2", "£ 1", "£ 2", "AUD 1", "LBP 1"])
    }

    @Test func unlistedCurrenciesAreRejectedAndKeepIndependentLinesWorking() {
        let results = evaluate(sheetText: "10 ZZZ\n10 zorkmids\n10 USDX\n10 australian\n2 + 2", context: context())
        for index in 0 ..< 4 {
            #expect(results[index].diagnostic == .syntax, "line \(index)")
            #expect(results[index].value == nil, "line \(index)")
        }
        #expect(results[4].display == "4")
        #expect(FiatCurrencies.byCode["ZZZ"] == nil)
    }
}

@MainActor
struct FiatRateLifecycleCoverageTests {
    private let instant = Date(timeIntervalSince1970: 1_800_000_000)

    private func context(_ rates: ExchangeRateSnapshot) -> EvaluationContext {
        var ctx = EvaluationContext(localeIdentifier: "en_US", timeZone: TimeZone(secondsFromGMT: 0)!, now: instant, displayPrecision: 2)
        ctx.exchangeRates = rates
        return ctx
    }

    @Test func conversionsUseShippedRatesBeforeTheFirstSuccessfulFetch() async throws {
        let source = RateSource()
        await source.enqueue(.failure(.invalidResponse))
        await source.enqueue(.failure(.invalidResponse))
        let service = ExchangeRateService(source: source, cache: Cache())
        let shippedBRL = try #require(ExchangeRateSnapshot.shipped.rates["BRL"])
        let expected = evaluate(sheetText: "10 USD in BRL", context: context(.shipped))[0]
        #expect(expected.diagnostic == nil)
        #expect(expected.value == .monetary(MonetaryValue(amount: 10 * shippedBRL, currency: "BRL")))

        // Before any fetch, and after a failed first fetch, the shipped table serves the sheet.
        for _ in 0 ..< 2 {
            #expect(service.snapshot == .shipped)
            let line = evaluate(sheetText: "10 USD in BRL\n2 + 2", context: context(service.snapshot))
            #expect(line.map(\.display) == [expected.display, "4"])
            await service.setForeground(true, now: instant)
            await service.setForeground(false, now: instant)
        }
        #expect(service.lastUpdateFailed)
    }

    @Test func staleCachedRatesServeSheetsAfterAFailedUpdateAndRestart() async {
        let stale = ExchangeRateSnapshot(base: "USD", rates: ["BRL": 4], fetchedAt: instant.addingTimeInterval(-86400 * 30))
        let cache = Cache(stale)
        let source = RateSource()
        await source.enqueue(.failure(.invalidResponse))
        let service = ExchangeRateService(source: source, cache: cache)
        await service.setForeground(true, now: instant)
        #expect(service.lastUpdateFailed)
        #expect(service.snapshot == stale)
        #expect(evaluate(sheetText: "10 USD in BRL", context: context(service.snapshot))[0].display == "R$ 40")

        let restarted = ExchangeRateService(source: RateSource(), cache: cache)
        #expect(restarted.snapshot == stale)
        let results = evaluate(sheetText: "10 USD in BRL\n10 USD in AUD", context: context(restarted.snapshot))
        #expect(results[0].display == "R$ 40")
        #expect(results[1].diagnostic?.message == "Exchange rate unavailable: AUD")
    }

    @Test func fetchesOnOpenWhenRatesAreOldAndOnReturnOnlyWhenAtLeast30MinutesOld() async {
        let source = RateSource()
        let old = ExchangeRateSnapshot(base: "USD", rates: ["BRL": 4], fetchedAt: instant.addingTimeInterval(-3600))
        let service = ExchangeRateService(source: source, cache: Cache(old))
        await service.setForeground(true, now: instant)
        #expect(await source.calls == 1)
        #expect(service.snapshot.fetchedAt == instant)

        // Return with recent rates: skipped.
        await service.setForeground(false, now: instant.addingTimeInterval(60))
        await service.setForeground(true, now: instant.addingTimeInterval(1799))
        #expect(await source.calls == 1)

        // Background: skipped, however old the rates become.
        await service.setForeground(false, now: instant.addingTimeInterval(1800))
        await service.refreshIfDue(now: instant.addingTimeInterval(36000))
        #expect(await source.calls == 1)

        // Return at exactly 30 minutes: fetched.
        await service.setForeground(true, now: instant.addingTimeInterval(1800))
        #expect(await source.calls == 2)
        #expect(service.snapshot.fetchedAt == instant.addingTimeInterval(1800))
    }

    @Test func openingTheAppFetchesEvenWithRecentCachedRates() async {
        let source = RateSource()
        let service = ExchangeRateService(source: source, cache: Cache(ExchangeRateSnapshot(base: "USD", rates: ["BRL": 4], fetchedAt: instant)))
        await service.setForeground(true, now: instant.addingTimeInterval(10))
        #expect(await source.calls == 1)
    }

    @Test func sheetsShareOneServiceAndReevaluateAfterASuccessfulRefreshWithoutEditingText() async throws {
        let cache = Cache(ExchangeRateSnapshot(base: "USD", rates: ["BRL": 5], fetchedAt: instant.addingTimeInterval(-7200)))
        let source = RateSource()
        await source.enqueue(.success(ExchangeRateTable(base: "USD", rates: ["BRL": 6])))
        let service = ExchangeRateService(source: source, cache: cache)
        let firstText = "10 USD in BRL\n2 + 2"
        let secondText = "20 USD in BRL"
        var first = SheetRefresher(sheetText: firstText, context: context(service.snapshot))
        var second = SheetRefresher(sheetText: secondText, context: context(service.snapshot))
        #expect(first.results[0].display == "R$ 50")
        #expect(second.results[0].display == "R$ 100")

        await service.setForeground(true, now: instant)
        let a = first.update(exchangeRates: service.snapshot, now: instant)
        let b = second.update(exchangeRates: service.snapshot, now: instant)
        #expect(await source.calls == 1)
        #expect(a.changedIndexes == [0])
        #expect(b.changedIndexes == [0])
        #expect(first.results.map(\.display) == ["R$ 60", "4"])
        #expect(second.results.map(\.display) == ["R$ 120"])
        #expect(first.sheetText == firstText)
        #expect(second.sheetText == secondText)
        #expect(try cache.load() == service.snapshot)
    }

    @Test func aFailedRefreshChangesNoSheetResult() async {
        let cached = ExchangeRateSnapshot(base: "USD", rates: ["BRL": 5], fetchedAt: instant.addingTimeInterval(-7200))
        let source = RateSource()
        await source.enqueue(.failure(.invalidResponse))
        let service = ExchangeRateService(source: source, cache: Cache(cached))
        var sheet = SheetRefresher(sheetText: "10 USD in BRL", context: context(service.snapshot))
        await service.setForeground(true, now: instant)
        let outcome = sheet.update(exchangeRates: service.snapshot, now: instant)
        #expect(outcome.changedIndexes.isEmpty)
        #expect(sheet.results[0].display == "R$ 50")
    }
}

@MainActor
private final class Cache: ExchangeRateCache {
    var snapshot: ExchangeRateSnapshot?
    init(_ snapshot: ExchangeRateSnapshot? = nil) {
        self.snapshot = snapshot
    }

    func load() throws -> ExchangeRateSnapshot? {
        snapshot
    }

    func save(_ snapshot: ExchangeRateSnapshot) throws {
        self.snapshot = snapshot
    }
}

private actor RateSource: ExchangeRateSource {
    var calls = 0
    private var queue: [Result<ExchangeRateTable, ExchangeRateUpdateError>] = []
    func enqueue(_ response: Result<ExchangeRateTable, ExchangeRateUpdateError>) {
        queue.append(response)
    }

    func fetch() async throws -> ExchangeRateTable {
        calls += 1
        if !queue.isEmpty {
            return try queue.removeFirst().get()
        }
        return ExchangeRateTable(base: "USD", rates: ["USD": 1, "BRL": 5])
    }
}
