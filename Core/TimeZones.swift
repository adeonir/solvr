import Foundation

/// A clock reading with no date, such as `11am` or `5pm`. The
/// hour and minute are clock fields, apart from any numeric magnitude and
/// from a calendar date.
public struct TimeOfDay: Sendable, Equatable, Hashable {
    /// The hour of the 24-hour clock, from midnight counting zero.
    public let hour: Int
    /// The minute of the hour.
    public let minute: Int

    enum Meridiem: Sendable {
        case am, pm

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

    init?(hour: Int, minute: Int = 0, meridiem: Meridiem) {
        guard (1 ... 12).contains(hour), (0 ... 59).contains(minute) else { return nil }
        switch meridiem {
        case .am: self.hour = hour == 12 ? 0 : hour
        case .pm: self.hour = hour == 12 ? 12 : hour + 12
        }
        self.minute = minute
    }
}

enum TimeZones {
    enum Place: Sendable, Equatable, Hashable {
        case zone(TimeZone)
        case city(String)
    }

    static func abbreviation(_ word: String) -> TimeZone? {
        guard word.allSatisfy(\.isLetter) else { return nil }
        return TimeZone(abbreviation: word.uppercased())
    }

    static func expanded(_ city: String) -> String {
        CityTimeZones.expanded(city)
    }

    static let connectorWords: Set<String> = ["and", "or", "to", "of", "off", "as", "at", "until", "timespan"]

    static func place(words: [String]) -> Place? {
        guard !words.isEmpty else { return nil }
        if words.count == 1, let zone = abbreviation(words[0]) {
            return .zone(zone)
        }
        return .city(words.joined(separator: " "))
    }

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

    static func reading(of instant: Date, in timeZone: TimeZone) throws -> TimeOfDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: instant)
        guard let time = TimeOfDay(hour: parts.hour ?? 0, minute: parts.minute ?? 0) else {
            throw Diagnostic.syntax
        }
        return time
    }

    struct SheetPlaces: Sendable, Equatable {
        var zones: Set<TimeZone> = []
        var cities: Set<String> = []
    }

    static func used(inSheetText sheetText: String, context: EvaluationContext) -> SheetPlaces {
        var evaluator = SheetEvaluator(context: context)
        _ = evaluator.evaluate(sheetText)
        return SheetPlaces(
            zones: evaluator.convertedTimeZones,
            cities: evaluator.convertedCities
        )
    }
}

extension SheetEvaluator {
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
            convertedTimeZones.formUnion([origin, destination])
            return .timeOfDay(converted)
        default:
            return nil
        }
    }

    private mutating func zone(of named: TimeZones.Place?) throws -> TimeZone {
        guard let named else { return context.timeZone }
        if case let .city(city) = named {
            convertedCities.insert(city)
        }
        return try TimeZones.zone(of: named, cities: context.cityTimeZones)
    }

    private func reading(of time: TimeOfDay, in timeZone: TimeZone) throws -> TimeOfDay {
        guard let instant = TimeZones.instant(of: time, in: timeZone, now: context.now) else {
            throw Diagnostic.syntax
        }
        return try TimeZones.reading(of: instant, in: timeZone)
    }

    func timeOfDayDisplay(_ value: ExpressionValue) -> String? {
        guard case let .timeOfDay(time) = value else { return nil }
        return String(format: "%02d:%02d", time.hour, time.minute)
    }
}
