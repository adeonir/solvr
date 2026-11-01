// TimeZones (ADK-249): time-of-day values, the places a `in` conversion
// names, and the conversion that shows one place's clock in another's. A
// written reading anchors on the calendar date its own place keeps, so the
// place's daylight-saving rules decide the instant, and the result shows
// the destination clock as `HH:mm` alone.

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
/// such as `PST`, or a city such as `London` (ADK-249).
enum TimeZones {
    /// A place whose local clock rules apply to a reading.
    struct Place: Sendable, Equatable, Hashable {
        /// The zone carrying the place's rules, daylight saving included.
        let timeZone: TimeZone
    }

    /// The place an abbreviation names, any casing. Foundation resolves the
    /// abbreviation to the region that keeps it, so `PST` means Pacific
    /// time with daylight saving, not a fixed offset (ADK-249). nil when
    /// Foundation knows no such abbreviation.
    static func abbreviation(_ word: String) -> Place? {
        guard word.allSatisfy(\.isLetter) else { return nil }
        return TimeZone(abbreviation: word.uppercased()).map(Place.init(timeZone:))
    }

    /// The place the word run spells, the longest run first: an
    /// abbreviation, or a city name that a known time zone carries.
    static func place(words: [String]) -> (place: Place, count: Int)? {
        guard !words.isEmpty else { return nil }
        for length in stride(from: words.count, through: 1, by: -1) {
            let run = Array(words.prefix(length))
            if run.count == 1, let abbreviation = abbreviation(run[0]) {
                return (abbreviation, 1)
            }
            if let zone = cities[normalize(run.joined(separator: " "))] {
                return (Place(timeZone: zone), length)
            }
        }
        return nil
    }

    /// The city names the known time zones carry, keyed by the folded name
    /// of the zone's own city: `London` names `Europe/London`, `New York`
    /// names `America/New_York`, `São Paulo` names `America/Sao_Paulo`. A
    /// name that more than one zone carries stays out, so no conversion
    /// picks one of them silently.
    private static let cities: [String: TimeZone] = {
        var index: [String: TimeZone] = [:]
        var ambiguous: Set<String> = []
        for identifier in TimeZone.knownTimeZoneIdentifiers {
            guard let zone = TimeZone(identifier: identifier),
                  let city = identifier.split(separator: "/").last
            else { continue }
            let name = normalize(String(city).replacingOccurrences(of: "_", with: " "))
            if index[name] == nil {
                index[name] = zone
            } else {
                ambiguous.insert(name)
            }
        }
        for name in ambiguous {
            index.removeValue(forKey: name)
        }
        return index
    }()

    /// Folds case, diacritics, and the blanks between words, so `São Paulo`
    /// and `Sao Paulo` name the same place.
    private static func normalize(_ words: String) -> String {
        words
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }

    /// The instant the written reading has in its place, on the calendar
    /// date that place keeps for `now`: the reading anchors on the place's
    /// own date, so the place's daylight rules decide the offset (ADK-249).
    /// Foundation resolves a nonexistent or a repeated local time.
    static func instant(of time: TimeOfDay, in place: Place, now: Date) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = place.timeZone
        var parts = calendar.dateComponents([.year, .month, .day], from: now)
        parts.hour = time.hour
        parts.minute = time.minute
        parts.second = 0
        return calendar.date(from: parts)
    }

    /// The clock reading `instant` shows in the place.
    static func reading(of instant: Date, in place: Place) throws -> TimeOfDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = place.timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: instant)
        guard let time = TimeOfDay(hour: parts.hour ?? 0, minute: parts.minute ?? 0) else {
            throw Diagnostic.syntax
        }
        return time
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
            return try .timeOfDay(reading(of: time, in: place(named)))
        case let .timeOfDayConversion(source, target):
            guard case let .timeOfDay(time, named) = source else {
                throw Diagnostic.syntax
            }
            let system = TimeZones.Place(timeZone: context.timeZone)
            let origin = place(named ?? target)
            guard let instant = TimeZones.instant(
                of: time, in: origin, now: context.now
            ) else {
                throw Diagnostic.syntax
            }
            return try .timeOfDay(TimeZones.reading(of: instant, in: named == nil ? system : target))
        default:
            return nil
        }
    }

    /// The place a reading belongs to: the place it names, or the sheet's
    /// system time zone when it names none.
    private func place(_ named: TimeZones.Place?) -> TimeZones.Place {
        named ?? TimeZones.Place(timeZone: context.timeZone)
    }

    /// The clock reading the written reading shows in its own place.
    private func reading(of time: TimeOfDay, in place: TimeZones.Place) throws -> TimeOfDay {
        guard let instant = TimeZones.instant(of: time, in: place, now: context.now) else {
            throw Diagnostic.syntax
        }
        return try TimeZones.reading(of: instant, in: place)
    }

    /// The representation a time-of-day result shows: the clock alone, in
    /// fixed 24-hour digits, whatever the sheet's region (ADK-249).
    func timeOfDayDisplay(_ value: ExpressionValue) -> String? {
        guard case let .timeOfDay(time) = value else { return nil }
        return String(format: "%02d:%02d", time.hour, time.minute)
    }
}
