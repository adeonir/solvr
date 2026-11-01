// TimeZones (ADK-249, ADK-250): time-of-day values, the places a `in`
// conversion names, and the conversion that shows one place's clock in
// another's. A written reading anchors on the calendar date its own place
// keeps, so the place's daylight-saving rules decide the instant, and the
// result shows the destination clock as `HH:mm` alone. An abbreviation
// resolves through Foundation; a city resolves through the injected city
// data, never through the network.

import Foundation

/// A clock reading with no date, such as `11am` or `5pm` (ADK-249). The
/// hour and minute are clock fields, apart from any numeric magnitude and
/// from a calendar date.
public struct TimeOfDay: Sendable, Equatable, Hashable {
    /// The hour of the 24-hour clock, from midnight counting zero.
    public let hour: Int
    /// The minute of the hour.
    public let minute: Int

    /// The half of the day a written reading names.
    enum Meridiem: Sendable {
        case am, pm

        /// The meridiem a word spells, any casing.
        init?(word: String) {
            switch word.lowercased() {
            case "am": self = .am
            case "pm": self = .pm
            default: return nil
            }
        }
    }

    /// A reading of the 24-hour clock.
    public init?(hour: Int, minute: Int = 0) {
        guard (0 ... 23).contains(hour), (0 ... 59).contains(minute) else { return nil }
        self.hour = hour
        self.minute = minute
    }

    /// A written 12-hour reading: `12am` is midnight and `12pm` is noon.
    init?(hour: Int, minute: Int = 0, meridiem: Meridiem) {
        guard (1 ... 12).contains(hour), (0 ... 59).contains(minute) else { return nil }
        switch meridiem {
        case .am: self.hour = hour == 12 ? 0 : hour
        case .pm: self.hour = hour == 12 ? 12 : hour + 12
        }
        self.minute = minute
    }
}

/// The places a time-of-day conversion names: a time zone abbreviation
/// such as `PST`, or a city such as `London` or `sf` (ADK-249, ADK-250).
enum TimeZones {
    /// A place as the line writes it: an abbreviation Foundation resolves
    /// at parse time, or a city name the city data resolves during
    /// evaluation, when the cache is at hand.
    enum Place: Sendable, Equatable, Hashable {
        /// The zone an abbreviation names, daylight saving included.
        case zone(TimeZone)
        /// A city name or known city abbreviation, unresolved until the
        /// city data holds an outcome for it.
        case city(String)
    }

    /// The place an abbreviation names, any casing. Foundation resolves the
    /// abbreviation to the region that keeps it, so `PST` means Pacific
    /// time with daylight saving, not a fixed offset (ADK-249). nil when
    /// Foundation knows no such abbreviation.
    static func abbreviation(_ word: String) -> TimeZone? {
        guard word.allSatisfy(\.isLetter) else { return nil }
        return TimeZone(abbreviation: word.uppercased())
    }

    /// The city name an abbreviation stands for, any casing; a name that no
    /// abbreviation stands for comes back as written (ADK-250).
    static func expanded(_ city: String) -> String {
        CityTimeZones.expanded(city)
    }

    /// The words that end a place name: the language's connectors, so
    /// `11am PST in London and 2` keeps its `and 2` outside the place.
    static let connectorWords: Set<String> = ["and", "or", "to", "of", "off", "as", "at", "until", "timespan"]

    /// The place the word run spells: one abbreviation, or the city the run
    /// names, the longest run first (ADK-249).
    static func place(words: [String]) -> Place? {
        guard !words.isEmpty else { return nil }
        if words.count == 1, let zone = abbreviation(words[0]) {
            return .zone(zone)
        }
        return .city(words.joined(separator: " "))
    }

    /// The zone the place keeps: the abbreviation's zone, or the city the
    /// city data resolved. An unresolved city throws the diagnostic that
    /// names why (ADK-250).
    static func zone(of place: Place, cities: CityTimeZoneSnapshot) throws -> TimeZone {
        switch place {
        case let .zone(timeZone):
            return timeZone
        case let .city(city):
            guard let outcome = cities.outcome(for: city) else {
                throw Diagnostic.cityNotCached(name: city)
            }
            switch outcome {
            case let .found(record):
                guard let timeZone = record.timeZone else {
                    throw Diagnostic.unknownCity(name: city)
                }
                return timeZone
            case .unknown:
                throw Diagnostic.unknownCity(name: city)
            case .ambiguous:
                throw Diagnostic.ambiguousCity(name: city)
            }
        }
    }

    /// The instant the written reading has in its place, on the calendar
    /// date that place keeps for `now`: the reading anchors on the place's
    /// own date, so the place's daylight rules decide the offset (ADK-249).
    /// Foundation resolves a nonexistent or a repeated local time.
    static func instant(of time: TimeOfDay, in timeZone: TimeZone, now: Date) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        var parts = calendar.dateComponents([.year, .month, .day], from: now)
        parts.hour = time.hour
        parts.minute = time.minute
        parts.second = 0
        return calendar.date(from: parts)
    }

    /// The clock reading `instant` shows in the place.
    static func reading(of instant: Date, in timeZone: TimeZone) throws -> TimeOfDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: instant)
        guard let time = TimeOfDay(hour: parts.hour ?? 0, minute: parts.minute ?? 0) else {
            throw Diagnostic.syntax
        }
        return time
    }

    /// The time zones the sheet's visible conversions use (ADK-251): one
    /// evaluation collects the source and destination zone of every
    /// converted line, resolved as the sheet's city data resolves them. A
    /// line that could not convert uses no zone, so a place that never
    /// resolved schedules no transition.
    static func used(inSheetText sheetText: String, context: EvaluationContext) -> Set<TimeZone> {
        var evaluator = SheetEvaluator(context: context)
        _ = evaluator.evaluate(sheetText)
        return evaluator.convertedTimeZones
    }
}

// MARK: The sheet's time-of-day forms

extension SheetEvaluator {
    /// The typed value of a whole-line time-of-day form, or nil when the
    /// node carries none (ADK-249). A reading shows the destination clock,
    /// so the value carries no source instant. A reading that names no
    /// place in a conversion is read in the place the line names, and the
    /// sheet's system time zone is the destination: `5pm in London` reads
    /// 5pm in London.
    mutating func evaluateTimeOfDayForm(_ node: Node) throws -> ExpressionValue? {
        switch node {
        case let .timeOfDay(time, named):
            return try .timeOfDay(reading(of: time, in: zone(of: named)))
        case let .timeOfDayConversion(source, target):
            guard case let .timeOfDay(time, named) = source else {
                throw Diagnostic.syntax
            }
            let origin = try zone(of: named ?? target)
            let destination = named == nil ? context.timeZone : try zone(of: target)
            guard let instant = TimeZones.instant(
                of: time, in: origin, now: context.now
            ) else {
                throw Diagnostic.syntax
            }
            let converted = try TimeZones.reading(of: instant, in: destination)
            // The conversion follows the daylight-saving rules of both
            // zones, so it keeps following the next transition of either
            // (ADK-251).
            convertedTimeZones.formUnion([origin, destination])
            return .timeOfDay(converted)
        default:
            return nil
        }
    }

    /// The zone of the place the line names: the abbreviation's or city's
    /// own zone, or the sheet's system time zone when it names none.
    private func zone(of named: TimeZones.Place?) throws -> TimeZone {
        guard let named else { return context.timeZone }
        return try TimeZones.zone(of: named, cities: context.cityTimeZones)
    }

    /// The clock reading the written reading shows in its own place.
    private func reading(of time: TimeOfDay, in timeZone: TimeZone) throws -> TimeOfDay {
        guard let instant = TimeZones.instant(of: time, in: timeZone, now: context.now) else {
            throw Diagnostic.syntax
        }
        return try TimeZones.reading(of: instant, in: timeZone)
    }

    /// The representation a time-of-day result shows: the clock alone, in
    /// fixed 24-hour digits, whatever the sheet's region (ADK-249).
    func timeOfDayDisplay(_ value: ExpressionValue) -> String? {
        guard case let .timeOfDay(time) = value else { return nil }
        return String(format: "%02d:%02d", time.hour, time.minute)
    }
}
