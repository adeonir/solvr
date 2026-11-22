import Foundation
#if canImport(Core)
@testable import Core
#else
@testable import SolvrCore
#endif
import Testing

// Locale, time zone, display precision, and clock are fixed per fixture
// through the EvaluationContext.

struct TimeZoneConversionTests {
    /// The city data the fixtures resolve city names against: a lookup reads
    /// the injected city data, never the network.
    private let cities = CityTimeZoneSnapshot(entries: [
        "London": .found(CityRecord(name: "London", country: "United Kingdom", region: "England", timeZoneIdentifier: "Europe/London", population: 8_961_989)),
        "New York": .found(CityRecord(name: "New York", country: "United States", region: "New York", timeZoneIdentifier: "America/New_York", population: 8_804_190)),
        "São Paulo": .found(CityRecord(name: "São Paulo", country: "Brazil", region: "São Paulo", timeZoneIdentifier: "America/Sao_Paulo", population: 10_021_295))
    ])

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

    private func display(_ source: String, now: Date, locale: String = "en_US") -> String? {
        let results = evaluate(sheetText: source, context: context(locale: locale, now: now))
        #expect(results.count == 1)
        #expect(results[0].kind == .expression)
        #expect(results[0].diagnostic == nil)
        return results[0].display
    }

    // MARK: Acceptance examples

    @Test(arguments: [
        ("2026-10-26 09:00:00", "11am PST in London", "18:00"),
        ("2026-10-26 09:00:00", "11 am PST in London", "18:00"),
        ("2026-11-01 09:00:00", "9am CST in London", "15:00"),
        ("2026-11-01 09:00:00", "9am IST in London", "03:30"),
        ("2026-11-01 09:00:00", "9am BST in New York", "04:00"),
        ("2026-11-01 09:00:00", "11am PST in London", "19:00"),
    ])
    func abbreviationsConvertBetweenPlaces(
        _ clockText: String, _ source: String, _ expected: String
    ) {
        #expect(display(source, now: clock(clockText)) == expected)
    }

    /// The same written line follows the daylight-saving rules of the
    /// place its abbreviation names, not a fixed offset.
    @Test
    func pacificConversionFollowsDaylightSaving() {
        #expect(display("11am PST in London", now: clock("2026-10-26 09:00:00")) == "18:00")
        #expect(display("11am PST in London", now: clock("2026-11-01 09:00:00")) == "19:00")
    }

    // MARK: System time zone as destination

    /// A reading that names no place is read where the line names it, and
    /// the sheet's system time zone is the destination.
    @Test
    func bareTimeIsReadInThePlaceTheLineNames() {
        #expect(display("5pm in London", now: clock("2026-11-01 09:00:00")) == "14:00")
        // Naming the source place turns the same line the other way.
        #expect(display("5pm São Paulo in London", now: clock("2026-11-01 09:00:00")) == "20:00")
    }

    // MARK: Display contract

    @Test
    func conversionShowsTheClockAlone() {
        let results = evaluate(
            sheetText: "11am PST in London",
            context: context(now: clock("2026-10-26 09:00:00"))
        )
        #expect(results[0].display == "18:00")
        // The clock is fixed width and carries neither the date nor the
        // place, whatever the sheet's region.
        #expect(display("11am PST in London", now: clock("2026-10-26 09:00:00"), locale: "pt_BR") == "18:00")
        #expect(display("9am IST in London", now: clock("2026-11-01 09:00:00"), locale: "pt_BR") == "03:30")
    }

    @Test
    func minutesRideTheWrittenReading() {
        #expect(display("2:30 pm HKT in London", now: clock("2026-11-01 09:00:00")) == "06:30")
    }

    @Test
    func abbreviationAndCityReadAnyCasing() {
        #expect(display("11AM pst in london", now: clock("2026-10-26 09:00:00")) == "18:00")
    }

    // MARK: Unresolved places

    @Test
    func unknownPlaceShowsADiagnosticInsteadOfTheNumber() {
        let results = evaluate(
            sheetText: "11am XYZ in London",
            context: context(now: clock("2026-10-26 09:00:00"))
        )
        #expect(results[0].kind == .expression)
        #expect(results[0].display == nil)
        #expect(results[0].diagnostic != nil)
    }

    // MARK: The typed value

    @Test
    func valueCarriesTheDestinationClock() throws {
        let results = evaluate(
            sheetText: "11am PST in London",
            context: context(now: clock("2026-10-26 09:00:00"))
        )
        let value = try #require(results[0].value)
        let expected = try #require(TimeOfDay(hour: 18, minute: 0))
        #expect(value == .timeOfDay(expected))
    }

    /// A reading that no conversion shows keeps its written clock in the
    /// sheet's system time zone.
    @Test(arguments: [
        ("12am", "00:00"),
        ("12pm", "12:00"),
        ("9am", "09:00"),
        ("9pm", "21:00")
    ])
    func meridiemDecidesTheClockOfTheWrittenHour(_ source: String, _ expected: String) {
        #expect(display(source, now: clock("2026-10-26 09:00:00")) == expected)
    }

    @Test
    func anHourOutsideTheWrittenClockIsNoReading() {
        let results = evaluate(
            sheetText: "13pm",
            context: context(now: clock("2026-10-26 09:00:00"))
        )
        #expect(results[0].diagnostic == .syntax)
        #expect(results[0].display == nil)
    }

    /// A reading is a whole-line value: arithmetic does not consume it.
    @Test
    func arithmeticDoesNotConsumeAReading() {
        let results = evaluate(
            sheetText: "9am + 1",
            context: context(now: clock("2026-10-26 09:00:00"))
        )
        #expect(results[0].diagnostic == .syntax)
    }

    @Test
    func theMeridiemWordsStayReserved() {
        let results = evaluate(
            sheetText: "am = 5",
            context: context(now: clock("2026-10-26 09:00:00"))
        )
        #expect(results[0].diagnostic == .reservedName(name: "am"))
    }

    // MARK: Sheet total

    @Test
    func sheetTotalStaysWithoutATimeOfDayResult() {
        let evaluationContext = context(now: clock("2026-10-26 09:00:00"))
        let results = evaluate(
            sheetText: "11am PST in London", context: evaluationContext
        )
        #expect(sheetTotal(of: results, context: evaluationContext) == nil)
    }
}
