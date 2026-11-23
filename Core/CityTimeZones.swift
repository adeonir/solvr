// The city data a time-of-day conversion resolves a city name against. A
// lookup leaves one outcome per city in the cache — the place it resolved,
// no place of that name, or more than one plausible place — so the
// evaluator can tell an unknown city from a city that was never looked up
// without reaching the network.

import Foundation

/// One city record as the external city data source returns it.
/// The identity fields keep enough context to revisit or show the place.
public struct CityRecord: Sendable, Equatable, Codable {
    public let name: String
    public let country: String?
    public let region: String?
    /// The time zone database identifier the place keeps, e.g.
    /// `America/New_York`.
    public let timeZoneIdentifier: String
    public let population: Int?

    public init(
        name: String,
        country: String? = nil,
        region: String? = nil,
        timeZoneIdentifier: String,
        population: Int? = nil
    ) {
        self.name = name
        self.country = country
        self.region = region
        self.timeZoneIdentifier = timeZoneIdentifier
        self.population = population
    }

    /// The zone the record names, or nil when the identifier is not one the
    /// system knows.
    public var timeZone: TimeZone? {
        TimeZone(identifier: timeZoneIdentifier)
    }
}

/// What one city lookup left behind: the place it resolved, no place of
/// that name, or more than one place the name could mean.
public enum CityLookupOutcome: Sendable, Equatable, Codable {
    case found(CityRecord)
    case unknown
    case ambiguous
}

/// The city data the evaluator reads: one outcome per looked-up city, keyed
/// by the folded city name. The application persists it, so a city resolved
/// before keeps converting without a connection.
public struct CityTimeZoneSnapshot: Sendable, Equatable, Codable {
    public let entries: [String: CityLookupOutcome]

    public init(entries: [String: CityLookupOutcome] = [:]) {
        self.entries = entries.reduce(into: [:]) { folded, entry in
            folded[CityTimeZones.key(entry.key)] = entry.value
        }
    }

    public static let empty = CityTimeZoneSnapshot()

    public var isEmpty: Bool {
        entries.isEmpty
    }

    /// The outcome of the city name's earlier lookup, or nil when it was
    /// never looked up. The name matches any casing, without diacritics,
    /// and through its known abbreviation.
    public func outcome(for city: String) -> CityLookupOutcome? {
        entries[CityTimeZones.key(city)]
    }

    /// The same city data with one lookup's outcome recorded.
    public func recording(_ outcome: CityLookupOutcome, for city: String) -> CityTimeZoneSnapshot {
        var entries = entries
        entries[CityTimeZones.key(city)] = outcome
        return CityTimeZoneSnapshot(entries: entries)
    }
}

/// The city name rules and the lookup policy, apart from the network and
/// the disk.
enum CityTimeZones {
    /// The abbreviations the language expands to a city name before the
    /// lookup: `ldn` reads London and `sf` reads San Francisco.
    static let aliasNames: [String: String] = ["ldn": "London", "sf": "San Francisco"]

    /// The city name an abbreviation stands for, any casing; a name that no
    /// abbreviation stands for comes back as written.
    static func expanded(_ city: String) -> String {
        aliasNames[folded(city)] ?? city
    }

    /// The cache key of a city name: case, diacritics, the abbreviation it
    /// stands for, and the blanks between words all fold away, so
    /// `São Paulo`, `sao paulo`, and `SAO PAULO` name one place.
    static func key(_ city: String) -> String {
        folded(expanded(city))
    }

    static func folded(_ name: String) -> String {
        name
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }

    /// The outcome one lookup's records leave for the city: a place whose
    /// name matches exactly, when the name means one place. Same-name
    /// places stay usable while one of them dwarfs the others — `London`
    /// names the British city, not the Canadian one — and stay ambiguous
    /// when they are near ties, as the several `Springfield`s are.
    static func outcome(for city: String, records: [CityRecord]) -> CityLookupOutcome {
        let name = key(city)
        let matches = records
            .filter { folded($0.name) == name && $0.timeZone != nil }
            .sorted { ($0.population ?? 0) > ($1.population ?? 0) }
        guard let leading = matches.first else { return .unknown }
        guard matches.count > 1 else { return .found(leading) }
        let runnerUp = matches[1].population ?? 0
        guard let population = leading.population,
              population > 0, population >= 2 * runnerUp
        else { return .ambiguous }
        return .found(leading)
    }
}
