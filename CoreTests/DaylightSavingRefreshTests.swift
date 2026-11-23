import Foundation
@testable import Core
import Testing

// A conversion schedules the next transition of the zones it uses, and
// every reevaluation trigger — including the transition itself — shows
// the clock the transition changed. The clock is injected per trigger,
// never read from the process, and no UI automation runs.

struct DaylightSavingRefreshTests {
    /// The city data the fixtures resolve city names against.
    private let cities = CityTimeZoneSnapshot(entries: [
        "London": .found(CityRecord(name: "London", country: "United Kingdom", region: "England", timeZoneIdentifier: "Europe/London", population: 8_961_989)),
        "New York": .found(CityRecord(name: "New York", country: "United States", region: "New York", timeZoneIdentifier: "America/New_York", population: 8_804_190)),
        "San Francisco": .found(CityRecord(name: "San Francisco", country: "United States", region: "California", timeZoneIdentifier: "America/Los_Angeles", population: 873_965))
    ])

    private func context(
        now: Date,
        cities: CityTimeZoneSnapshot? = nil
    ) -> EvaluationContext {
        EvaluationContext(
            localeIdentifier: "en_US",
            timeZone: TimeZone(identifier: "America/Sao_Paulo")!,
            now: now,
            displayPrecision: 2,
            cityTimeZones: cities ?? self.cities
        )
    }

    private func clock(_ description: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: description)!
    }

    private func refresher(_ sheetText: String, now: String) -> SheetRefresher {
        SheetRefresher(sheetText: sheetText, context: context(now: clock(now)))
    }

    // MARK: The acceptance example — Pacific falls back and the clock moves

    @Test
    func conversionRefreshesAtTheNextTransition() throws {
        var refresher = refresher("11am PST in London", now: "2026-10-26 09:00:00")
        #expect(refresher.results[0].display == "18:00")

        // Pacific daylight saving time ends at 09:00 UTC on 1 November
        // 2026, earlier than the next London transition.
        let transition = try #require(
            refresher.nextDaylightSavingTransition(after: refresher.context.now)
        )
        #expect(transition == clock("2026-11-01 06:00:00"))

        let outcome = refresher.refresh(.daylightSavingTransition, now: transition)
        #expect(outcome.results[0].display == "19:00")
        let expected = try #require(TimeOfDay(hour: 19))
        #expect(outcome.results[0].value == .timeOfDay(expected))
        #expect(outcome.changedIndexes == Set([0]))
    }

    /// The transition reaches the results through every existing trigger,
    /// so a transition missed while the app slept leaves no stale clock.
    @Test(arguments: [
        SheetRefreshTrigger.midnight,
        .sheetOpening,
        .returningToApp,
        .daylightSavingTransition
    ])
    func everyTriggerBringsTheConversionCurrent(_ trigger: SheetRefreshTrigger) {
        var refresher = refresher("11am PST in London", now: "2026-10-26 09:00:00")
        let outcome = refresher.refresh(trigger, now: clock("2026-11-01 06:00:00"))
        #expect(outcome.results[0].display == "19:00")
        #expect(outcome.changedIndexes == Set([0]))
    }

    // MARK: Which transition is scheduled

    /// A conversion uses both its source and its destination zone: the
    /// earliest transition among them decides. Chicago moves before London
    /// in March 2027.
    @Test
    func theEarliestTransitionOfTheUsedZonesIsScheduled() {
        let refresher = refresher("9am CST in London", now: "2026-11-01 09:00:00")
        #expect(refresher.results[0].display == "15:00")
        #expect(
            refresher.nextDaylightSavingTransition(after: refresher.context.now)
                == clock("2027-03-14 05:00:00")
        )
    }

    @Test
    func theDestinationTransitionRefreshesTheConversion() {
        var refresher = refresher("9am London in New York", now: "2026-10-30 09:00:00")
        #expect(refresher.results[0].display == "05:00")

        let transition = clock("2026-11-01 03:00:00")
        #expect(refresher.nextDaylightSavingTransition(after: refresher.context.now) == transition)

        let outcome = refresher.refresh(.daylightSavingTransition, now: transition)
        #expect(outcome.results[0].display == "04:00")
        #expect(outcome.changedIndexes == Set([0]))
    }

    /// A sheet with no conversion uses no zone: nothing to schedule, even
    /// when it shows a written reading.
    @Test
    func sheetsWithoutAConversionScheduleNoTransition() {
        let refresher = refresher("days until 31 Mar 2027\n4 * 5\n9am", now: "2026-10-26 09:00:00")
        #expect(refresher.hasTimeZoneDependentResults == false)
        #expect(refresher.nextDaylightSavingTransition(after: refresher.context.now) == nil)
    }

    // MARK: An edit updates the schedule

    @Test
    func anEditUpdatesTheScheduledTransition() {
        var refresher = refresher("4 * 5", now: "2026-10-26 09:00:00")
        #expect(refresher.nextDaylightSavingTransition(after: refresher.context.now) == nil)

        let added = refresher.update(
            sheetText: "4 * 5\n11am PST in London", now: clock("2026-10-26 09:00:00")
        )
        #expect(added.results[1].display == "18:00")
        #expect(
            refresher.nextDaylightSavingTransition(after: clock("2026-10-26 09:00:00"))
                == clock("2026-11-01 06:00:00")
        )

        _ = refresher.update(sheetText: "4 * 5", now: clock("2026-10-26 10:00:00"))
        #expect(refresher.nextDaylightSavingTransition(after: clock("2026-10-26 10:00:00")) == nil)
    }

    // MARK: Fresh city data schedules the transition

    /// A city resolved after the sheet opened turns its error into a clock
    /// and begins following that zone's transitions.
    @Test
    func freshCityDataSchedulesTheTransition() {
        var refresher = SheetRefresher(
            sheetText: "5pm ldn in sf",
            context: context(now: clock("2026-11-01 09:00:00"), cities: .empty)
        )
        #expect(refresher.results[0].diagnostic == .cityNotCached(name: "ldn"))
        #expect(refresher.nextDaylightSavingTransition(after: refresher.context.now) == nil)

        let outcome = refresher.update(cityTimeZones: cities, now: clock("2026-11-01 09:00:00"))
        #expect(outcome.results[0].display == "09:00")
        #expect(
            refresher.nextDaylightSavingTransition(after: clock("2026-11-01 09:00:00"))
                == clock("2027-03-14 07:00:00")
        )
    }
}
