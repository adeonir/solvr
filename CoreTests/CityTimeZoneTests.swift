@testable import Core
import Foundation
import Testing

// The city data arrives as an injected snapshot, so the fixtures never
// touch the network, and the external source and cache run behind fakes.

struct CityTimeZoneTests {
    private let instant = Date(timeIntervalSince1970: 1_793_524_800)

    // MARK: Fixtures

    private func record(
        _ name: String,
        _ timeZoneIdentifier: String,
        country: String = "",
        region: String = "",
        population: Int? = nil
    ) -> CityRecord {
        CityRecord(
            name: name,
            country: country,
            region: region,
            timeZoneIdentifier: timeZoneIdentifier,
            population: population
        )
    }

    /// The cached city data the fixtures resolve names against: the cities
    /// the acceptance examples name, keyed by the name Open-Meteo returns.
    private var cities: CityTimeZoneSnapshot {
        CityTimeZoneSnapshot(entries: [
            "London": .found(record("London", "Europe/London", country: "United Kingdom", region: "England", population: 8_961_989)),
            "New York": .found(record("New York", "America/New_York", country: "United States", region: "New York", population: 8_804_190)),
            "Tokyo": .found(record("Tokyo", "Asia/Tokyo", country: "Japan", region: "Tokyo", population: 8_336_599)),
            "São Paulo": .found(record("São Paulo", "America/Sao_Paulo", country: "Brazil", region: "São Paulo", population: 10_021_295)),
            "San Francisco": .found(record("San Francisco", "America/Los_Angeles", country: "United States", region: "California", population: 864_816)),
            "Atlantis": .unknown,
            "Springfield": .ambiguous
        ])
    }

    private func context(
        locale identifier: String = "en_US",
        timeZone: TimeZone = TimeZone(identifier: "America/Sao_Paulo")!,
        now: Date
    ) -> EvaluationContext {
        EvaluationContext(
            localeIdentifier: identifier,
            timeZone: timeZone,
            now: now,
            displayPrecision: 2,
            cityTimeZones: cities
        )
    }

    private func clock(
        _ description: String,
        timeZone: TimeZone = TimeZone(identifier: "America/Sao_Paulo")!
    ) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: description)!
    }

    private var november: Date {
        clock("2026-11-01 09:00:00")
    }

    private func display(_ source: String, now: Date) -> String? {
        let results = evaluate(sheetText: source, context: context(now: now))
        #expect(results.count == 1)
        #expect(results[0].diagnostic == nil)
        return results[0].display
    }

    private func diagnostic(_ source: String) -> Diagnostic? {
        evaluate(sheetText: source, context: context(now: november))[0].diagnostic
    }

    // MARK: Acceptance examples

    @Test(arguments: [
        ("9am New York in Tokyo", "23:00"),
        ("8pm Tokyo in São Paulo", "08:00"),
        ("5pm ldn in sf", "09:00"),
    ])
    func citiesConvertOnFirstNovember(_ source: String, _ expected: String) {
        #expect(display(source, now: november) == expected)
    }

    /// A reading with no place of its own is read where the line names it,
    /// and the macOS system time zone is the destination.
    @Test
    func theSystemTimeZoneIsTheDestinationOfABareReading() {
        #expect(display("5pm in London", now: november) == "14:00")
    }

    @Test
    func citiesReadWithoutTheirDiacritics() {
        #expect(display("8pm Tokyo in Sao Paulo", now: november) == "08:00")
        #expect(display("9am new york in TOKYO", now: november) == "23:00")
    }

    // MARK: City abbreviations

    /// The cache holds `San Francisco`, never `sf`: the abbreviation expands
    /// to the city name before the lookup, so the line still converts.
    @Test
    func knownAbbreviationExpandsBeforeLookup() {
        #expect(TimeZones.expanded("LDN") == "London")
        #expect(TimeZones.expanded("sf") == "San Francisco")
        #expect(TimeZones.expanded("Tokyo") == "Tokyo")
        #expect(display("5pm ldn in sf", now: november) == "09:00")
    }

    @Test
    func anAbbreviationIsReadInTheCityItNames() {
        #expect(display("5pm sf in London", now: november) == "01:00")
    }

    // MARK: City data errors

    /// A city the source reported as absent, a city with more than one
    /// plausible place, and a city never looked up each say their own thing.
    @Test
    func eachUnresolvedCityShowsItsOwnMessage() {
        #expect(diagnostic("9am Atlantis in Tokyo") == .unknownCity(name: "Atlantis"))
        #expect(diagnostic("9am Springfield in Tokyo") == .ambiguousCity(name: "Springfield"))
        #expect(diagnostic("9am Berlin in Tokyo") == .cityNotCached(name: "Berlin"))
        #expect(diagnostic("9am Tokyo in Berlin") == .cityNotCached(name: "Berlin"))
    }

    @Test
    func theCityMessagesAreShortAndDistinct() {
        let messages = Set([
            Diagnostic.unknownCity(name: "Nowhere").message,
            Diagnostic.ambiguousCity(name: "Nowhere").message,
            Diagnostic.cityNotCached(name: "Nowhere").message
        ])
        #expect(messages == ["Unknown city: Nowhere", "Ambiguous city: Nowhere", "City not cached: Nowhere"])
    }

    /// An unresolved city shows no clock and never falls back to another
    /// place or to the system time zone.
    @Test
    func anUnresolvedCityShowsNoResult() {
        let results = evaluate(sheetText: "9am Berlin in Tokyo", context: context(now: november))
        #expect(results[0].display == nil)
        #expect(results[0].value == nil)
    }

    // MARK: Lookup policy

    @Test
    func lookupTakesTheOnlyExactMatch() {
        let outcome = CityTimeZones.outcome(for: "Tokyo", records: [
            record("Tokyo", "Asia/Tokyo", country: "Japan", population: 8_336_599),
            record("Tokyo Disneyland", "Asia/Tokyo", country: "Japan", population: 0)
        ])
        #expect(outcome == .found(record("Tokyo", "Asia/Tokyo", country: "Japan", population: 8_336_599)))
    }

    /// Same-name places stay usable when one of them dwarfs the others, as
    /// `London` does; near ties, as the several `Springfield`s, stay
    /// ambiguous so no conversion picks one silently.
    @Test
    func lookupNeedsALeadingPlaceAmongSameNameMatches() {
        let dominant = CityTimeZones.outcome(for: "London", records: [
            record("London", "Europe/London", country: "United Kingdom", population: 8_961_989),
            record("London", "America/Toronto", country: "Canada", population: 422_324)
        ])
        #expect(dominant == .found(record("London", "Europe/London", country: "United Kingdom", population: 8_961_989)))
        let tie = CityTimeZones.outcome(for: "Springfield", records: [
            record("Springfield", "America/Chicago", country: "United States", population: 170_188),
            record("Springfield", "America/New_York", country: "United States", population: 154_341)
        ])
        #expect(tie == .ambiguous)
    }

    @Test
    func lookupWithoutACloseMatchIsUnknown() {
        #expect(CityTimeZones.outcome(for: "Atlantis", records: [
            record("Atlantis Resort", "Africa/Johannesburg", country: "South Africa", population: 60000)
        ]) == .unknown)
        #expect(CityTimeZones.outcome(for: "Atlantis", records: []) == .unknown)
    }

    /// A record whose time zone identifier Foundation does not know cannot
    /// resolve a place.
    @Test
    func lookupLeavesAnInvalidZoneUnresolved() {
        #expect(CityTimeZones.outcome(for: "Atlantis", records: [
            record("Atlantis", "Mars/Olympus", population: 60000)
        ]) == .unknown)
    }

    // MARK: Open-Meteo source

    @Test
    func geocodingSourceReadsOpenMeteoRecords() async throws {
        let payload = """
        {"results":[{"id":2643743,"name":"London","country":"United Kingdom","country_code":"GB",
        "admin1":"England","timezone":"Europe/London","population":8961989,"latitude":51.5,"longitude":-0.1}]}
        """
        let source = OpenMeteoGeocodingSource { request in
            #expect(request.url?.host() == "geocoding-api.open-meteo.com")
            #expect(request.url?.query()?.contains("name=S%C3%A3o%20Paulo") == true)
            return (Data(payload.utf8), 200)
        }
        let records = try await source.lookup("São Paulo")
        #expect(records == [record("London", "Europe/London", country: "United Kingdom", region: "England", population: 8_961_989)])
    }

    @Test
    func geocodingSourceReportsAnEmptyAnswerAsNoRecords() async throws {
        let source = OpenMeteoGeocodingSource { _ in (Data(#"{"generationtime_ms":0.1}"#.utf8), 200) }
        #expect(try await source.lookup("Atlantis") == [])
    }

    @Test
    func geocodingSourceReportsAFailedResponse() async {
        let failing = OpenMeteoGeocodingSource { _ in (Data("{}".utf8), 503) }
        await #expect(throws: CityLookupError.httpStatus(503)) {
            try await failing.lookup("London")
        }
        let malformed = OpenMeteoGeocodingSource { _ in (Data("not json".utf8), 200) }
        await #expect(throws: CityLookupError.invalidResponse) {
            try await malformed.lookup("London")
        }
    }

    // MARK: The city data service

    @MainActor
    @Test
    func resolvedCityIsCachedAndBecomesVisible() async throws {
        let tokyo = CityTimeZoneSnapshot(entries: [
            "Tokyo": .found(record("Tokyo", "Asia/Tokyo", country: "Japan", population: 8_336_599))
        ])
        let cache = MemoryCityCache(snapshot: tokyo)
        let source = ControlledCitySource()
        let service = CityTimeZoneService(source: source, cache: cache)
        await source.answer("London", with: [record("London", "Europe/London", country: "United Kingdom", population: 8_961_989)])
        await service.resolve(["ldn"], now: instant)
        let expected = CityTimeZoneSnapshot(entries: [
            "Tokyo": .found(record("Tokyo", "Asia/Tokyo", country: "Japan", population: 8_336_599)),
            "London": .found(record("London", "Europe/London", country: "United Kingdom", population: 8_961_989))
        ])
        #expect(service.snapshot == expected)
        #expect(try cache.load() == expected)
        // The abbreviation reaches the source as the city name it stands for.
        #expect(await source.queries == ["London"])
        // The resolved city reaches the sheet without an edit.
        var offline = context(now: november)
        offline.cityTimeZones = service.snapshot
        #expect(evaluate(sheetText: "5pm London in Tokyo", context: offline)[0].display == "02:00")
    }

    /// A failed fetch leaves the cache unchanged, so a city resolved earlier
    /// keeps converting offline.
    @MainActor
    @Test
    func failedFetchLeavesTheCachedCityDataAlone() async throws {
        let cache = MemoryCityCache(snapshot: cities)
        let source = ControlledCitySource()
        let service = CityTimeZoneService(source: source, cache: cache)
        await source.failNext()
        await service.resolve(["Berlin"], now: instant)
        #expect(service.lastUpdateFailed)
        #expect(service.snapshot == cities)
        var offline = context(now: november)
        offline.cityTimeZones = service.snapshot
        #expect(evaluate(sheetText: "5pm London in Tokyo", context: offline)[0].display == "02:00")
        #expect(try cache.load() == cities)
    }

    @MainActor
    @Test
    func restoringTheCacheKeepsCitiesResolvable() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = FileCityTimeZoneCache(url: folder.appendingPathComponent("city-time-zones.json"))
        try cache.save(cities)
        #expect(try FileCityTimeZoneCache(url: cache.url).load() == cities)
        let service = CityTimeZoneService(source: ControlledCitySource(), cache: cache)
        #expect(service.snapshot == cities)
    }

    @MainActor
    @Test
    func aCachedCityIsLookedUpAgainAndItsEntryReplaced() async {
        let cache = MemoryCityCache(snapshot: cities)
        let source = ControlledCitySource()
        await source.answer("London", with: [record("London", "Europe/Paris")])
        let service = CityTimeZoneService(source: source, cache: cache)
        await service.resolve(["London"], now: instant)
        #expect(await source.queries == ["London"])
        #expect(service.snapshot.outcome(for: "London") == .found(record("London", "Europe/Paris")))
    }

    @MainActor
    @Test
    func aCachedCityIsNotLookedUpAgainBeforeTheRecheckInterval() async {
        let cache = MemoryCityCache(snapshot: cities)
        let source = ControlledCitySource()
        let service = CityTimeZoneService(source: source, cache: cache)
        await service.resolve(["London"], now: instant)
        await service.resolve(["London"], now: instant.addingTimeInterval(60))
        #expect(await source.queries == ["London"])
        await service.resolve(["London"], now: instant.addingTimeInterval(1800))
        #expect(await source.queries == ["London", "London"])
    }

    @MainActor
    @Test
    func aFailedRefreshKeepsTheCachedEntry() async {
        let cache = MemoryCityCache(snapshot: cities)
        let source = ControlledCitySource()
        let service = CityTimeZoneService(source: source, cache: cache)
        await source.failNext()
        await service.resolve(["London"], now: instant)
        #expect(service.snapshot == cities)
    }

    @MainActor
    @Test
    func aFailedLookupIsNotRetriedWithinTheRecheckInterval() async {
        let source = ControlledCitySource()
        let service = CityTimeZoneService(source: source, cache: MemoryCityCache())
        await source.failNext()
        await service.resolve(["Berlin"], now: instant)
        await service.resolve(["Berlin"], now: instant.addingTimeInterval(60))
        #expect(await source.queries == ["Berlin"])
        await service.resolve(["Berlin"], now: instant.addingTimeInterval(1800))
        #expect(await source.queries == ["Berlin", "Berlin"])
    }

    @MainActor
    @Test
    func aCityAskedForDuringALookupIsNotDropped() async {
        let source = GatedCitySource()
        let service = CityTimeZoneService(source: source, cache: MemoryCityCache())
        let first = Task { await service.resolve(["Berlin"], now: instant) }
        await source.waitForQueries(1)
        // A second city arrives while the first lookup is still in flight.
        await service.resolve(["Lisbon"], now: instant)
        await source.openGate()
        await first.value
        #expect(await source.queries == ["Berlin", "Lisbon"])
        #expect(service.snapshot.outcome(for: "Lisbon") != nil)
    }

    @MainActor
    @Test
    func anUnknownAnswerIsCachedSoTheCityKeepsItsError() async {
        let cache = MemoryCityCache()
        let service = CityTimeZoneService(source: ControlledCitySource(), cache: cache)
        await service.resolve(["Atlantis"], now: instant)
        #expect(service.snapshot.outcome(for: "Atlantis") == .unknown)
    }

    // MARK: Reevaluation

    @Test
    func cityDataRefreshesTheVisibleResultWithoutAnEdit() {
        var context = context(now: november)
        context.cityTimeZones = .empty
        var refresher = SheetRefresher(sheetText: "5pm London in Tokyo", context: context)
        #expect(refresher.results[0].diagnostic == .cityNotCached(name: "London"))
        #expect(refresher.uncachedCityNames == ["London"])
        let outcome = refresher.update(cityTimeZones: cities, now: november)
        #expect(outcome.changedIndexes == [0])
        #expect(outcome.results[0].display == "02:00")
        #expect(refresher.uncachedCityNames.isEmpty)
    }

    @Test
    func aResolvedCityLeavesNothingToLookUp() {
        let refresher = SheetRefresher(sheetText: "5pm London in Tokyo", context: context(now: november))
        #expect(refresher.uncachedCityNames.isEmpty)
    }

    @Test
    func cityNamesCoverEveryCityTheVisibleConversionsUse() {
        let refresher = SheetRefresher(sheetText: "5pm London in Tokyo", context: context(now: november))
        #expect(refresher.cityNames == ["London", "Tokyo"])
    }

    @Test
    func anUnresolvedCityIsStillACityName() {
        var context = context(now: november)
        context.cityTimeZones = .empty
        let refresher = SheetRefresher(sheetText: "5pm London in Tokyo", context: context)
        #expect(refresher.cityNames == ["London"])
    }
}

// MARK: Fakes

@MainActor
private final class MemoryCityCache: CityTimeZoneCache {
    private var snapshot: CityTimeZoneSnapshot?

    init(snapshot: CityTimeZoneSnapshot? = nil) {
        self.snapshot = snapshot
    }

    func load() throws -> CityTimeZoneSnapshot? {
        snapshot
    }

    func save(_ snapshot: CityTimeZoneSnapshot) throws {
        self.snapshot = snapshot
    }
}

private actor ControlledCitySource: CityTimeZoneSource {
    private(set) var queries: [String] = []
    private var answers: [String: [CityRecord]] = [:]
    private var failOnce = false

    func answer(_ city: String, with records: [CityRecord]) {
        answers[city] = records
    }

    func failNext() {
        failOnce = true
    }

    func lookup(_ city: String) async throws -> [CityRecord] {
        queries.append(city)
        if failOnce {
            failOnce = false
            throw CityLookupError.invalidResponse
        }
        return answers[city] ?? []
    }
}

/// A source whose lookup waits for the test to let it finish, so a second
/// city can arrive while the first lookup is in flight.
private actor GatedCitySource: CityTimeZoneSource {
    private(set) var queries: [String] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var open = false

    func openGate() {
        open = true
        for waiter in waiters {
            waiter.resume()
        }
        waiters.removeAll()
    }

    func waitForQueries(_ count: Int) async {
        while queries.count < count {
            await Task.yield()
        }
    }

    func lookup(_ city: String) async throws -> [CityRecord] {
        queries.append(city)
        if !open {
            await withCheckedContinuation { waiters.append($0) }
        }
        return [CityRecord(name: city, timeZoneIdentifier: "Europe/London")]
    }
}
